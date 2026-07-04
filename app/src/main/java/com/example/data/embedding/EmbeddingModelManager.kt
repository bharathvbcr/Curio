package com.example.data.embedding

import android.content.Context
import android.util.Log
import com.example.data.remote.TokenStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Manages the downloadable on-device EmbeddingGemma model.
 *
 * EmbeddingGemma runs through the Google AI Edge RAG library's [GemmaEmbeddingModel] (requires
 * `localagents-rag` ≥ 0.3.0), which needs two files: the LiteRT `.tflite` weights and a SentencePiece tokenizer. We keep them
 * in the app's external files dir (so they survive reinstalls of data, can be inspected, and — handy
 * for development — can be side-loaded with `adb push`). The ~180MB model is *not* bundled in the
 * APK; the user opts in to the download.
 *
 * The source repo (litert-community/embeddinggemma-300m) is gated under the Gemma license, so an
 * unauthenticated fetch may be rejected. [download] accepts an optional bearer token, and any file
 * can also be side-loaded into [modelDir] out of band.
 */
class EmbeddingModelManager(
    private val context: Context,
    private val tokenStore: TokenStore
) {

    sealed interface State {
        /** Model files not present — the on-device path is unavailable. */
        data object Absent : State
        /** Download in progress. [fraction] is 0f..1f across both files; [label] is a human note. */
        data class Downloading(val fraction: Float, val label: String) : State
        /** Both files present — on-device embedding can run. */
        data object Ready : State
        data class Failed(val message: String) : State
    }

    private val _state = MutableStateFlow(initialState())
    val state: StateFlow<State> = _state.asStateFlow()

    private fun initialState(): State {
        if (isReady()) return State.Ready
        val hasModel = modelFile().exists() && modelFile().length() > 0
        val hasTok = tokenizerFile().exists() && tokenizerFile().length() > 0
        if (!hasModel && !hasTok) return State.Absent
        return State.Failed(
            if (hasModel && !isValidModelFile()) "Downloaded weights are not a valid TFLite model — delete and re-download."
            else "Model files are incomplete — delete and re-download."
        )
    }

    fun modelDir(): File {
        val externalDir = context.getExternalFilesDir(null)
        val base = if (externalDir != null) {
            externalDir
        } else {
            Log.w(TAG, "External storage unavailable, using internal storage")
            context.filesDir
        }
        return File(base, "models").apply { mkdirs() }
    }
    fun modelFile(): File = File(modelDir(), MODEL_FILE)
    fun tokenizerFile(): File = File(modelDir(), TOKENIZER_FILE)

    /** True when both the weights and tokenizer are present and non-empty. */
    fun isReady(): Boolean =
        isValidModelFile() && tokenizerFile().let { it.exists() && it.length() > 0 }

    /**
     * Guards against truncated downloads and HTML error pages mistaken for weights: LiteRT/TFLite
     * files carry a `TFL3` magic at bytes 4–7. Without this check [isReady] could go true on a
     * multi-megabyte gated-repo error body, then [GemmaEmbeddingModel] load fails opaquely at embed time.
     */
    fun isValidModelFile(): Boolean {
        val file = modelFile()
        if (!file.exists() || file.length() < MIN_MODEL_BYTES) return false
        return runCatching {
            file.inputStream().use { input ->
                val header = ByteArray(8)
                if (input.read(header) < 8) return false
                header.copyOfRange(4, 8).decodeToString() == "TFL3"
            }
        }.getOrDefault(false)
    }

    /** Re-derive state from disk (e.g. after a side-loaded push). */
    fun refresh() {
        _state.value = initialState()
    }

    // Serializes downloads: a double-tapped DOWNLOAD/RETRY, or a trigger from both the Settings card
    // and the feed sheet, would otherwise run two coroutines writing the same ".part" temp file and
    // both renaming it onto the model path — corrupting the weights on disk. tryLock (not lock) means
    // a concurrent re-trigger is ignored rather than queued behind the in-flight download.
    private val downloadMutex = Mutex()

    private val http: OkHttpClient by lazy {
        // Dedicated client: no body logging (these are large binaries) and a generous read timeout.
        OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(5, TimeUnit.MINUTES)
            .build()
    }

    /**
     * Downloads the tokenizer (small) then the weights (large), reporting combined progress.
     * Safe to call again after a failure — partial files are overwritten. Returns true on success.
     */
    suspend fun download(overrideToken: String? = null): Boolean = withContext(Dispatchers.IO) {
        if (isReady()) {
            _state.value = State.Ready
            return@withContext true
        }
        // Ignore a re-entrant call while a download is already running (see downloadMutex). The
        // in-flight coroutine keeps driving _state, so the UI is unaffected by the ignored tap.
        if (!downloadMutex.tryLock()) {
            Log.d(TAG, "Download already in progress; ignoring re-entrant request")
            return@withContext false
        }
        try {
        // Resolve the HF access token (BYOK): a freshly pasted one wins (and is persisted so it's
        // entered once), then a previously saved token. No key ships in the APK, so null is possible
        // — fine for an ungated mirror; gated repos surface a clear 401/403 hint below.
        //
        // Trim first: tokens pasted from the HF site routinely carry a trailing newline or spaces.
        // Left intact, that newline makes OkHttp throw on the "Bearer …" header (an illegal header
        // value), so the download dies with a confusing error instead of authenticating — and the
        // tainted value would otherwise be persisted and reused on every retry. Trimming on both the
        // fresh and the saved path also self-heals a previously stored tainted token.
        val pasted = overrideToken?.trim()?.takeIf { it.isNotBlank() }
        val authToken = pasted
            ?: tokenStore.getHuggingFaceToken()?.trim()?.takeIf { it.isNotBlank() }
        try {
            // Tokenizer first — it's tiny and lets us fail fast on auth/network before the big file.
            _state.value = State.Downloading(0f, "Fetching tokenizer…")
            fetch(TOKENIZER_URL, tokenizerFile(), authToken) { _ -> }

            fetch(MODEL_URL, modelFile(), authToken) { frac ->
                _state.value = State.Downloading(frac, "Downloading model… ${(frac * 100).toInt()}%")
            }

            if (isReady()) {
                // Persist only a token we've now confirmed works, so a wrong/expired submission can't
                // poison later blank-field retries with a cached bad token.
                if (pasted != null) runCatching { tokenStore.saveHuggingFaceToken(pasted) }
                _state.value = State.Ready
                true
            } else {
                cleanup()
                _state.value = State.Failed(
                    if (!isValidModelFile()) "Downloaded weights are not a valid TFLite model — check your Hugging Face token and Gemma license, then retry."
                    else "Downloaded files were incomplete"
                )
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Model download failed: ${e.message}", e)
            cleanup()
            val msg = e.message ?: ""
            // Distinguish the two gated-repo failure modes — a valid token that hasn't accepted the
            // license (403) is the common case and was previously mis-reported as "token required".
            val hint = when {
                msg.contains("403") ->
                    "Access not granted (403). Your token works, but you must accept the Gemma license: open " +
                        "huggingface.co/litert-community/embeddinggemma-300m, click “Agree and access repository”, " +
                        "then retry. (A fine-grained token also needs “Read access to public gated repos”.)"
                msg.contains("401") ->
                    "Hugging Face token invalid or expired (401). Create a new READ token at " +
                        "huggingface.co/settings/tokens and paste it above."
                else -> msg.ifBlank { "Download failed" }
            }
            _state.value = State.Failed(hint)
            false
        }
        } finally {
            downloadMutex.unlock()
        }
    }

    /** Optional hook so [OnDeviceEmbeddingProvider] can drop its in-memory interpreter when files are removed. */
    var onDeleted: (() -> Unit)? = null

    fun delete() {
        cleanup()
        onDeleted?.invoke()
        _state.value = State.Absent
    }

    private fun cleanup() {
        runCatching { modelFile().delete() }
        runCatching { tokenizerFile().delete() }
    }

    private fun fetch(url: String, dest: File, authToken: String?, onProgress: (Float) -> Unit) {
        val reqBuilder = Request.Builder().url(url)
        if (!authToken.isNullOrBlank()) reqBuilder.header("Authorization", "Bearer $authToken")
        http.newCall(reqBuilder.build()).execute().use { response ->
            if (!response.isSuccessful) throw IllegalStateException("HTTP ${response.code} for $url")
            val body = response.body ?: throw IllegalStateException("Empty body for $url")
            val total = body.contentLength().takeIf { it > 0 }
            val tmp = File(dest.parentFile, dest.name + ".part")
            body.byteStream().use { input ->
                tmp.outputStream().use { output ->
                    val buf = ByteArray(1 shl 16)
                    var read: Int
                    var written = 0L
                    while (input.read(buf).also { read = it } != -1) {
                        output.write(buf, 0, read)
                        written += read
                        if (total != null) onProgress(written.toFloat() / total)
                    }
                }
            }
            if (!tmp.renameTo(dest)) {
                tmp.copyTo(dest, overwrite = true); tmp.delete()
            }
        }
    }

    companion object {
        private const val TAG = "EmbeddingModelManager"

        // Local on-disk names (kept stable regardless of the remote filename).
        const val MODEL_FILE = "embeddinggemma_seq256.tflite"
        const val TOKENIZER_FILE = "sentencepiece.model"

        // ~180MB; guards against a truncated/HTML error page being mistaken for the model.
        private const val MIN_MODEL_BYTES = 1_000_000L

        // litert-community/embeddinggemma-300m — gated under the Gemma license.
        // The repo renamed the seq256 weights to a `_mixed-precision` suffix; the old
        // `embeddinggemma-300M_seq256.tflite` path now 404s. The generic (non-vendor) variant is the
        // portable CPU build, which matches our `useGpu = false` inference path.
        private const val REPO = "https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main"
        const val MODEL_URL = "$REPO/embeddinggemma-300M_seq256_mixed-precision.tflite?download=true"
        const val TOKENIZER_URL = "$REPO/sentencepiece.model?download=true"

        /** Approximate total download size, for the UI. */
        const val APPROX_SIZE_LABEL = "~180 MB"
    }
}
