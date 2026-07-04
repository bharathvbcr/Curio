package com.example.domain.model

/**
 * An embedding-derived suggestion that [bookmarkId] semantically belongs in Space [spaceId]
 * ([spaceName]) with the given cosine [score]. Surfaced on the card as a tap-to-file pill for
 * medium-confidence matches that aren't confident enough to file automatically.
 */
data class SpaceSuggestion(
    val bookmarkId: String,
    val spaceId: String,
    val spaceName: String,
    val score: Float
)

/**
 * Outcome of an [com.example.domain.repo.BookmarkRepository.organizeByEmbedding] run:
 * how many cards were auto-filed, how many new Spaces were spun up from clusters, and the
 * per-card [suggestions] for the medium-confidence remainder.
 */
data class OrganizeResult(
    val autoFiled: Int,
    val newSpaces: Int,
    val suggestions: List<SpaceSuggestion>
) {
    val hadChanges: Boolean get() = autoFiled > 0 || newSpaces > 0

    /** True when a user-facing toast is worth showing (includes medium-confidence suggestions). */
    val hasFeedback: Boolean get() = hadChanges || suggestions.isNotEmpty()

    /** Toast copy for the manual "Embed All" / auto-organise announce path; null when nothing to say. */
    fun announceMessage(): String? {
        val parts = buildList {
            if (autoFiled > 0) add("filed $autoFiled")
            if (newSpaces > 0) add("created $newSpaces space${if (newSpaces == 1) "" else "s"}")
            if (suggestions.isNotEmpty()) {
                add("${suggestions.size} suggestion${if (suggestions.size == 1) "" else "s"}")
            }
        }
        return if (parts.isEmpty()) null else "Auto-organised — ${parts.joinToString(", ")}"
    }

    companion object { val EMPTY = OrganizeResult(0, 0, emptyList()) }
}
