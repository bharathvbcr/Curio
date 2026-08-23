package com.example.data.remote

import android.util.Log
import android.util.Xml
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.xmlpull.v1.XmlPullParser

data class ArxivMeta(
    val id: String,
    val title: String,
    val authors: List<String>,
    val abstract: String,
    val published: String,     // "2023-12-01"
    val categories: List<String>
)

class ArxivClient(
    private val client: OkHttpClient,
    // Injectable so tests can point at a MockWebServer; defaults to the live arXiv API.
    private val baseUrl: String = "https://export.arxiv.org/api/query"
) {

    suspend fun fetchPaper(arxivId: String): ArxivMeta? = withContext(Dispatchers.IO) {
        val cleanId = arxivId.replace(Regex("v\\d+$"), "").trim()
        val url = "$baseUrl?id_list=${java.net.URLEncoder.encode(cleanId, "UTF-8")}&max_results=1"
        repeat(3) { attempt ->
            try {
                // use{} guarantees the connection is released on every path (error statuses
                // previously leaked the response body and its pooled connection).
                client.newCall(Request.Builder().url(url).build()).execute().use { response ->
                    if (response.code == 503) {
                        Log.w("ArxivClient", "arXiv HTTP 503 for $arxivId (attempt ${attempt + 1})")
                        kotlinx.coroutines.delay(2000L * (attempt + 1))
                        return@use
                    }
                    if (!response.isSuccessful) {
                        Log.w("ArxivClient", "arXiv HTTP ${response.code} for $arxivId")
                        return@withContext null
                    }
                    val body = response.body?.string() ?: return@withContext null
                    return@withContext parseAtom(body)
                }
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                Log.e("ArxivClient", "Failed to fetch $arxivId (attempt ${attempt + 1}): ${e.message}")
                if (attempt == 2) return@withContext null
                kotlinx.coroutines.delay(1000L * (attempt + 1))
            }
        }
        null
    }

    private fun parseAtom(xml: String): ArxivMeta? {
        return try {
            val parser = Xml.newPullParser()
            try {
                parser.setFeature("http://xmlpull.org/v1/doc/features.html#process-namespaces", true)
            } catch (e: Exception) {
                // not all parsers support this — ignore
            }
            parser.setInput(xml.reader())

            var inEntry = false
            var inAuthor = false
            val tagStack = ArrayDeque<String>()

            var rawId = ""
            val titleBuilder = StringBuilder()
            val abstractBuilder = StringBuilder()
            var published = ""
            val authors = mutableListOf<String>()
            val authorNameBuilder = StringBuilder()
            val categories = mutableListOf<String>()

            var eventType = parser.eventType
            while (eventType != XmlPullParser.END_DOCUMENT) {
                when (eventType) {
                    XmlPullParser.START_TAG -> {
                        val name = parser.name
                        tagStack.addLast(name)
                        when {
                            name == "entry" -> inEntry = true
                            name == "author" && inEntry -> {
                                inAuthor = true
                                authorNameBuilder.clear()
                            }
                            name == "category" && inEntry -> {
                                val term = parser.getAttributeValue(null, "term")
                                if (term != null) categories.add(term)
                            }
                        }
                    }
                    XmlPullParser.TEXT -> {
                        if (inEntry) {
                            val text = parser.text
                            when (tagStack.lastOrNull()) {
                                "id" -> rawId += text
                                "title" -> titleBuilder.append(text)
                                "summary" -> abstractBuilder.append(text)
                                "published" -> published += text
                                "name" -> if (inAuthor) authorNameBuilder.append(text)
                            }
                        }
                    }
                    XmlPullParser.END_TAG -> {
                        when (parser.name) {
                            "entry" -> inEntry = false
                            "author" -> {
                                val name = authorNameBuilder.toString().trim()
                                if (name.isNotEmpty()) authors.add(name)
                                inAuthor = false
                            }
                        }
                        tagStack.removeLastOrNull()
                    }
                }
                eventType = parser.next()
            }

            if (titleBuilder.isBlank()) return null

            val idMatch = Regex("arxiv\\.org/abs/([\\w.]+)").find(rawId)
            val canonicalId = idMatch?.groupValues?.get(1)
                ?.replace(Regex("v\\d+$"), "") ?: rawId.trim()

            ArxivMeta(
                id = canonicalId,
                title = titleBuilder.toString().trim().replace(Regex("\\s+"), " "),
                authors = authors,
                abstract = abstractBuilder.toString().trim().replace(Regex("\\s+"), " "),
                published = published.trim().take(10),
                categories = categories.filter { it.matches(Regex("[a-zA-Z-]+\\.[A-Z]+")) }
            )
        } catch (e: Exception) {
            Log.e("ArxivClient", "Parse error: ${e.message}")
            null
        }
    }

    companion object {
        // Modern arXiv IDs are YYMM.NNNNN(±vN). The previous [\d.]+ capture swallowed the
        // trailing dot of /pdf/2401.00001.pdf links (captured "2401.00001."), producing
        // API queries that could never resolve.
        val ARXIV_ID_REGEX = Regex("(?:arxiv\\.org|ar5iv\\.org)/(?:abs|pdf)/(\\d{4}\\.\\d{4,5}(?:v\\d+)?)")
        val ARXIV_BARE_REGEX = Regex("\\b(\\d{4}\\.\\d{4,5}(?:v\\d+)?)\\b")
    }
}
