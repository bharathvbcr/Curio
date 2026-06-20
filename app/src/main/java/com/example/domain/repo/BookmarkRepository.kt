package com.example.domain.repo

import com.example.domain.model.Bookmark
import com.example.domain.model.Space
import com.example.domain.model.SpaceRules
import com.example.domain.model.SourceType
import kotlinx.coroutines.flow.Flow

interface BookmarkRepository {
    fun getBookmarksFlow(userId: String): Flow<List<Bookmark>>
    suspend fun getBookmarkById(id: String): Bookmark?
    suspend fun syncBookmarks(userId: String, fetchNextPage: Boolean = false): Result<Unit>
    suspend fun clearAll(userId: String)

    suspend fun updateAnalysisAndTags(
        id: String,
        summary: String?,
        category: String?,
        tags: List<String>,
        entities: String? = null
    )

    suspend fun updateOcrContent(id: String, ocrText: String?, isOcrScheduled: Boolean)
    suspend fun addBookmark(userId: String, text: String): Result<Bookmark>
    suspend fun deleteBookmarks(ids: List<String>)
    suspend fun updateCategoryForIds(ids: List<String>, category: String)
    suspend fun updateCreatedAt(id: String, createdAt: Long)

    // Phase 8: source resolution
    suspend fun updateSourceInfo(
        id: String,
        sourceType: SourceType?,
        sourceId: String?,
        sourceTitle: String?,
        sourceAuthors: String?,
        sourceAbstract: String?,
        sourceExtra: String?,
        referenceCount: Int = 1
    )
    suspend fun incrementReferenceCount(sourceId: String, userId: String)
    suspend fun deduplicateBySource(userId: String)

    // Phase 10: embeddings
    suspend fun updateEmbedding(id: String, embedding: ByteArray)
    suspend fun getBookmarksWithEmbeddings(userId: String): List<Pair<String, ByteArray>>
    /** Analyzed bookmarks still lacking an embedding — drives the charging-time on-device backfill. */
    suspend fun getUnembeddedAnalyzed(userId: String): List<Bookmark>
    /** Drops all stored embeddings (e.g. when switching embedding models / vector dimensions). */
    suspend fun clearAllEmbeddings()

    // Phase 9: deep analysis
    suspend fun updateDeepSummary(id: String, deepSummary: String)

    // Phase 12: personal curation
    suspend fun setFavorite(id: String, isFavorite: Boolean)
    suspend fun setSavedForLater(id: String, isSavedForLater: Boolean)
    /** Sets (or clears, when [notes] is null/blank) the user's personal note on an entry. Local-only. */
    suspend fun updateNotes(id: String, notes: String?)

    // Spaces: user-created collections
    fun getSpacesFlow(userId: String): Flow<List<Space>>
    suspend fun createSpace(
        userId: String,
        name: String,
        color: Long,
        icon: String,
        description: String = "",
        rules: SpaceRules = SpaceRules.EMPTY,
        isPinned: Boolean = false
    ): Space
    suspend fun updateSpace(
        id: String,
        name: String,
        color: Long,
        icon: String,
        description: String = "",
        rules: SpaceRules = SpaceRules.EMPTY,
        isPinned: Boolean = false
    )
    suspend fun deleteSpace(id: String)
    /** Pins (or unpins) a Space so it floats to the top of the list. */
    suspend fun setSpacePinned(id: String, pinned: Boolean)
    /** Files (or unfiles, when [spaceId] is null) the given bookmarks into a Space. */
    suspend fun assignToSpace(ids: List<String>, spaceId: String?)

    // Smart Spaces: rule-driven auto-filing
    /**
     * Files [bookmark] into the first auto-file Smart Space whose [SpaceRules] match it, returning
     * that Space's id (or null when nothing matches). Only considers currently-unfiled bookmarks —
     * a manual filing is never overridden.
     */
    suspend fun fileByRules(bookmark: Bookmark): String?

    /**
     * Files every unfiled bookmark matching [spaceId]'s rules into it, regardless of the Space's
     * auto-file toggle (this is the explicit "Apply rules now" action). Returns the number filed.
     */
    suspend fun applySpaceRules(spaceId: String): Int

    /**
     * Backfill across all of [userId]'s auto-file Smart Spaces: every unfiled bookmark is filed into
     * the first Space whose rules match. Idempotent and cheap; safe to call on every login. Returns
     * the number of bookmarks filed.
     */
    suspend fun applyRulesToLibrary(userId: String): Int

    /**
     * Ensures the canonical default Space for an AI [category] exists for [userId] (creating it from
     * [com.example.domain.model.CategorySpaces] the first time) and returns its id. Returns null when
     * [category] is blank. Idempotent — an existing Space (including one the user has since renamed)
     * is left untouched.
     */
    suspend fun ensureCategorySpace(userId: String, category: String): String?

    /**
     * Backfills Space membership for already-analysed bookmarks: any item that has an AI [category]
     * but no Space yet is filed into its category's default Space (created on demand). Idempotent and
     * cheap — only unfiled, categorised items are touched. Safe to call on every login.
     */
    suspend fun backfillCategorySpaces(userId: String)
}
