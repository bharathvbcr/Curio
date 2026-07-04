package com.example.appfunctions

import androidx.appfunctions.AppFunctionAppUnknownException
import androidx.appfunctions.AppFunctionContext
import androidx.appfunctions.AppFunctionDeniedException
import androidx.appfunctions.service.AppFunction
import com.example.data.export.BibtexExporter
import com.example.data.remote.TokenStore
import com.example.domain.model.Bookmark
import com.example.domain.repo.BookmarkRepository
import com.example.interop.ChronosFlowBridge
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
    private val chronosFlowBridge: ChronosFlowBridge,
) {

    private suspend fun requireUserId(): String =
        tokenStore.userIdFlow.first()
            ?: throw AppFunctionDeniedException(
                "Not signed in. Open the Curio app and sign in with X to use these functions."
            )

    /**
     * Gate for the write functions (add bookmark / add note / toggle favourite). alpha09 does not
     * expose the calling package to function code, so a per-caller allowlist isn't possible; this
     * user-controlled toggle (Settings → "Allow assistants to modify my bookmarks") is the
     * available defence. Read-only discovery/detail functions are intentionally not gated.
     */
    private suspend fun requireAgentWritesAllowed() {
        if (!tokenStore.isAgentWritesAllowed()) {
            throw AppFunctionDeniedException(
                "Assistant modifications are turned off. Enable “Allow assistants to modify my " +
                    "bookmarks” in Curio Settings to use this function."
            )
        }
    }

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
        requireAgentWritesAllowed()
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
        requireUserId()
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
        requireAgentWritesAllowed()
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
        requireAgentWritesAllowed()
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

    // ── ChronosFlow handoff (productivity integration) ───────────────────────
    // These hand a saved bookmark off to the companion ChronosFlow planner app. They require
    // ChronosFlow to be installed; ChronosFlow itself verifies Curio's signature before accepting.

    private fun Bookmark.bestUrl(): String? =
        url?.takeIf { it.isNotBlank() } ?: text.takeIf { it.isNotBlank() }

    private fun Bookmark.bestTitle(): String? =
        (sourceTitle ?: title)?.takeIf { it.isNotBlank() }

    /**
     * Save a bookmark to ChronosFlow's reading list ("remind me to read later").
     *
     * The bookmark's link is added to the ChronosFlow planner's reading list. When
     * [remindInMinutes] is provided, ChronosFlow also schedules a reminder notification that many
     * minutes from now (e.g. 60 for "in an hour", 1440 for "tomorrow").
     * Required workflow: Call searchBookmarks first to obtain a valid bookmarkId.
     *
     * @param appFunctionContext The execution context.
     * @param bookmarkId The unique identifier returned by searchBookmarks.
     * @param remindInMinutes Optional minutes from now to fire a read-later reminder. Pass null for no reminder.
     * @return The handoff outcome, or null if the bookmarkId is not found.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun remindToReadLater(
        appFunctionContext: AppFunctionContext,
        bookmarkId: String,
        remindInMinutes: Int? = null,
    ): ChronosHandoffResult? = withContext(Dispatchers.IO) {
        requireAgentWritesAllowed()
        requireChronosFlow()
        val bookmark = bookmarkRepository.getBookmarkById(bookmarkId) ?: return@withContext null
        val url = bookmark.bestUrl()
            ?: return@withContext ChronosHandoffResult(false, "This bookmark has no link to read later.", null)
        val reminderAt = remindInMinutes
            ?.takeIf { it > 0 }
            ?.let { System.currentTimeMillis() + it.toLong() * 60_000L }
        chronosFlowBridge.sendToReadingList(
            url = url,
            title = bookmark.bestTitle(),
            reminderAtEpochMillis = reminderAt,
            notes = bookmark.notes,
        ).fold(
            onSuccess = {
                ChronosHandoffResult(
                    success = true,
                    message = if (reminderAt != null) "Saved to ChronosFlow reading list with a reminder."
                    else "Saved to ChronosFlow reading list.",
                    reminderAt = reminderAt?.let { Instant.ofEpochMilli(it).toString() },
                )
            },
            onFailure = { ChronosHandoffResult(false, "ChronosFlow declined the item: ${it.message}", null) },
        )
    }

    /**
     * Capture a bookmark into ChronosFlow's quick-capture inbox for later triage.
     *
     * Required workflow: Call searchBookmarks first to obtain a valid bookmarkId.
     *
     * @param appFunctionContext The execution context.
     * @param bookmarkId The unique identifier returned by searchBookmarks.
     * @return The handoff outcome, or null if the bookmarkId is not found.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun captureToChronosInbox(
        appFunctionContext: AppFunctionContext,
        bookmarkId: String,
    ): ChronosHandoffResult? = withContext(Dispatchers.IO) {
        requireAgentWritesAllowed()
        requireChronosFlow()
        val bookmark = bookmarkRepository.getBookmarkById(bookmarkId) ?: return@withContext null
        val text = listOfNotNull(bookmark.bestTitle(), bookmark.bestUrl() ?: bookmark.text)
            .distinct()
            .joinToString("\n")
            .ifBlank { bookmark.text }
        chronosFlowBridge.captureToInbox(text).fold(
            onSuccess = { ChronosHandoffResult(true, "Captured to ChronosFlow inbox.", null) },
            onFailure = { ChronosHandoffResult(false, "ChronosFlow declined the item: ${it.message}", null) },
        )
    }

    /**
     * Create a follow-up task in ChronosFlow from a bookmark (e.g. "follow up on this paper").
     *
     * Required workflow: Call searchBookmarks first to obtain a valid bookmarkId.
     *
     * @param appFunctionContext The execution context.
     * @param bookmarkId The unique identifier returned by searchBookmarks.
     * @param title Optional task title. Defaults to the bookmark's title/source title when omitted.
     * @return The handoff outcome, or null if the bookmarkId is not found.
     */
    @AppFunction(isDescribedByKDoc = true)
    suspend fun createChronosTask(
        appFunctionContext: AppFunctionContext,
        bookmarkId: String,
        title: String? = null,
    ): ChronosHandoffResult? = withContext(Dispatchers.IO) {
        requireAgentWritesAllowed()
        requireChronosFlow()
        val bookmark = bookmarkRepository.getBookmarkById(bookmarkId) ?: return@withContext null
        val taskTitle = title?.trim()?.takeIf { it.isNotEmpty() }
            ?: bookmark.bestTitle()
            ?: bookmark.text.take(80)
        chronosFlowBridge.createTask(
            title = taskTitle,
            notes = bookmark.summary ?: bookmark.notes,
            url = bookmark.bestUrl(),
        ).fold(
            onSuccess = { ChronosHandoffResult(true, "Created a task in ChronosFlow.", null) },
            onFailure = { ChronosHandoffResult(false, "ChronosFlow declined the item: ${it.message}", null) },
        )
    }

    private fun requireChronosFlow() {
        if (!chronosFlowBridge.isAvailable()) {
            throw AppFunctionDeniedException(
                "ChronosFlow is not installed. Install the ChronosFlow planner app to save reminders, " +
                    "inbox captures, and tasks from Curio."
            )
        }
    }
}
