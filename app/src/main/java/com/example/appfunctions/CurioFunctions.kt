package com.example.appfunctions

import androidx.appfunctions.AppFunctionAppUnknownException
import androidx.appfunctions.AppFunctionContext
import androidx.appfunctions.AppFunctionDeniedException
import androidx.appfunctions.service.AppFunction
import com.example.data.export.BibtexExporter
import com.example.data.remote.TokenStore
import com.example.domain.model.Bookmark
import com.example.domain.repo.BookmarkRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import java.time.Instant

/**
 * Exposes the Curio personal research index to on-device AI agents and Android system assistants.
 *
 * Curio saves X (Twitter) bookmarks and enriches them with AI-generated summaries, tags,
 * research categories, and primary-source metadata (arXiv, GitHub, Hugging Face, DOI).
 *
 * Operational patterns:
 * - Call searchBookmarks to obtain a valid bookmarkId before calling getBookmarkDetail,
 *   addNoteToBookmark, toggleFavorite, or exportCitation.
 * - A blank query in searchBookmarks returns the most recent bookmarks.
 * - AI enrichment (summary, tags, category) runs in the foreground when the Curio app is open;
 *   newly added bookmarks may show null fields until the app is opened.
 *
 * Constraints:
 * - The user must be signed in with X (Twitter) in the Curio app before any function can run.
 * - exportCitation returns null for tweet-only bookmarks without a resolved academic source.
 * - Maximum 50 results per searchBookmarks call.
 */
