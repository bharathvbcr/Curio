package com.example.data.local

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "bookmarks",
    indices = [
        Index(value = ["userId", "createdAt"]),
        Index(value = ["userId", "sourceId"]),
        // Speeds up Space membership clears (clearSpace) and category filtering (byCategory).
        Index(value = ["spaceId"]),
        Index(value = ["userId", "category"]),
        // Speeds up embedding backfill queries (getUnembedded) and enrichment queries (unenriched).
        Index(value = ["isAnalyzed"]),
        Index(value = ["userId", "isAnalyzed"])
    ]
)
data class BookmarkEntity(
    @PrimaryKey val id: String,
    val text: String,
    val createdAt: Long,
    val userId: String,
    val title: String? = null,
    val url: String? = null,
    val summary: String? = null,
    val tags: String? = null,            // CSV
    val category: String? = null,
    val imageUrl: String? = null,
    val ocrText: String? = null,
    val isOcrScheduled: Boolean = false,
    val isAnalyzed: Boolean = false,
    // Phase 8
    val sourceType: String? = null,
    val sourceId: String? = null,
    val sourceTitle: String? = null,
    val sourceAuthors: String? = null,
    val sourceAbstract: String? = null,
    val sourceExtra: String? = null,
    val referenceCount: Int = 1,
    // Phase 9
    val entities: String? = null,
    val isDeepAnalyzed: Boolean = false,
    val deepSummary: String? = null,
    // Phase 10
    val embedding: ByteArray? = null,
    // Phase 12: personal curation
    val isFavorite: Boolean = false,
    val isSavedForLater: Boolean = false,
    // Tweet author (joined from includes.users via author_id) + image alt-text from media
    val authorName: String? = null,
    val authorUsername: String? = null,
    val imageAltText: String? = null,
    // Spaces: user-created collection membership (null = unfiled). Local-only; not cloud-mirrored.
    val spaceId: String? = null,
    // User's personal note/annotation on this entry (null = none). Local-only; not cloud-mirrored.
    val notes: String? = null,
    /**
     * Last-local-write stamp (epoch ms), maintained by the `bookmarks_touch_updated_at` DB
     * triggers created in migration 12→13 — every INSERT/UPDATE on the table refreshes it, so
     * callers never set it manually. Compared against the cloud document's `updatedAt` during
     * pull reconciliation to pick the newer side (last-writer-wins for content fields).
     */
    val updatedAt: Long = 0
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is BookmarkEntity) return false
        return id == other.id
    }
    override fun hashCode(): Int = id.hashCode()
}
