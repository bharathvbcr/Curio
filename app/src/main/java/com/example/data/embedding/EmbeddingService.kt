package com.example.data.embedding

import android.util.Log
import com.example.data.XaiKeyStore
import com.example.data.remote.XAiApi
import com.example.data.remote.XAiEmbeddingRequest
import com.example.domain.model.Bookmark
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Cloud embedding backend (xAI). Used as the fallback when on-device EmbeddingGemma is absent.
 *
 * Caveat: as of 2026-06 xAI does NOT expose a public `/v1/embeddings` REST endpoint (embeddings
 * live only behind the Collections feature), so this call is best-effort and usually returns null.
 * [EmbeddingProviderSelector] handles that by preferring on-device EmbeddingGemma and the
 * recency fallback in the chat path, so RAG keeps working regardless.
 */
class EmbeddingService(private val xAiApi: XAiApi) : EmbeddingProvider {

    override fun isOnDevice(): Boolean = false

    override suspend fun embedDocument(bookmark: Bookmark): FloatArray? {
        // Chunk + mean-pool so long documents retain body content (mirrors the on-device path).
        val vectors = EmbeddingText.chunksForDocument(bookmark).mapNotNull { embed(it) }
        return EmbeddingText.meanPool(vectors)
    }

    override suspend fun embedQuery(query: String): FloatArray? = embed(query)

    private suspend fun embed(text: String): FloatArray? = withContext(Dispatchers.IO) {
        try {
            val apiKey = XaiKeyStore.resolve()
            if (!XaiKeyStore.isConfigured()) return@withContext null

            val request = XAiEmbeddingRequest(
                model = com.example.data.remote.GrokModels.EMBEDDING,
                input = text.take(8000)
            )
            val response = xAiApi.createEmbeddings("Bearer $apiKey", request)
            response.data?.firstOrNull()?.embedding?.toFloatArray()
        } catch (e: Exception) {
            Log.e("EmbeddingService", "Embed failed: ${e.message}")
            null
        }
    }
}