class CurioFunctions(
    private val bookmarkRepository: BookmarkRepository,
    private val tokenStore: TokenStore,
) {

    /**
     * On-device AI agents and system assistants that are permitted to invoke write or
     * detail-level read functions. Read-only discovery functions (searchBookmarks) do not
     * enforce this check.
     */
    private val ALLOWED_CALLERS = setOf(
        "com.google.android.as",
        "com.android.systemui",
        "com.google.android.googlequicksearchbox"
    )

    private fun requireAllowedCaller(appFunctionContext: AppFunctionContext) {
        if (appFunctionContext.callingPackageName !in ALLOWED_CALLERS) {
            throw AppFunctionDeniedException(
                "Caller '${appFunctionContext.callingPackageName}' is not permitted to invoke this function."
            )
        }
    }

    private suspend fun requireUserId(): String =
        tokenStore.userIdFlow.first()
            ?: throw AppFunctionDeniedException(
                "Not signed in. Open the Curio app and sign in with X to use these functions."
            )

    private fun Bookmark.toSummary() = BookmarkSummary(
        id = id,
        text = text.take(300),
        title = title,
        summary = summary,
        tags = tags,
        category = category,
        sourceTitle = sourceTitle,
        isFavorite = isFavorite,
        createdAt = Instant.ofEpochMilli(createdAt).toString(),
    )

    private fun Bookmark.toDetail() = BookmarkDetail(
        id = id,
        text = text,
        title = title,
        summary = summary,
        deepSummary = deepSummary,
        tags = tags,
        category = category,
        entities = entities,
        notes = notes,
        sourceType = sourceType?.name,
        sourceId = sourceId,
        sourceTitle = sourceTitle,
        sourceAuthors = sourceAuthors,
        sourceAbstract = sourceAbstract,
        isFavorite = isFavorite,
        isSavedForLater = isSavedForLater,
        createdAt = Instant.ofEpochMilli(createdAt).toString(),
    )

    /**
     * Search the personal research index by keyword.
     *
     * Performs a case-insensitive substring search across tweet text, AI-generated title,
     * summary, and OCR-extracted text. Returns the most recent bookmarks when [query] is blank.
     *
     * @param appFunctionContext The execution context.
     * @param query Keyword or phrase to find (e.g. "diffusion models", "RLHF"). Pass blank to get recent bookmarks.
     * @param category Optional research category to restrict results (e.g. "Deep Learning"). Pass null to search all categories.
     * @param limit Maximum results to return. Capped at 50.
     * @return List of [BookmarkSummary] ordered newest first. Empty list when nothing matches.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun searchBookmarks(
        appFunctionContext: AppFunctionContext,
        query: String,
        category: String? = null,
        limit: Int = 10,
    ): List<BookmarkSummary> = withContext(Dispatchers.IO) {
        val userId = requireUserId()
        val cap = limit.coerceIn(1, 50)
        bookmarkRepository.searchBookmarks(userId, query)
            .filter { category == null || it.category == category }
            .take(cap)
            .map { it.toSummary() }
    }

    /**
     * Save a new item to the research index.
     *
     * Accepts raw tweet text, a URL, or any research-related text snippet. The saved bookmark
     * is queued for AI enrichment; summary, tags, and category fields populate the next time the
     * Curio app is opened.
     *
     * @param appFunctionContext The execution context.
     * @param text The tweet content, URL, or research snippet to save.
     * @return The newly created [BookmarkSummary] with its assigned id.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun addBookmark(
        appFunctionContext: AppFunctionContext,
        text: String,
    ): BookmarkSummary = withContext(Dispatchers.IO) {
        requireAllowedCaller(appFunctionContext)
        val userId = requireUserId()
        bookmarkRepository.addBookmark(userId, text)
            .getOrElse {
                throw AppFunctionAppUnknownException("Failed to save bookmark: ${it.message}")
            }
            .toSummary()
    }

    /**
     * Retrieve the full detail record for a single bookmark, including AI analysis and annotations.
     *
     * Required workflow: Call searchBookmarks first to obtain a valid bookmarkId.
     *
     * @param appFunctionContext The execution context.
     * @param bookmarkId The unique identifier returned by searchBookmarks.
     * @return Full [BookmarkDetail], or null if the bookmarkId is not found.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun getBookmarkDetail(
        appFunctionContext: AppFunctionContext,
        bookmarkId: String,
    ): BookmarkDetail? = withContext(Dispatchers.IO) {
        requireAllowedCaller(appFunctionContext)
        bookmarkRepository.getBookmarkById(bookmarkId)?.toDetail()
    }

    /**
     * Add or replace the personal annotation note on a bookmark.
     *
     * Required workflow: Call searchBookmarks first to obtain a valid bookmarkId.
     *
     * @param appFunctionContext The execution context.
     * @param bookmarkId The unique identifier returned by searchBookmarks.
     * @param note The note text to attach. Pass an empty string to clear an existing note.
     * @return Updated [BookmarkSummary] reflecting the change, or null if the bookmarkId is not found.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun addNoteToBookmark(
        appFunctionContext: AppFunctionContext,
        bookmarkId: String,
        note: String,
    ): BookmarkSummary? = withContext(Dispatchers.IO) {
        requireAllowedCaller(appFunctionContext)
        val stored = bookmarkRepository.getBookmarkById(bookmarkId) ?: return@withContext null
        bookmarkRepository.updateNotes(bookmarkId, note.takeIf { it.isNotBlank() })
        stored.copy(notes = note.takeIf { it.isNotBlank() }).toSummary()
    }

    /**
     * Star or unstar a bookmark.
     *
     * Required workflow: Call searchBookmarks first to obtain a valid bookmarkId.
     *
     * @param appFunctionContext The execution context.
     * @param bookmarkId The unique identifier returned by searchBookmarks.
     * @param favorite True to star; false to remove the star.
     * @return Updated [BookmarkSummary] with the new favourite state, or null if not found.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun toggleFavorite(
        appFunctionContext: AppFunctionContext,
        bookmarkId: String,
        favorite: Boolean = true,
    ): BookmarkSummary? = withContext(Dispatchers.IO) {
        requireAllowedCaller(appFunctionContext)
        val stored = bookmarkRepository.getBookmarkById(bookmarkId) ?: return@withContext null
        bookmarkRepository.setFavorite(bookmarkId, favorite)
        stored.copy(isFavorite = favorite).toSummary()
    }

    /**
     * Export a BibTeX citation for a resolved academic source.
     *
     * Only bookmarks with a resolved primary source (arXiv, DOI, GitHub, Hugging Face) produce
     * BibTeX output. Tweet-only bookmarks return null.
     * Required workflow: Call searchBookmarks first to obtain a valid bookmarkId.
     *
     * @param appFunctionContext The execution context.
     * @param bookmarkId The unique identifier returned by searchBookmarks.
     * @return A BibTeX string ready to paste into a .bib file, or null if no source is resolved.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun exportCitation(
        appFunctionContext: AppFunctionContext,
        bookmarkId: String,
    ): String? = withContext(Dispatchers.IO) {
        val bookmark = bookmarkRepository.getBookmarkById(bookmarkId) ?: return@withContext null
        BibtexExporter.toBibtex(bookmark)
    }
}
