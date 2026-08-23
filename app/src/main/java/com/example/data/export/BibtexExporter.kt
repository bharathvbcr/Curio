package com.example.data.export

import com.example.domain.model.Bookmark
import com.example.domain.model.SourceType
import org.json.JSONObject

/**
 * Citation export for resolved primary sources. Supports BibTeX, RIS, CSL-JSON and Markdown so
 * the research index can hand off to LaTeX, Zotero/Mendeley, CSL-based tools and plain notes.
 */
object BibtexExporter {

    fun toBibtex(bookmark: Bookmark): String? = when (bookmark.sourceType) {
        SourceType.ARXIV -> arxivBibtex(bookmark)
        SourceType.GITHUB -> githubBibtex(bookmark)
        SourceType.HUGGING_FACE -> hfBibtex(bookmark)
        SourceType.DOI -> doiBibtex(bookmark)
        else -> null
    }

    private fun doiBibtex(bookmark: Bookmark): String? {
        val doi = bookmark.sourceId ?: return null
        val title = bookmark.sourceTitle ?: return null
        val year = extractYear(bookmark)
        val authors = formatAuthors(bookmark.sourceAuthors)
        val container = extra(bookmark)?.optString("container")?.takeIf { it.isNotBlank() }
        val month = extractMonth(bookmark)
        return buildString {
            appendLine("@article{${generateKey(bookmark, year)},")
            appendLine("  title   = {${escapeLatex(title)}},")
            if (authors.isNotEmpty()) appendLine("  author  = {$authors},")
            if (container != null) appendLine("  journal = {${escapeLatex(container)}},")
            appendLine("  year    = {$year},")
            if (month != null) appendLine("  month   = {$month},")
            appendLine("  doi     = {$doi},")
            if (!bookmark.sourceAbstract.isNullOrBlank()) {
                appendLine("  abstract= {${escapeLatex(bookmark.sourceAbstract)}},")
            }
            append("  url     = {https://doi.org/$doi}")
            append("\n}")
        }
    }

