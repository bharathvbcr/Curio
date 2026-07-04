package com.example.data.embedding

import android.util.Log
import com.example.domain.model.Bookmark
import com.google.ai.edge.localagents.rag.models.EmbedData
import com.google.ai.edge.localagents.rag.models.EmbeddingRequest
import com.google.ai.edge.localagents.rag.models.GemmaEmbeddingModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * A pluggable text-embedding backend. Like [com.example.data.ai.TextGenerator] for generation,
 * this interface is what gets injected so the on-device and cloud embedding paths are fully
 * interchangeable and the on-device path can be device-gated.
 */
interface EmbeddingProvider {
    suspend fun embedDocument(bookmark: Bookmark): FloatArray?
    suspend fun embedQuery(query: String): FloatArray?
    /** True when embeddings are computed on-device (no network / fully private). */
    fun isOnDevice(): Boolean
    /** Reason the most recent embed returned null (for the UI), or null if none/not tracked. */
    val lastError: String? get() = null
}

/** Shared document-text assembly so on-device and cloud embed the *same* text for a bookmark. */
object EmbeddingText {
    /**
     * On-device weights are `embeddinggemma-300M_seq256_*`: 256 tokenizer positions total.
     * [com.google.ai.edge.localagents.rag.models.GemmaEmbeddingModel] throws (no truncation) when
     * `token.size() + 2 > 256`. Task prefixes cost ~10–30 tokens; ~480 chars stays safely under
     * the limit for typical English (and most mixed text).
     */
    const val MAX_EMBED_CHARS = 480
    /** Larger chunks for the cloud embedder (xAI accepts up to ~8k chars per call). */
    const val CLOUD_CHUNK_CHARS = 800
    private const val MAX_CHUNKS = 4

    /** Minimum char window when backing off from a seq256 token-limit error. */
    const val MIN_EMBED_CHARS = 64

    /** Hard cap applied immediately before each on-device inference (queries + document chunks). */
    fun clipForOnDevice(text: String): String = text.trim().take(MAX_EMBED_CHARS)

    /** True when [GemmaEmbeddingModel] rejected input for exceeding the seq256 window. */
    fun isTokenLimitError(e: Throwable): Boolean =
        generateSequence(e) { it.cause }.any { t ->
            val msg = t.message.orEmpty()
            msg.contains("max_input_size", ignoreCase = true) ||
                msg.contains("token.size()", ignoreCase = true)
        }

    fun forDocument(b: Bookmark): String = buildString {
        b.sourceTitle?.let { append(it); append(". ") }
        b.sourceAbstract?.let { append(it.take(1000)); append(" ") }
        b.summary?.let { append(it); append(" ") }
        if (b.tags.isNotEmpty()) { append(b.tags.joinToString(" ")); append(" ") }
        b.entities?.let { append(it.replace(Regex("[\"{}\\[\\]]"), " ").take(200)); append(" ") }
        append(b.text.take(500))
    }.trim().ifBlank { b.text }

    /**
     * Splits a document into up to [MAX_CHUNKS] retrieval chunks so long papers don't lose their
     * body content the way single-vector truncation did. Chunk 1 is the high-signal header
     * (title + abstract + summary); the rest window over the body. The per-chunk vectors are
     * mean-pooled by the provider into one vector, so the storage schema is unchanged.
     */
    fun chunksForDocument(b: Bookmark, chunkChars: Int = MAX_EMBED_CHARS): List<String> {
        val safeChunk = chunkChars.coerceAtLeast(MIN_EMBED_CHARS)
        val header = buildString {
            b.sourceTitle?.let { append(it); append(". ") }
            b.sourceAbstract?.let { append(it); append(" ") }
            b.summary?.let { append(it); append(" ") }
            if (b.tags.isNotEmpty()) { append(b.tags.joinToString(" ")); append(" ") }
        }.trim()
        val chunks = mutableListOf<String>()
        if (header.isNotBlank()) chunks.add(header.take(safeChunk))
        val body = b.text.trim()
        var i = 0
        while (i < body.length && chunks.size < MAX_CHUNKS) {
            chunks.add(body.substring(i, minOf(i + safeChunk, body.length)))
            i += safeChunk
        }
        return chunks.ifEmpty { listOf(forDocument(b).take(safeChunk)) }
    }

