package com.example.data.embedding

import android.util.Log
import com.example.domain.model.Bookmark
import com.google.ai.edge.localagents.rag.models.EmbedData
import com.google.ai.edge.localagents.rag.models.EmbeddingRequest
import com.google.ai.edge.localagents.rag.models.GeckoEmbeddingModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.util.Optional

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
}

/** Shared document-text assembly so on-device and cloud embed the *same* text for a bookmark. */
object EmbeddingText {
    private const val CHUNK_CHARS = 800
    private const val MAX_CHUNKS = 4

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
    fun chunksForDocument(b: Bookmark): List<String> {
        val header = buildString {
            b.sourceTitle?.let { append(it); append(". ") }
            b.sourceAbstract?.let { append(it); append(" ") }
            b.summary?.let { append(it); append(" ") }
            if (b.tags.isNotEmpty()) { append(b.tags.joinToString(" ")); append(" ") }
        }.trim()
        val chunks = mutableListOf<String>()
        if (header.isNotBlank()) chunks.add(header.take(CHUNK_CHARS))
        val body = b.text.trim()
        var i = 0
        while (i < body.length && chunks.size < MAX_CHUNKS) {
            chunks.add(body.substring(i, minOf(i + CHUNK_CHARS, body.length)))
            i += CHUNK_CHARS
        }
        return chunks.ifEmpty { listOf(forDocument(b)) }
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
 * On-device EmbeddingGemma backend via the AI Edge RAG [GeckoEmbeddingModel] (LiteRT weights +
 * SentencePiece tokenizer). Gated by [EmbeddingAvailability]: returns null when the model isn't
 * downloaded so the selector falls back to the cloud provider.
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

    @Volatile private var model: GeckoEmbeddingModel? = null

    // A single GeckoEmbeddingModel wraps one LiteRT interpreter, which is not safe to invoke
    // concurrently. The background backfill worker and a foreground search query can both reach this
    // shared instance at once, so inference is serialized.
    private val inferenceLock = Mutex()

    override fun isOnDevice(): Boolean = availability.isEmbeddingGemmaAvailable()

    override suspend fun embedDocument(bookmark: Bookmark): FloatArray? {
        // Chunk long documents and mean-pool the per-chunk vectors so body content is retained.
        val vectors = EmbeddingText.chunksForDocument(bookmark)
            .mapNotNull { embed(it, EmbedData.TaskType.RETRIEVAL_DOCUMENT) }
        return EmbeddingText.meanPool(vectors)
    }

    override suspend fun embedQuery(query: String): FloatArray? =
        embed(query, EmbedData.TaskType.RETRIEVAL_QUERY)

    private fun ensureModel(): GeckoEmbeddingModel? {
        model?.let { return it }
        if (!availability.isEmbeddingGemmaAvailable()) return null
        return synchronized(this) {
            model ?: runCatching {
                GeckoEmbeddingModel(
                    modelManager.modelFile().absolutePath,
                    Optional.of(modelManager.tokenizerFile().absolutePath),
                    /* useGpu = */ false
                ).also { model = it }
            }.onFailure { Log.e(TAG, "Failed to load EmbeddingGemma: ${it.message}", it) }.getOrNull()
        }
    }

    private suspend fun embed(text: String, task: EmbedData.TaskType): FloatArray? =
        withContext(Dispatchers.IO) {
            val m = ensureModel() ?: return@withContext null
            try {
                val request = EmbeddingRequest.create(
                    listOf(EmbedData.create<String>(text, task))
                )
                // ImmutableList<Float>; blocking on IO. Serialized — one interpreter, no concurrency.
                val vector = inferenceLock.withLock { m.getEmbeddings(request).get() }
                if (vector.isNullOrEmpty()) {
                    Log.w(TAG, "EmbeddingGemma returned an empty vector")
                    null
                } else {
                    FloatArray(vector.size) { vector[it] }
                }
            } catch (e: Exception) {
                Log.e(TAG, "On-device embed failed: ${e.message}", e)
                null
            }
        }

    /** Releases native resources; call when the model file is deleted. */
    fun release() {
        synchronized(this) { model = null }
    }

    companion object { private const val TAG = "OnDeviceEmbedding" }
}

/**
 * Routes embedding requests to EmbeddingGemma on-device when available, else the cloud provider.
 * Prefers the fully-private on-device path whenever the model is present.
 */
class EmbeddingProviderSelector(
    private val onDevice: OnDeviceEmbeddingProvider,
    private val cloud: EmbeddingProvider
) : EmbeddingProvider {
    override fun isOnDevice(): Boolean = onDevice.isOnDevice()

    override suspend fun embedDocument(bookmark: Bookmark): FloatArray? =
        if (onDevice.isOnDevice()) (onDevice.embedDocument(bookmark) ?: cloud.embedDocument(bookmark))
        else cloud.embedDocument(bookmark)

    override suspend fun embedQuery(query: String): FloatArray? =
        if (onDevice.isOnDevice()) (onDevice.embedQuery(query) ?: cloud.embedQuery(query))
        else cloud.embedQuery(query)
}
