package com.example.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import com.example.domain.model.SourceType

/**
 * Semantic + brand color tokens that sit alongside the Material [androidx.compose.material3.ColorScheme].
 *
 * A handful of Curio's colors are *semantic* (favorite = pink) or *brand* (arXiv red,
 * GitHub green, Hugging Face amber) rather than something that should be derived from the
 * Material You seed. Before, these were copy-pasted `Color(0xFF…)` literals scattered across
 * CurioPostCard, ReaderViewScreen and BookmarkFeedScreen — drifting out of sync and never
 * adapting per surface. Centralising them here gives one place to tune them and one import
 * for every screen.
 */
object CurioColors {
    /** Favorite / like accent — a warm red-pink that stays legible on both light and dark. */
    val Favorite = Color(0xFFFF5A6E)

    // Per-source brand accents (card covers, source pills, reader headers).
    private val ArxivRed = Color(0xFFE53935)
    private val GithubGreen = Color(0xFF66BB6A)
    private val HuggingAmber = Color(0xFFFFB300)

    /**
     * Brand accent for a bookmark's [source], falling back to [fallback] (the theme primary
     * by default) for tweets and unknown sources.
     */
    @Composable
    @ReadOnlyComposable
    fun sourceAccent(
        source: SourceType?,
        fallback: Color = MaterialTheme.colorScheme.primary
    ): Color = when (source) {
        SourceType.ARXIV -> ArxivRed
        SourceType.GITHUB -> GithubGreen
        SourceType.HUGGING_FACE -> HuggingAmber
        else -> fallback
    }

    /**
     * Black or white — whichever stays legible on top of [background]. Used for icons/labels drawn
     * on user-chosen Space colors, where a fixed `Color.White` disappears on light picks.
     */
    fun onColor(background: Color): Color =
        if (background.luminance() > 0.5f) Color.Black.copy(alpha = 0.85f) else Color.White
}