    /**
     * Element-wise mean of per-chunk vectors → one document vector (cosine similarity normalises,
     * so no extra L2 step is needed). Vectors of a differing dimension are not pooled (returns the
     * first), guarding against mixing incompatible embedding sizes.
     */
    fun meanPool(vectors: List<FloatArray>): FloatArray? {
        val nonEmpty = vectors.filter { it.isNotEmpty() }
        if (nonEmpty.isEmpty()) return null
        val dim = nonEmpty.first().size
        if (nonEmpty.any { it.size != dim }) return nonEmpty.first()
        val acc = FloatArray(dim)
        for (v in nonEmpty) for (j in 0 until dim) acc[j] += v[j]
        for (j in 0 until dim) acc[j] /= nonEmpty.size
        return acc
    }
}

/**
 * Detects whether the on-device EmbeddingGemma model is present. The runtime (Google AI Edge RAG
 * library) is always on the classpath; availability therefore reduces to "have the weights +
 * tokenizer been downloaded?", which [EmbeddingModelManager] answers. We never assume the model is
 * present — absence routes to the cloud provider.
 */
class EmbeddingAvailability(private val modelManager: EmbeddingModelManager) {
    fun isEmbeddingGemmaAvailable(): Boolean = modelManager.isReady()
}

/**
 * On-device EmbeddingGemma backend via the AI Edge RAG [GemmaEmbeddingModel] (LiteRT weights +
 * SentencePiece tokenizer). Gated by [EmbeddingAvailability]: returns null when the model isn't
 * downloaded so the selector falls back to the cloud provider.
 *
 * Requires `localagents-rag` ≥ 0.3.0 — older releases only ship [GeckoEmbeddingModel] for Gecko
 * weights; running EmbeddingGemma `.tflite` through Gecko fails at inference ("On-device embed failed").
 *
 * EmbeddingGemma is task-aware — documents are embedded with [EmbedData.TaskType.RETRIEVAL_DOCUMENT]
 * and queries with [EmbedData.TaskType.RETRIEVAL_QUERY] so query/document vectors align. Inference
 * runs on CPU (`useGpu = false`): the GPU path is known to emit all-zero vectors unless precision is
 * forced to FP32, so CPU is the safe default.
 */
class OnDeviceEmbeddingProvider(
    private val availability: EmbeddingAvailability,
    private val modelManager: EmbeddingModelManager
) : EmbeddingProvider {

    @Volatile private var model: GemmaEmbeddingModel? = null

    @Volatile override var lastError: String? = null
        private set

    // A single GemmaEmbeddingModel wraps one LiteRT interpreter, which is not safe to invoke
    // concurrently. The background backfill worker and a foreground search query can both reach this
    // shared instance at once, so inference is serialized.
    private val inferenceLock = Mutex()

    override fun isOnDevice(): Boolean = availability.isEmbeddingGemmaAvailable()

    override suspend fun embedDocument(bookmark: Bookmark): FloatArray? {
        if (!availability.isEmbeddingGemmaAvailable()) {
            lastError = "On-device EmbeddingGemma model not downloaded (Settings → Download model)."
            return null
        }
        // Chunk long documents and mean-pool the per-chunk vectors so body content is retained.
        val vectors = EmbeddingText.chunksForDocument(bookmark)
            .mapNotNull { embed(it, EmbedData.TaskType.RETRIEVAL_DOCUMENT) }
        val pooled = EmbeddingText.meanPool(vectors)
        if (pooled != null) lastError = null
        else if (lastError == null) lastError = "On-device embedding returned no vector."
        return pooled
    }

    override suspend fun embedQuery(query: String): FloatArray? =
        embed(query, EmbedData.TaskType.RETRIEVAL_QUERY)

    private suspend fun ensureModel(): GemmaEmbeddingModel? {
        model?.let { return it }
        if (!availability.isEmbeddingGemmaAvailable()) return null
        return inferenceLock.withLock {
            // Double-check: another coroutine may have initialised the model while we waited for
            // the lock, so skip redundant construction.
            if (model != null) return@withLock model
            runCatching {
                GemmaEmbeddingModel(
                    modelManager.modelFile().absolutePath,
                    modelManager.tokenizerFile().absolutePath,
                    /* useGpu = */ false
                ).also { model = it }
            }.onFailure { e ->
                Log.e(TAG, "Failed to load EmbeddingGemma: ${e.message}", e)
                lastError = buildString {
                    append("On-device model load failed: ${e.message ?: "unknown error"}")
                    if (!modelManager.isValidModelFile()) {
                        append(". The weights file looks corrupt — delete the model in Settings and re-download.")
                    } else {
                        append(". Try deleting the model in Settings and re-downloading.")
                    }
                }
            }.getOrNull()
        }
    }

    private suspend fun embed(text: String, task: EmbedData.TaskType): FloatArray? =
        withContext(Dispatchers.IO) {
            val m = ensureModel() ?: return@withContext null
            var charLimit = EmbeddingText.MAX_EMBED_CHARS
            while (charLimit >= EmbeddingText.MIN_EMBED_CHARS) {
                val clipped = text.trim().take(charLimit)
                if (clipped.isBlank()) return@withContext null
                try {
                    val request = EmbeddingRequest.create(
                        listOf(EmbedData.create<String>(clipped, task))
                    )
                    val vector = inferenceLock.withLock { m.getEmbeddings(request).get() }
                    if (vector.isNullOrEmpty()) {
                        lastError = "On-device EmbeddingGemma returned an empty vector."
                        Log.w(TAG, lastError!!)
                        return@withContext null
                    }
                    lastError = null
                    return@withContext FloatArray(vector.size) { vector[it] }
                } catch (e: Exception) {
                    if (e is kotlinx.coroutines.CancellationException) throw e
                    if (EmbeddingText.isTokenLimitError(e) && charLimit > EmbeddingText.MIN_EMBED_CHARS) {
                        charLimit /= 2
                        Log.w(TAG, "Token limit hit; retrying with $charLimit chars")
                        continue
                    }
                    lastError = formatEmbedFailure(e)
                    Log.e(TAG, lastError!!, e)
                    return@withContext null
                }
            }
            return@withContext null
        }

    /** Releases native resources; call when the model file is deleted. */
    fun release() {
        // Intentionally non-suspend: the caller (e.g. EmbeddingModelManager.delete) may not be in
        // a coroutine. Setting the volatile field directly is safe here — the inferenceLock guards
        // construction, not the null-out on teardown, and a null read in embed() is handled.
        model = null
    }

    companion object {
        private const val TAG = "OnDeviceEmbedding"

        /** Unwraps [java.util.concurrent.ExecutionException] from [ListenableFuture.get] and adds ABI hints. */
        private fun formatEmbedFailure(e: Throwable): String {
            val root = generateSequence(e) { it.cause }.last()
            val detail = root.message?.takeIf { it.isNotBlank() } ?: root.javaClass.simpleName
            val hint = when {
                EmbeddingText.isTokenLimitError(e) ->
                    " Text exceeded the seq256 token window — try a shorter bookmark or re-embed after updating."
                root is UnsatisfiedLinkError || detail.contains("dlopen", ignoreCase = true) ->
                    " On-device embeddings require a physical arm64 device or an arm64-v8a emulator image."
                else -> ""
            }
            return "On-device embed failed: $detail$hint"
        }
    }
}

