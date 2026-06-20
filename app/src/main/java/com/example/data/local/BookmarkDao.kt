package com.example.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface BookmarkDao {
    @Query("SELECT * FROM bookmarks WHERE userId = :userId ORDER BY createdAt DESC")
    fun getBookmarks(userId: String): Flow<List<BookmarkEntity>>

    /** All bookmarks across users, newest first. */
    @Query("SELECT * FROM bookmarks ORDER BY createdAt DESC")
    fun observeAll(): Flow<List<BookmarkEntity>>

    /**
     * Full-text-ish search across raw text, OCR text, summary and title.
     * `COLLATE NOCASE` makes matching case-insensitive (ASCII), so "attention" also finds
     * "Attention" — SQLite's LIKE is otherwise case-sensitive for these columns.
     */
    @Query(
        """
        SELECT * FROM bookmarks
        WHERE userId = :userId AND (
            text LIKE '%' || :query || '%' COLLATE NOCASE OR
            ocrText LIKE '%' || :query || '%' COLLATE NOCASE OR
            summary LIKE '%' || :query || '%' COLLATE NOCASE OR
            title LIKE '%' || :query || '%' COLLATE NOCASE
        )
        ORDER BY createdAt DESC
        """
    )
    fun search(userId: String, query: String): Flow<List<BookmarkEntity>>

    /** Bookmarks in a given category. */
    @Query("SELECT * FROM bookmarks WHERE userId = :userId AND category = :category ORDER BY createdAt DESC")
    fun byCategory(userId: String, category: String): Flow<List<BookmarkEntity>>

    /** Distinct non-null categories present for a user. */
    @Query("SELECT DISTINCT category FROM bookmarks WHERE userId = :userId AND category IS NOT NULL ORDER BY category")
    fun categories(userId: String): Flow<List<String>>

    /** Bookmarks not yet enriched (no AI analysis or summary) — drives foreground enrichment. */
    @Query("SELECT * FROM bookmarks WHERE userId = :userId AND (isAnalyzed = 0 OR summary IS NULL OR summary = '')")
    suspend fun unenriched(userId: String): List<BookmarkEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertBookmarks(bookmarks: List<BookmarkEntity>)

    @Query("DELETE FROM bookmarks WHERE userId = :userId")
    suspend fun clearBookmarks(userId: String)

    @Query("SELECT * FROM bookmarks WHERE id = :id")
    suspend fun getBookmarkById(id: String): BookmarkEntity?

    @Query("SELECT * FROM bookmarks WHERE sourceId = :sourceId AND userId = :userId LIMIT 1")
    suspend fun getBookmarkBySourceId(sourceId: String, userId: String): BookmarkEntity?

    @Query("SELECT * FROM bookmarks WHERE userId = :userId AND sourceId IS NOT NULL")
    suspend fun getBookmarksWithSourceId(userId: String): List<BookmarkEntity>

    @Query("UPDATE bookmarks SET summary = :summary, tags = :tags, category = :category, isAnalyzed = :isAnalyzed, entities = :entities WHERE id = :id")
    suspend fun updateAnalysis(id: String, summary: String?, tags: String?, category: String?, isAnalyzed: Boolean, entities: String?)

    @Query("UPDATE bookmarks SET ocrText = :ocrText, isOcrScheduled = :isOcrScheduled WHERE id = :id")
    suspend fun updateOcr(id: String, ocrText: String?, isOcrScheduled: Boolean)

    @Query("DELETE FROM bookmarks WHERE id IN (:ids)")
    suspend fun deleteBookmarks(ids: List<String>)

    @Query("UPDATE bookmarks SET category = :category WHERE id IN (:ids)")
    suspend fun updateCategoryForIds(ids: List<String>, category: String)

    /** Files (or unfiles, when [spaceId] is null) a set of bookmarks into a Space. */
    @Query("UPDATE bookmarks SET spaceId = :spaceId WHERE id IN (:ids)")
    suspend fun updateSpaceForIds(ids: List<String>, spaceId: String?)

    /** Clears membership for every bookmark in a Space — used when a Space is deleted. */
    @Query("UPDATE bookmarks SET spaceId = NULL WHERE spaceId = :spaceId")
    suspend fun clearSpace(spaceId: String)

    @Query("UPDATE bookmarks SET createdAt = :createdAt WHERE id = :id")
    suspend fun updateCreatedAt(id: String, createdAt: Long)

    /** Every bookmark on the device, across users — only for the device-wide background sweep. */
    @Query("SELECT * FROM bookmarks")
    suspend fun getAllBookmarksDirect(): List<BookmarkEntity>

    /** One user's bookmarks (filter pushed into SQL instead of loading every row into memory). */
    @Query("SELECT * FROM bookmarks WHERE userId = :userId ORDER BY createdAt DESC")
    suspend fun getBookmarksByUserDirect(userId: String): List<BookmarkEntity>

    @Query("""
        UPDATE bookmarks SET
            sourceType = :sourceType,
            sourceId = :sourceId,
            sourceTitle = :sourceTitle,
            sourceAuthors = :sourceAuthors,
            sourceAbstract = :sourceAbstract,
            sourceExtra = :sourceExtra,
            referenceCount = :referenceCount
        WHERE id = :id
    """)
    suspend fun updateSourceInfo(
        id: String,
        sourceType: String?,
        sourceId: String?,
        sourceTitle: String?,
        sourceAuthors: String?,
        sourceAbstract: String?,
        sourceExtra: String?,
        referenceCount: Int
    )

    @Query("UPDATE bookmarks SET referenceCount = referenceCount + 1 WHERE sourceId = :sourceId AND userId = :userId")
    suspend fun incrementReferenceCount(sourceId: String, userId: String)

    @Query("UPDATE bookmarks SET embedding = :embedding WHERE id = :id")
    suspend fun updateEmbedding(id: String, embedding: ByteArray?)

    @Query("SELECT id, embedding FROM bookmarks WHERE userId = :userId AND embedding IS NOT NULL")
    suspend fun getIdsAndEmbeddings(userId: String): List<IdEmbeddingRow>

    /** Analyzed bookmarks that still lack an embedding — the charging-time backfill work list. */
    @Query("SELECT * FROM bookmarks WHERE isAnalyzed = 1 AND embedding IS NULL AND userId = :userId LIMIT 200")
    suspend fun getUnembedded(userId: String): List<BookmarkEntity>

    @Query("SELECT * FROM bookmarks WHERE id IN (:ids)")
    suspend fun getBookmarksByIds(ids: List<String>): List<BookmarkEntity>

    @Query("SELECT * FROM bookmarks WHERE userId = :userId AND (spaceId IS NULL OR spaceId = '')")
    suspend fun getUnfiledBookmarks(userId: String): List<BookmarkEntity>

    /** Drops every stored embedding — used when switching embedding model/dimensions. */
    @Query("UPDATE bookmarks SET embedding = NULL")
    suspend fun clearAllEmbeddings()

    @Query("UPDATE bookmarks SET isDeepAnalyzed = :isDeepAnalyzed, deepSummary = :deepSummary WHERE id = :id")
    suspend fun updateDeepSummary(id: String, deepSummary: String?, isDeepAnalyzed: Boolean)

    @Query("UPDATE bookmarks SET isFavorite = :isFavorite WHERE id = :id")
    suspend fun updateFavorite(id: String, isFavorite: Boolean)

    @Query("UPDATE bookmarks SET isSavedForLater = :isSavedForLater WHERE id = :id")
    suspend fun updateSavedForLater(id: String, isSavedForLater: Boolean)

    @Query("UPDATE bookmarks SET notes = :notes WHERE id = :id")
    suspend fun updateNotes(id: String, notes: String?)
}

data class IdEmbeddingRow(val id: String, val embedding: ByteArray?)
