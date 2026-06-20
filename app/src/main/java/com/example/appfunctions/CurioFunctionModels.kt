package com.example.appfunctions

import androidx.appfunctions.AppFunctionSerializable

/**
 * Condensed view of a bookmark for search results and list responses.
 */
@AppFunctionSerializable(isDescribedByKDoc = true)
data class BookmarkSummary(
    /** Unique identifier; required by getBookmarkDetail, addNoteToBookmark, toggleFavorite, and exportCitation. */
    val id: String,
    /** Raw tweet text or manually added content (first 300 characters). */
    val text: String,
    /** AI-generated short title, or null if not yet analysed. */
    val title: String?,
    /** AI-generated one-paragraph summary, or null if not yet analysed. */
    val summary: String?,
    /** Research tags, e.g. ["attention", "transformers"]. Empty list if not yet analysed. */
    val tags: List<String>,
    /** Research category such as "Deep Learning" or "NLP". Null if not yet analysed. */
    val category: String?,
    /** Title of the resolved primary source (arXiv paper, GitHub repo, etc.), or null. */
    val sourceTitle: String?,
    /** True when the user has starred this bookmark. */
    val isFavorite: Boolean,
    /** ISO-8601 UTC timestamp of when the bookmark was saved. */
    val createdAt: String,
)

/**
 * Full detail record for a single bookmark including all AI analysis and user annotations.
 */
@AppFunctionSerializable(isDescribedByKDoc = true)
data class BookmarkDetail(
    /** Unique identifier. */
    val id: String,
    /** Full raw text content of the bookmark. */
    val text: String,
    /** AI-generated short title, or null. */
    val title: String?,
    /** AI-generated one-paragraph summary, or null. */
    val summary: String?,
    /** Structured AI deep-analysis (contributions, significance, limitations), or null. */
    val deepSummary: String?,
    /** Research tags. */
    val tags: List<String>,
    /** Research category, or null. */
    val category: String?,
    /** JSON with extracted entities: {"models":[], "methods":[], "datasets":[], "metrics":[]}. */
    val entities: String?,
    /** User's personal annotation note, or null. */
    val notes: String?,
    /** Source type: ARXIV, GITHUB, HUGGING_FACE, DOI, or TWEET. Null if unresolved. */
    val sourceType: String?,
    /** Source identifier (arXiv ID, GitHub "owner/repo", DOI). */
    val sourceId: String?,
    /** Resolved primary-source title. */
    val sourceTitle: String?,
    /** Comma-separated author names. */
    val sourceAuthors: String?,
    /** Primary-source abstract text. */
    val sourceAbstract: String?,
    /** True when starred by the user. */
    val isFavorite: Boolean,
    /** True when saved for later reading. */
    val isSavedForLater: Boolean,
    /** ISO-8601 UTC timestamp of when the bookmark was saved. */
    val createdAt: String,
)