/**
 * Routes embedding requests to EmbeddingGemma on-device or the cloud provider, honouring the user's
 * [EmbeddingBackend] choice ([backend] is read on every call so a Settings change takes effect
 * immediately without rebuilding the graph):
 *
 *  - [EmbeddingBackend.AUTO]: on-device when the model is present, else the cloud fallback (the
 *    historic behaviour).
 *  - [EmbeddingBackend.ON_DEVICE]: on-device only — no cloud fallback, so a missing model surfaces
 *    as "unavailable" rather than silently hitting the network.
 *  - [EmbeddingBackend.XAI]: cloud only.
 */
class EmbeddingProviderSelector(
    private val onDevice: OnDeviceEmbeddingProvider,
    private val cloud: EmbeddingProvider,
    private val backend: () -> EmbeddingBackend = { EmbeddingBackend.AUTO }
) : EmbeddingProvider {
    override fun isOnDevice(): Boolean = when (backend()) {
        EmbeddingBackend.ON_DEVICE -> true
        EmbeddingBackend.XAI -> false
        EmbeddingBackend.AUTO -> onDevice.isOnDevice()
    }

    override val lastError: String? get() = onDevice.lastError ?: cloud.lastError

    override suspend fun embedDocument(bookmark: Bookmark): FloatArray? = when (backend()) {
        EmbeddingBackend.ON_DEVICE -> onDevice.embedDocument(bookmark)
        EmbeddingBackend.XAI -> cloud.embedDocument(bookmark)
        EmbeddingBackend.AUTO ->
            if (onDevice.isOnDevice()) (onDevice.embedDocument(bookmark) ?: cloud.embedDocument(bookmark))
            else cloud.embedDocument(bookmark)
    }

    override suspend fun embedQuery(query: String): FloatArray? = when (backend()) {
        EmbeddingBackend.ON_DEVICE -> onDevice.embedQuery(query)
        EmbeddingBackend.XAI -> cloud.embedQuery(query)
        EmbeddingBackend.AUTO ->
            if (onDevice.isOnDevice()) (onDevice.embedQuery(query) ?: cloud.embedQuery(query))
            else cloud.embedQuery(query)
    }
}