    fun toRis(bookmark: Bookmark): String? {
        val id = bookmark.sourceId ?: return null
        val title = bookmark.sourceTitle ?: return null
        val paper = isPaper(bookmark.sourceType)
        if (bookmark.sourceType == null) return null
        return buildString {
            appendLine(if (paper) "TY  - JOUR" else "TY  - COMP")
            appendLine("TI  - $title")
            bookmark.sourceAuthors?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() }
                ?.forEach { appendLine("AU  - $it") }
            if (bookmark.sourceType == SourceType.ARXIV) appendLine("T2  - arXiv preprint arXiv:$id")
            appendLine("PY  - ${extractYear(bookmark)}")
            extractDoi(bookmark)?.let { appendLine("DO  - $it") }
            appendLine("UR  - ${sourceUrl(bookmark)}")
            if (!bookmark.sourceAbstract.isNullOrBlank()) {
                appendLine("N2  - ${bookmark.sourceAbstract.take(500)}")
            }
            appendLine("ER  - ")
        }
    }

    /** CSL-JSON (a JSON array of one item) — consumable by Zotero, citeproc and pandoc. */
    fun toCslJson(bookmark: Bookmark): String? {
        val title = bookmark.sourceTitle ?: return null
        val type = bookmark.sourceType ?: return null
        val year = extractYear(bookmark).toIntOrNull()
        val item = JSONObject().apply {
            put("id", bookmark.sourceId ?: bookmark.id)
            put("type", if (isPaper(type)) "article-journal" else "software")
            put("title", title)
            val authors = bookmark.sourceAuthors?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() }
            if (!authors.isNullOrEmpty()) {
                put("author", org.json.JSONArray().apply {
                    authors.forEach { name -> put(cslName(name)) }
                })
            }
            if (year != null) {
                put("issued", JSONObject().put("date-parts", org.json.JSONArray().apply {
                    put(org.json.JSONArray().apply { put(year) })
                }))
            }
            extractDoi(bookmark)?.let { put("DOI", it) }
            put("URL", sourceUrl(bookmark))
            bookmark.sourceAbstract?.takeIf { it.isNotBlank() }?.let { put("abstract", it) }
            if (type == SourceType.ARXIV) {
                put("container-title", "arXiv")
                bookmark.sourceId?.let { put("number", it) }
            } else if (type == SourceType.DOI) {
                extra(bookmark)?.optString("container")?.takeIf { it.isNotBlank() }
                    ?.let { put("container-title", it) }
            }
        }
        return item.toString(2)
    }

    /** Human-readable Markdown citation (one bullet) for plain notes / READMEs. */
    fun toMarkdown(bookmark: Bookmark): String? {
        val title = bookmark.sourceTitle ?: return null
        val authors = formatAuthors(bookmark.sourceAuthors).ifEmpty { null }
        val year = extractYear(bookmark)
        val url = sourceUrl(bookmark)
        return buildString {
            append("- ")
            authors?.let { append("$it ") }
            append("(${year}). [$title]($url)")
            extractDoi(bookmark)?.let { append(" doi:$it") }
        }
    }

    fun toBibtexList(bookmarks: List<Bookmark>): String {
        // BibTeX keys must be unique within a .bib file; two bookmarks sharing first author +
        // year + first title word used to emit colliding keys and break LaTeX/Zotero imports.
        val seen = HashMap<String, Int>()
        return bookmarks.mapNotNull { bm ->
            val entry = toBibtex(bm) ?: return@mapNotNull null
            val keyMatch = Regex("^(@\\w+)\\{([^,]+),").find(entry) ?: return@mapNotNull entry
            val (entryType, baseKey) = keyMatch.destructured
            val occurrence = seen[baseKey] ?: 0
            seen[baseKey] = occurrence + 1
            if (occurrence == 0) entry
            else entry.replaceFirst(keyMatch.value, "$entryType{$baseKey${'a' + occurrence - 1},")
        }.joinToString("\n\n")
    }

    fun toRisList(bookmarks: List<Bookmark>): String =
        bookmarks.mapNotNull { toRis(it) }.joinToString("\n")

    fun toMarkdownList(bookmarks: List<Bookmark>): String =
        bookmarks.mapNotNull { toMarkdown(it) }.joinToString("\n")

    fun toCslJsonList(bookmarks: List<Bookmark>): String =
        "[\n" + bookmarks.mapNotNull { toCslJson(it) }.joinToString(",\n") + "\n]"

    private fun arxivBibtex(bookmark: Bookmark): String? {
        val id = bookmark.sourceId ?: return null
        val title = bookmark.sourceTitle ?: return null
        val year = extractYear(bookmark)
        val key = generateKey(bookmark, year)
        val authors = formatAuthors(bookmark.sourceAuthors)
        val primaryClass = extractPrimaryClass(bookmark)
        val month = extractMonth(bookmark)
        val doi = extractDoi(bookmark)
        return buildString {
            appendLine("@article{$key,")
            appendLine("  title         = {${escapeLatex(title)}},")
            if (authors.isNotEmpty()) appendLine("  author        = {$authors},")
            appendLine("  journal       = {arXiv preprint arXiv:$id},")
            appendLine("  year          = {$year},")
            if (month != null) appendLine("  month         = {$month},")
            appendLine("  eprint        = {$id},")
            appendLine("  archivePrefix = {arXiv},")
            if (primaryClass != null) appendLine("  primaryClass  = {$primaryClass},")
            if (doi != null) appendLine("  doi           = {$doi},")
            if (!bookmark.sourceAbstract.isNullOrBlank()) {
                appendLine("  abstract      = {${escapeLatex(bookmark.sourceAbstract)}},")
            }
            append("  url           = {https://arxiv.org/abs/$id}")
            append("\n}")
        }
    }

    private fun githubBibtex(bookmark: Bookmark): String? {
        val id = bookmark.sourceId ?: return null
        val title = bookmark.sourceTitle ?: return null
        val year = extractYear(bookmark)
        val owner = id.substringBefore("/")
        val author = formatAuthors(bookmark.sourceAuthors).ifEmpty { owner }
        val key = buildKey(owner, year, title)
        return buildString {
            appendLine("@misc{$key,")
            appendLine("  title  = {{${escapeLatex(title)}}},")
            appendLine("  author = {${escapeLatex(author)}},")
            appendLine("  year   = {$year},")
            appendLine("  url    = {https://github.com/$id},")
            append("  note   = {GitHub repository}")
            append("\n}")
        }
    }

    private fun hfBibtex(bookmark: Bookmark): String? {
        val id = bookmark.sourceId ?: return null
        val title = bookmark.sourceTitle ?: return null
        val year = extractYear(bookmark)
        val author = formatAuthors(bookmark.sourceAuthors).ifEmpty { id.substringBefore("/") }
        val key = buildKey(id.substringBefore("/"), year, title)
        return buildString {
            appendLine("@misc{$key,")
            appendLine("  title  = {{${escapeLatex(title)}}},")
            appendLine("  author = {${escapeLatex(author)}},")
            appendLine("  year   = {$year},")
            appendLine("  url    = {https://huggingface.co/$id},")
            append("  note   = {HuggingFace model/dataset}")
            append("\n}")
        }
    }

    private fun sourceUrl(bookmark: Bookmark): String = when (bookmark.sourceType) {
        SourceType.ARXIV -> "https://arxiv.org/abs/${bookmark.sourceId}"
        SourceType.GITHUB -> "https://github.com/${bookmark.sourceId}"
        SourceType.HUGGING_FACE -> "https://huggingface.co/${bookmark.sourceId}"
        SourceType.DOI -> "https://doi.org/${bookmark.sourceId}"
        else -> bookmark.url ?: ""
    }

    private fun isPaper(type: SourceType?): Boolean =
        type == SourceType.ARXIV || type == SourceType.DOI

    /** Splits "Firstname Lastname" into CSL family/given parts (best-effort). */
    private fun cslName(name: String): JSONObject {
        val parts = name.trim().split(" ")
        return JSONObject().apply {
            if (parts.size > 1) {
                put("family", parts.last())
                put("given", parts.dropLast(1).joinToString(" "))
            } else {
                put("literal", name)
            }
        }
    }

    private fun extra(bookmark: Bookmark): JSONObject? =
        bookmark.sourceExtra?.takeIf { it.isNotBlank() }?.let { runCatching { JSONObject(it) }.getOrNull() }

    private fun extractDoi(bookmark: Bookmark): String? =
        extra(bookmark)?.optString("doi")?.takeIf { it.isNotBlank() }

    private fun extractPrimaryClass(bookmark: Bookmark): String? {
        val cats = extra(bookmark)?.optJSONArray("categories") ?: return null
        return if (cats.length() > 0) cats.optString(0).takeIf { it.isNotBlank() } else null
    }

    /** BibTeX month from the stored "published" date ("2023-12-01" -> "dec"). */
    private fun extractMonth(bookmark: Bookmark): String? {
        val published = extra(bookmark)?.optString("published") ?: return null
        val m = Regex("\\d{4}-(\\d{2})").find(published)?.groupValues?.get(1)?.toIntOrNull() ?: return null
        return MONTHS.getOrNull(m - 1)
    }

    private fun generateKey(bookmark: Bookmark, year: String): String {
        val firstAuthor = bookmark.sourceAuthors?.split(",")?.firstOrNull()?.trim() ?: "anon"
        val lastName = firstAuthor.split(" ").last()
        return buildKey(lastName, year, bookmark.sourceTitle ?: "paper")
    }

    private fun buildKey(base: String, year: String, title: String): String {
        val cleanBase = base.lowercase().replace(Regex("[^a-z0-9]"), "").take(12)
        val firstWord = title.lowercase().split(Regex("\\s+"))
            .firstOrNull { it.length > 3 && it.matches(Regex("[a-z]+")) } ?: "work"
        return "${cleanBase}${year}${firstWord}"
    }

    private fun formatAuthors(authorsStr: String?): String {
        if (authorsStr.isNullOrBlank()) return ""
        return authorsStr.split(",").joinToString(" and ") { it.trim() }
    }

    private fun escapeLatex(text: String): String {
        // Backslash cannot simply be replaced first or last: doing it first lets later
        // escapes corrupt the \textbackslash{} marker's braces; doing it last double-escapes
        // the very escapes just added. A sentinel keeps each pass independent — it must
        // contain ONLY control characters, since every printable special is itself rewritten.
        val backslashSentinel = "\u0000\u0001\u0002"
        return text
            .replace("\\", backslashSentinel)
            .replace("{", "\\{").replace("}", "\\}")
            .replace("&", "\\&").replace("%", "\\%").replace("$", "\\$")
            .replace("#", "\\#").replace("_", "\\_")
            .replace(backslashSentinel, "\\textbackslash{}")
    }

    private fun extractYear(bookmark: Bookmark): String {
        val fromExtra = bookmark.sourceExtra?.let {
            Regex("\"published\"\\s*:\\s*\"(\\d{4})").find(it)?.groupValues?.get(1)
        }
        if (fromExtra != null) return fromExtra
        val epochMs = bookmark.createdAt
        if (epochMs <= 0L) {
            // Legacy rows carry a 0 sentinel from failed timestamp parses — citing "1970"
            // is worse than the current year; use UTC so the year never shifts by timezone.
            return java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"))
                .get(java.util.Calendar.YEAR).toString()
        }
        val cal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"))
        cal.timeInMillis = if (epochMs > 1_000_000_000_000L) epochMs else epochMs * 1000
        return cal.get(java.util.Calendar.YEAR).toString()
    }

    private val MONTHS = listOf(
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"
    )
}
