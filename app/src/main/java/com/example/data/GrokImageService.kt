package com.example.data

import android.util.Log
import com.example.data.remote.GrokModels
import com.example.data.remote.XAiApi
import com.example.data.remote.XAiImageRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Result of a Grok image generation: the image URL plus the model's revised prompt. */
data class GeneratedImage(
    val url: String,
    val revisedPrompt: String? = null
)

/**
 * Real image generation via xAI's `grok-imagine` models (`POST /v1/images/generations`). Replaces
 * the procedural canvas placeholder with model-generated artwork. Returns null on any failure
 * (missing key, network, quota) so callers can fall back to the local generative graphic.
 */
class GrokImageService(
    private val xAiApi: XAiApi
) {
    /**
     * Generates a single representative image for a research bookmark.
     *
     * @param prompt the scene description (built from the bookmark's title/category/tags).
     * @param highQuality use the higher-fidelity `grok-imagine-image-quality` model.
     */
    suspend fun generate(
        prompt: String,
        highQuality: Boolean = false,
        aspectRatio: String = "16:9"
    ): GeneratedImage? = withContext(Dispatchers.IO) {
        val apiKey = XaiKeyStore.resolve()
        if (!XaiKeyStore.isConfigured()) {
            Log.w("GrokImageService", "xAI key missing — skipping image generation")
            return@withContext null
        }
        try {
            val request = XAiImageRequest(
                model = if (highQuality) GrokModels.IMAGE_QUALITY else GrokModels.IMAGE,
                prompt = prompt,
                n = 1,
                responseFormat = "url",
                aspectRatio = aspectRatio,
                resolution = if (highQuality) "2k" else "1k"
            )
            val response = xAiApi.generateImages("Bearer $apiKey", request)
            val first = response.data?.firstOrNull()
            val url = first?.url ?: return@withContext null
            GeneratedImage(url = url, revisedPrompt = first.revisedPrompt)
        } catch (e: Exception) {
            Log.e("GrokImageService", "Image generation failed: ${e.message}")
            null
        }
    }

    /**
     * Builds a tasteful, on-brand art prompt for a bookmark category so generated covers stay
     * visually consistent across the research index.
     */
    fun promptForCategory(category: String?, title: String?): String {
        val subject = title?.takeIf { it.isNotBlank() } ?: (category ?: "AI research")
        val style = when (category?.trim()?.lowercase()) {
            "architectures" -> "abstract neural network topology, flowing connections"
            "training" -> "gradient descent landscape, glowing optimization paths"
            "inference-opt" -> "streamlined data pipelines, speed and efficiency motifs"
            "datasets" -> "structured grids of data points, organized information"
            "evals" -> "benchmark dashboards, comparative bar charts"
            "agents" -> "interconnected autonomous nodes, tool-use orchestration"
            "multimodal" -> "fusion of vision and language, overlapping modalities"
            "theory" -> "elegant mathematical forms, clean geometric abstraction"
            "systems" -> "distributed compute clusters, server topology"
            else -> "minimal generative tech art"
        }
        return "A sophisticated editorial cover illustration representing \"$subject\": $style. " +
            "Modern, minimal, deep gradient palette, high contrast, no text."
    }
}
