package com.example.data.source

import android.util.Log
import com.example.data.remote.ArxivClient
import com.example.data.remote.GithubApi
import com.example.data.remote.HuggingFaceApi
import com.example.domain.model.SourceType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class SourceInfo(
    val sourceType: SourceType,
    val sourceId: String,
    val sourceTitle: String,
    val sourceAuthors: String?,
    val sourceAbstract: String?,
    val sourceExtra: String?
)

class SourceResolver(
    private val arxivClient: ArxivClient,
    private val githubApi: GithubApi,
    private val huggingFaceApi: HuggingFaceApi
) {

    suspend fun resolve(text: String, url: String?): SourceInfo? = withContext(Dispatchers.IO) {
        val allUrls = extractAllUrls(text) + listOfNotNull(url)

        // Priority: arXiv > HuggingFace papers page > GitHub > HuggingFace model/dataset
        for (u in allUrls) {
            resolveArxiv(u)?.let { return@withContext it }
        }
        for (u in allUrls) {
            resolveHfPaper(u)?.let { return@withContext it }
        }
        for (u in allUrls) {
            resolveGithub(u)?.let { return@withContext it }
        }
        for (u in allUrls) {
            resolveHuggingFace(u)?.let { return@withContext it }
        }
        // Fallback: bare arXiv IDs mentioned in text without a URL (e.g. "2312.00752")
        ArxivClient.ARXIV_BARE_REGEX.find(text)?.groupValues?.get(1)?.let { bareId ->
            resolveArxiv("https://arxiv.org/abs/$bareId")
        }?.let { return@withContext it }
        null
    }

    private fun extractAllUrls(text: String): List<String> {
        val regex = Regex("https?://[\\w./%-]+")
        return regex.findAll(text).map { it.value }.toList()
    }

    // ── arXiv ────────────────────────────────────────────────────────────────

    private suspend fun resolveArxiv(url: String): SourceInfo? {
        val id = ArxivClient.ARXIV_ID_REGEX.find(url)?.groupValues?.get(1)
            ?.replace(Regex("v\\d+$"), "") ?: return null

        return try {
            val meta = arxivClient.fetchPaper(id) ?: return null
            val extra = buildExtraJson(mapOf(
                "published" to meta.published,
                "categories" to meta.categories
            ))
            SourceInfo(
                sourceType = SourceType.ARXIV,
                sourceId = meta.id,
                sourceTitle = meta.title,
                sourceAuthors = meta.authors.joinToString(", "),
                sourceAbstract = meta.abstract,
                sourceExtra = extra
            )
        } catch (e: Exception) {
            Log.e("SourceResolver", "arXiv resolve failed for $id: ${e.message}")
            null
        }
    }

    // HuggingFace papers links embed arXiv IDs
    private suspend fun resolveHfPaper(url: String): SourceInfo? {
        val id = Regex("huggingface\\.co/papers/([\\d.]+)").find(url)?.groupValues?.get(1)
            ?: return null
        return resolveArxiv("https://arxiv.org/abs/$id")
    }

    // ── GitHub ────────────────────────────────────────────────────────────────

    private suspend fun resolveGithub(url: String): SourceInfo? {
        val match = Regex("github\\.com/([a-zA-Z0-9_.-]+)/([a-zA-Z0-9_.-]+)").find(url)
            ?: return null
        val owner = match.groupValues[1]
        val repo = match.groupValues[2].removeSuffix(".git")
        if (owner.isBlank() || repo.isBlank()) return null

        return try {
            val r = githubApi.getRepo(owner, repo)
            val extra = buildExtraJson(mapOf(
                "stars" to r.stars,
                "language" to r.language,
                "topics" to r.topics,
                "pushedAt" to r.pushedAt
            ))
            SourceInfo(
                sourceType = SourceType.GITHUB,
                sourceId = r.fullName,
                sourceTitle = r.fullName,
                sourceAuthors = r.owner.login,
                sourceAbstract = r.description,
                sourceExtra = extra
            )
        } catch (e: Exception) {
            Log.e("SourceResolver", "GitHub resolve failed for $owner/$repo: ${e.message}")
            null
        }
    }

    // ── HuggingFace ───────────────────────────────────────────────────────────

    private suspend fun resolveHuggingFace(url: String): SourceInfo? {
        // Exclude known non-model paths
        if (url.contains("/spaces/") || url.contains("/papers/") || url.contains("/docs/")) {
            return null
        }
        val datasetMatch = Regex("huggingface\\.co/datasets/([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)").find(url)
        if (datasetMatch != null) {
            return resolveHfDataset(datasetMatch.groupValues[1])
        }
        val modelMatch = Regex("huggingface\\.co/([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)").find(url)
        if (modelMatch != null) {
            return resolveHfModel(modelMatch.groupValues[1])
        }
        return null
    }

    private suspend fun resolveHfModel(id: String): SourceInfo? {
        return try {
            val r = huggingFaceApi.getModel(id)
            val modelId = r.modelId ?: r.id ?: id
            val extra = buildExtraJson(mapOf(
                "downloads" to r.downloads,
                "likes" to r.likes,
                "pipelineTag" to r.pipelineTag,
                "tags" to r.tags.take(8)
            ))
            SourceInfo(
                sourceType = SourceType.HUGGING_FACE,
                sourceId = modelId,
                sourceTitle = modelId,
                sourceAuthors = r.author,
                sourceAbstract = r.description?.take(500),
                sourceExtra = extra
            )
        } catch (e: Exception) {
            Log.e("SourceResolver", "HF model resolve failed for $id: ${e.message}")
            null
        }
    }

    private suspend fun resolveHfDataset(id: String): SourceInfo? {
        return try {
            val r = huggingFaceApi.getDataset(id)
            val datasetId = r.id ?: id
            val extra = buildExtraJson(mapOf(
                "downloads" to r.downloads,
                "likes" to r.likes,
                "tags" to r.tags.take(8)
            ))
            SourceInfo(
                sourceType = SourceType.HUGGING_FACE,
                sourceId = datasetId,
                sourceTitle = datasetId,
                sourceAuthors = r.author,
                sourceAbstract = r.description?.take(500),
                sourceExtra = extra
            )
        } catch (e: Exception) {
            Log.e("SourceResolver", "HF dataset resolve failed for $id: ${e.message}")
            null
        }
    }

    private fun buildExtraJson(data: Map<String, Any?>): String {
        val obj = org.json.JSONObject()
        data.filterValues { it != null }.forEach { (k, v) ->
            when (v) {
                is List<*> -> obj.put(k, org.json.JSONArray(v))
                else -> obj.put(k, v)
            }
        }
        return obj.toString()
    }
}
