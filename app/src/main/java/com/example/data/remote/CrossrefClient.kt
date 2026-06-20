package com.example.data.remote

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject

data class CrossrefMeta(
    val doi: String,
    val title: String,
    val authors: List<String>,
    val abstract: String?,
    val published: String,        // "YYYY" or "YYYY-MM-DD"
    val containerTitle: String?,  // journal / proceedings
    val type: String?             // crossref work type, e.g. "journal-article"
)

/**
 * Resolves a DOI to bibliographic metadata via the public Crossref REST API
 * (https://api.crossref.org/works/{doi}). No key required; Crossref asks for a descriptive
 * User-Agent so requests can be attributed to the "polite pool".
 */
class CrossrefClient(
    private val client: OkHttpClient,
    // Injectable so tests can point at a MockWebServer; defaults to the live Crossref API.
    private val baseUrl: String = "https://api.crossref.org/works/"
) {

    suspend fun fetchWork(doi: String): CrossrefMeta? = withContext(Dispatchers.IO) {
        val clean = doi.trim().removeSuffix(".").lowercase()
        if (clean.isBlank()) return@withContext null
        val url = "$baseUrl$clean"
        try {
            val request = Request.Builder()
                .url(url)
                .header("User-Agent", "Curio/1.0 (Android research index; mailto:curio@example.com)")
                .build()
            val response = client.newCall(request).execute()
            response.use {
                if (!it.isSuccessful) {
                    Log.w(TAG, "Crossref $clean returned HTTP ${it.code}")
                    return@withContext null
                }
                val body = it.body?.string() ?: return@withContext null
                parse(body)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Crossref fetch failed for $clean: ${e.message}")
            null
        }
    }

    private fun parse(json: String): CrossrefMeta? {
        val msg = runCatching { JSONObject(json).optJSONObject("message") }.getOrNull() ?: return null
        val title = msg.optJSONArray("title")?.takeIf { it.length() > 0 }?.optString(0)?.trim()
            ?.takeIf { it.isNotBlank() } ?: return null

        val authors = buildList {
            msg.optJSONArray("author")?.let { arr ->
                for (i in 0 until arr.length()) {
                    val a = arr.optJSONObject(i) ?: continue
                    val given = a.optString("given").trim()
                    val family = a.optString("family").trim()
                    val name = listOf(given, family).filter { it.isNotEmpty() }.joinToString(" ")
                        .ifBlank { a.optString("name").trim() }
                    if (name.isNotBlank()) add(name)
                }
            }
        }

        // Crossref abstracts are JATS XML; strip tags for a plain-text snippet.
        val abstract = msg.optString("abstract").takeIf { it.isNotBlank() }
            ?.replace(Regex("<[^>]+>"), " ")?.replace(Regex("\\s+"), " ")?.trim()

        val container = msg.optJSONArray("container-title")?.takeIf { it.length() > 0 }
            ?.optString(0)?.takeIf { it.isNotBlank() }

        return CrossrefMeta(
            doi = msg.optString("DOI").ifBlank { return null },
            title = title.replace(Regex("\\s+"), " "),
            authors = authors,
            abstract = abstract,
            published = extractPublished(msg),
            containerTitle = container,
            type = msg.optString("type").takeIf { it.isNotBlank() }
        )
    }

    private fun extractPublished(msg: JSONObject): String {
        val parts = (msg.optJSONObject("issued") ?: msg.optJSONObject("published"))
            ?.optJSONArray("date-parts")?.optJSONArray(0) ?: return ""
        val year = parts.optInt(0, 0).takeIf { it > 0 } ?: return ""
        val month = if (parts.length() > 1) parts.optInt(1, 0) else 0
        val day = if (parts.length() > 2) parts.optInt(2, 0) else 0
        return when {
            month > 0 && day > 0 -> "%04d-%02d-%02d".format(year, month, day)
            month > 0 -> "%04d-%02d".format(year, month)
            else -> year.toString()
        }
    }

    companion object {
        private const val TAG = "CrossrefClient"
        // Matches a DOI inside a doi.org URL or as a bare "10.xxxx/..." token.
        val DOI_REGEX = Regex("\\b(10\\.\\d{4,9}/[-._;()/:A-Za-z0-9]+)", RegexOption.IGNORE_CASE)
    }
}
