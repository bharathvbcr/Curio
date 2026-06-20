package com.example.data.embedding

import android.content.Context
import android.util.Log
import com.example.data.remote.TokenStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Manages the downloadable on-device EmbeddingGemma model.
 *
 * EmbeddingGemma runs through the Google AI Edge RAG library's [com.google.ai.edge.localagents.rag.models.GeckoEmbeddingModel],
 * which needs two files: the LiteRT `.tflite` weights and a SentencePiece tokenizer. We keep them
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

    private val _state = MutableStateFlow<State>(if (isReady()) State.Ready else State.Absent)
    val state: StateFlow<State> = _state.asStateFlow()

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
        modelFile().let { it.exists() && it.length() > MIN_MODEL_BYTES } &&
            tokenizerFile().let { it.exists() && it.length() > 0 }

    /** Re-derive state from disk (e.g. after a side-loaded push). */
    fun refresh() {
        _state.value = if (isReady()) State.Ready else State.Absent
    }

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
        // Resolve the HF access token: a freshly pasted one wins (and is persisted so it's entered
        // once), then a previously saved token, then the build-time owner token. Null is fine for an
        // ungated mirror — gated repos will surface a clear 401/403 hint below.
        val pasted = overrideToken?.takeIf { it.isNotBlank() }
        if (pasted != null) runCatching { tokenStore.saveHuggingFaceToken(pasted) }
        val authToken = pasted
            ?: tokenStore.getHuggingFaceToken()?.takeIf { it.isNotBlank() }
            ?: com.example.BuildConfig.HF_TOKEN.takeIf { it.isNotBlank() }
        try {
            // Tokenizer first — it's tiny and lets us fail fast on auth/network before the big file.
            _state.value = State.Downloading(0f, "Fetching tokenizer…")
            fetch(TOKENIZER_URL, tokenizerFile(), authToken) { _ -> }

            fetch(MODEL_URL, modelFile(), authToken) { frac ->
                _state.value = State.Downloading(frac, "Downloading model… ${(frac * 100).toInt()}%")
            }

            if (isReady()) {
                _state.value = State.Ready
                true
            } else {
                cleanup()
                _state.value = State.Failed("Downloaded files were incomplete")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Model download failed: ${e.message}", e)
            cleanup()
            val hint = if ((e.message ?: "").contains("401") || (e.message ?: "").contains("403"))
                "Model is gated — a Hugging Face access token is required."
            else e.message ?: "Download failed"
            _state.value = State.Failed(hint)
            false
        }
    }

    fun delete() {
        cleanup()
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
        private const val REPO = "https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main"
        const val MODEL_URL = "$REPO/embeddinggemma-300M_seq256.tflite?download=true"
        const val TOKENIZER_URL = "$REPO/sentencepiece.model?download=true"

        /** Approximate total download size, for the UI. */
        const val APPROX_SIZE_LABEL = "~180 MB"
    }
}
