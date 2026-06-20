package com.example.data.source

import android.util.Log
import com.example.data.remote.ArxivClient
import com.example.data.remote.CrossrefClient
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
    private val huggingFaceApi: HuggingFaceApi,
    private val crossrefClient: CrossrefClient
) {

    private suspend fun <T> withRetry(maxAttempts: Int = 3, delayMs: Long = 1000, block: suspend () -> T?): T? {
        repeat(maxAttempts) { attempt ->
            try {
                return block()
            } catch (e: retrofit2.HttpException) {
                if (e.code() == 429 || e.code() == 503) {
                    val retryAfterMs = (e.response()?.headers()?.get("Retry-After")?.toLongOrNull() ?: (1L shl attempt)) * 1000L
                    kotlinx.coroutines.delay(retryAfterMs)
                } else if (e.code() in 400..499) {
                    return null  // client errors: don't retry
                }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                if (attempt == maxAttempts - 1) return null
                kotlinx.coroutines.delay(delayMs * (1L shl attempt))
            }
        }
        return null
    }

    suspend fun resolve(text: String, url: String?): SourceInfo? = withContext(Dispatchers.IO) {
        val allUrls = extractAllUrls(text) + listOfNotNull(url)

        // Priority: arXiv > HuggingFace papers page > GitHub > HuggingFace model/dataset > DOI
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
        // Fallback: a DOI in a doi.org URL or bare "10.xxxx/..." token anywhere in the text.
        for (u in allUrls) {
            CrossrefClient.DOI_REGEX.find(u)?.groupValues?.get(1)?.let { doi ->
                resolveDoi(doi)?.let { return@withContext it }
            }
        }
        CrossrefClient.DOI_REGEX.find(text)?.groupValues?.get(1)?.let { doi ->
            resolveDoi(doi)
        }?.let { return@withContext it }
        null
    }

    // ── DOI (Crossref) ──────────────────────────────────────────────────────────

    private suspend fun resolveDoi(doi: String): SourceInfo? {
        return try {
            val meta = withRetry { crossrefClient.fetchWork(doi) } ?: return null
            // arXiv DOIs (10.48550/arXiv.*) are better served by the arXiv resolver; skip them here.
            if (meta.doi.contains("arxiv", ignoreCase = true)) return null
            val extra = buildExtraJson(mapOf(
                "doi" to meta.doi,
                "published" to meta.published,
                "container" to meta.containerTitle,
                "type" to meta.type
            ))
            SourceInfo(
                sourceType = SourceType.DOI,
                sourceId = meta.doi,
                sourceTitle = meta.title,
                sourceAuthors = meta.authors.joinToString(", ").ifBlank { null },
                sourceAbstract = meta.abstract,
                sourceExtra = extra
            )
        } catch (e: Exception) {
            Log.e("SourceResolver", "DOI resolve failed for $doi: ${e.message}")
            null
        }
    }

    private fun extractAllUrls(text: String): List<String> {
        // Matches full URLs including query strings (?k=v) and fragments (#anchor).
        // Characters excluded from the character class: whitespace, angle brackets, quotes.
        // Trailing punctuation that is syntactically part of the surrounding sentence
        // (period, comma, closing paren/bracket, exclamation, semicolon) is stripped after
        // extraction so that "see https://arxiv.org/abs/2401.00001." works correctly.
        val regex = Regex("""https?://[^\s<>"']+""")
        return regex.findAll(text)
            .map { it.value.trimEnd('.', ',', ')', ']', '!', '?', ';') }
            .toList()
    }

    // ── arXiv ────────────────────────────────────────────────────────────────

    private suspend fun resolveArxiv(url: String): SourceInfo? {
        val id = ArxivClient.ARXIV_ID_REGEX.find(url)?.groupValues?.get(1)
            ?.replace(Regex("v\\d+$"), "") ?: return null

        return try {
            val meta = withRetry { arxivClient.fetchPaper(id) } ?: return null
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
            val r = withRetry { githubApi.getRepo(owner, repo) } ?: return null
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
            val r = withRetry { huggingFaceApi.getModel(id) } ?: return null
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
            val r = withRetry { huggingFaceApi.getDataset(id) } ?: return null
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
