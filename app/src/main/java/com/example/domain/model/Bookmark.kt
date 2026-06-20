package com.example.domain.model

enum class SourceType { ARXIV, GITHUB, HUGGING_FACE, TWEET, DOI }

data class Bookmark(
    val id: String,
    val text: String,
    val createdAt: Long, // Unix epoch millis
    val userId: String,
    val title: String? = null,
    val url: String? = null,
    val summary: String? = null,
    val tags: List<String> = emptyList(),
    val category: String? = null,
    val imageUrl: String? = null,        // primary attached media (tweet photo / preview)
    val ocrText: String? = null,
    val isOcrScheduled: Boolean = false,
    val isAnalyzed: Boolean = false,
    // Phase 8: primary-source resolution
    val sourceType: SourceType? = null,
    val sourceId: String? = null,
    val sourceTitle: String? = null,
    val sourceAuthors: String? = null,   // comma-separated
    val sourceAbstract: String? = null,
    val sourceExtra: String? = null,     // JSON: published date, stars, etc.
    val referenceCount: Int = 1,         // tweets pointing to same source
    // Phase 9: research taxonomy + entities
    val entities: String? = null,        // JSON: {models:[], methods:[], datasets:[], metrics:[]}
    val isDeepAnalyzed: Boolean = false,
    val deepSummary: String? = null,     // structured contribution/significance/caveats
    // Phase 12: personal curation
    val isFavorite: Boolean = false,     // starred / loved
    val isSavedForLater: Boolean = false, // marked to read later
    // Tweet author (joined from includes.users) + image alt-text
    val authorName: String? = null,
    val authorUsername: String? = null,
    val imageAltText: String? = null,
    // Spaces: user-created collection membership (null = unfiled)
    val spaceId: String? = null,
    // User's personal note/annotation on this entry (null = none)
    val notes: String? = null
)
