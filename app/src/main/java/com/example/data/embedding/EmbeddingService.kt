package com.example.data.embedding

import android.util.Log
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

    override suspend fun embedDocument(bookmark: Bookmark): FloatArray? =
        embed(EmbeddingText.forDocument(bookmark))

    override suspend fun embedQuery(query: String): FloatArray? = embed(query)

    private suspend fun embed(text: String): FloatArray? = withContext(Dispatchers.IO) {
        try {
            val apiKey = com.example.BuildConfig.XAI_API_KEY
            if (apiKey.isEmpty() || apiKey == "MY_XAI_API_KEY") return@withContext null

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
