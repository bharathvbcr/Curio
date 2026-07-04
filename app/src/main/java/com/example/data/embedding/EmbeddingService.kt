package com.example.data.embedding

import android.util.Log
import com.example.data.XaiKeyStore
import com.example.data.remote.XAiApi
import com.example.data.remote.XAiEmbeddingRequest
import com.example.domain.model.Bookmark
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Cloud embedding backend (xAI).
 *
 * xAI does not publish a fixed embedding-model name — availability is provisioned per key/team — so
 * this discovers the account's embedding model at runtime via [XAiApi.listEmbeddingModels] and only
 * falls back to [com.example.data.remote.GrokModels.EMBEDDING] if discovery yields nothing. The exact
 * server error (HTTP status + body) is captured in [lastError] and logged, so a "0 embedded" outcome
 * is explainable ("no embedding model on your xAI account" vs a real network/auth failure) instead of
 * a silent null.
 */
class EmbeddingService(private val xAiApi: XAiApi) : EmbeddingProvider {

    /** Human-readable reason the last embed attempt failed, for the UI to surface. Null on success. */
    @Volatile override var lastError: String? = null
        private set

    // Cache the discovered model id for the process lifetime so we don't re-list on every chunk.
    @Volatile private var cachedModelId: String? = null

    override fun isOnDevice(): Boolean = false

    override suspend fun embedDocument(bookmark: Bookmark): FloatArray? {
        // Chunk + mean-pool; cloud accepts much longer inputs than the seq256 on-device model.
        val vectors = EmbeddingText.chunksForDocument(bookmark, EmbeddingText.CLOUD_CHUNK_CHARS)
            .mapNotNull { embed(it) }
        return EmbeddingText.meanPool(vectors)
    }

    override suspend fun embedQuery(query: String): FloatArray? = embed(query)

    /**
     * Resolves the embedding model id for this account: cached → account-provisioned (discovered) →
     * the compile-time default. Discovery failures are non-fatal (we still try the default) but are
     * recorded so the caller can explain a subsequent failure.
     */
    private suspend fun resolveModelId(apiKey: String): String {
        cachedModelId?.let { return it }
        val discovered = try {
            xAiApi.listEmbeddingModels("Bearer $apiKey").firstModelId()
        } catch (e: retrofit2.HttpException) {
            Log.w("EmbeddingService", "embedding-models list HTTP ${e.code()}: ${errorBody(e)}")
            null
        } catch (e: Exception) {
            Log.w("EmbeddingService", "embedding-models list failed: ${e.message}")
            null
        }
        val id = discovered ?: com.example.data.remote.GrokModels.EMBEDDING
        cachedModelId = id
        if (discovered != null) Log.i("EmbeddingService", "Using discovered xAI embedding model: $id")
        return id
    }

    private suspend fun embed(text: String): FloatArray? = withContext(Dispatchers.IO) {
        try {
            if (!XaiKeyStore.isConfigured()) {
                lastError = "No xAI API key set (Settings → xAI API Key)."
                return@withContext null
            }
            val apiKey = XaiKeyStore.resolve()

            val request = XAiEmbeddingRequest(
                model = resolveModelId(apiKey),
                input = text.take(8000)
            )
            val response = xAiApi.createEmbeddings("Bearer $apiKey", request)
            val vector = response.data?.firstOrNull()?.embedding?.toFloatArray()
            if (vector == null) {
                lastError = "xAI returned no embedding — your account may not have an embedding model provisioned."
                Log.w("EmbeddingService", lastError!!)
            } else {
                lastError = null
            }
            vector
        } catch (e: retrofit2.HttpException) {
            val body = errorBody(e)
            lastError = when (e.code()) {
                404 -> "xAI has no embeddings endpoint/model for this key (404). Use On-device embeddings."
                401, 403 -> "xAI rejected the key for embeddings (HTTP ${e.code()})."
                else -> "xAI embeddings failed: HTTP ${e.code()} $body"
            }
            Log.e("EmbeddingService", "Embed HTTP ${e.code()}: $body")
            null
        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException) throw e
            lastError = "xAI embeddings failed: ${e.message}"
            Log.e("EmbeddingService", "Embed failed: ${e.message}", e)
            null
        }
    }

    private fun errorBody(e: retrofit2.HttpException): String =
        runCatching { e.response()?.errorBody()?.string()?.take(300) }.getOrNull().orEmpty()
}
