package com.example.data.export

import com.example.domain.model.Bookmark
import com.example.domain.model.SourceType

object BibtexExporter {

    fun toBibtex(bookmark: Bookmark): String? = when (bookmark.sourceType) {
        SourceType.ARXIV -> arxivBibtex(bookmark)
        SourceType.GITHUB -> githubBibtex(bookmark)
        SourceType.HUGGING_FACE -> hfBibtex(bookmark)
        else -> null
    }

    fun toRis(bookmark: Bookmark): String? {
        if (bookmark.sourceType != SourceType.ARXIV) return null
        val id = bookmark.sourceId ?: return null
        return buildString {
            appendLine("TY  - JOUR")
            appendLine("TI  - ${bookmark.sourceTitle ?: ""}")
            bookmark.sourceAuthors?.split(",")?.forEach { author ->
                appendLine("AU  - ${author.trim()}")
            }
            appendLine("T2  - arXiv preprint arXiv:$id")
            appendLine("PY  - ${extractYear(bookmark)}")
            appendLine("UR  - https://arxiv.org/abs/$id")
            if (!bookmark.sourceAbstract.isNullOrBlank()) {
                appendLine("N2  - ${bookmark.sourceAbstract.take(500)}")
            }
            appendLine("ER  - ")
        }
    }

    fun toBibtexList(bookmarks: List<Bookmark>): String =
        bookmarks.mapNotNull { toBibtex(it) }.joinToString("\n\n")

    private fun arxivBibtex(bookmark: Bookmark): String? {
        val id = bookmark.sourceId ?: return null
        val title = bookmark.sourceTitle ?: return null
        val year = extractYear(bookmark)
        val key = generateKey(bookmark, year)
        val authors = formatAuthors(bookmark.sourceAuthors)
        return buildString {
            appendLine("@article{$key,")
            appendLine("  title   = {${escapeLatex(title)}},")
            if (authors.isNotEmpty()) appendLine("  author  = {$authors},")
            appendLine("  journal = {arXiv preprint arXiv:$id},")
            appendLine("  year    = {$year},")
            append("  url     = {https://arxiv.org/abs/$id}")
            append("\n}")
        }
    }

    private fun githubBibtex(bookmark: Bookmark): String? {
        val id = bookmark.sourceId ?: return null
        val title = bookmark.sourceTitle ?: return null
        val year = extractYear(bookmark)
        val owner = id.substringBefore("/")
        val key = buildKey(owner, year, title)
        return buildString {
            appendLine("@misc{$key,")
            appendLine("  title  = {{${escapeLatex(title)}}},")
            appendLine("  author = {${escapeLatex(owner)}},")
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
        val key = buildKey(id.substringBefore("/"), year, title)
        return buildString {
            appendLine("@misc{$key,")
            appendLine("  title  = {{${escapeLatex(title)}}},")
            appendLine("  year   = {$year},")
            appendLine("  url    = {https://huggingface.co/$id},")
            append("  note   = {HuggingFace model/dataset}")
            append("\n}")
        }
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

    private fun escapeLatex(text: String): String = text
        .replace("&", "\\&").replace("%", "\\%").replace("\$", "\\\$")
        .replace("#", "\\#").replace("_", "\\_")

    private fun extractYear(bookmark: Bookmark): String {
        val fromExtra = bookmark.sourceExtra?.let {
            Regex("\"published\"\\s*:\\s*\"(\\d{4})").find(it)?.groupValues?.get(1)
        }
        if (fromExtra != null) return fromExtra
        val epochMs = bookmark.createdAt
        val cal = java.util.Calendar.getInstance()
        cal.timeInMillis = if (epochMs > 1_000_000_000_000L) epochMs else epochMs * 1000
        return cal.get(java.util.Calendar.YEAR).toString()
    }
}
