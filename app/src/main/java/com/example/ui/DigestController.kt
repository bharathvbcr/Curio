package com.example.ui

import android.util.Log
import com.example.data.XAiAnalyzer
import com.example.domain.model.Bookmark
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Owns the weekly AI digest: its own [DigestUiState] flow and the Grok-backed generation over the
 * last 7 days of saves. Self-contained (its state isn't shared with sync/analysis), so it extracts
 * cleanly out of [BookmarkViewModel]; the VM facades it so the UI is unchanged.
 */
internal class DigestController(
    private val scope: CoroutineScope,
    private val aiAnalyzer: XAiAnalyzer,
    private val rawBookmarks: () -> List<Bookmark>
) {
    private val _digestState = MutableStateFlow<DigestUiState>(DigestUiState.Idle)
    val digestState: StateFlow<DigestUiState> = _digestState.asStateFlow()

    /**
     * Generates a themed markdown digest of the last 7 days of saves via Grok. Surfaces an explicit
     * Empty state when nothing was saved this week so the UI never shows a misleading blank digest.
     */
    fun generate() {
        scope.launch {
            _digestState.value = DigestUiState.Loading
            val cutoff = System.currentTimeMillis() - DIGEST_WINDOW_MS
            val recent = rawBookmarks().filter { it.createdAt >= cutoff }
            if (recent.isEmpty()) {
                _digestState.value = DigestUiState.Empty("No saves in the last 7 days — come back after you've bookmarked something new.")
                return@launch
            }
            val itemsBlock = recent.take(DIGEST_MAX_ITEMS).joinToString("\n") { b ->
                val title = b.sourceTitle?.takeIf { it.isNotBlank() }
                    ?: b.title?.takeIf { it.isNotBlank() }
                    ?: b.text.take(80).trim()
                val cat = b.category?.takeIf { it.isNotBlank() }?.let { " [$it]" } ?: ""
                val summary = b.summary?.takeIf { it.isNotBlank() }?.let { " — $it" } ?: ""
                "- $title$cat$summary"
            }
            try {
                val markdown = aiAnalyzer.generateWeeklyDigest(itemsBlock, recent.size)
                _digestState.value = DigestUiState.Ready(markdown, recent.size)
            } catch (e: Exception) {
                Log.w(TAG, "Weekly digest failed", e)
                _digestState.value = DigestUiState.Error(humanReadableError(e, ErrorContext.AI))
            }
        }
    }

    fun dismiss() { _digestState.value = DigestUiState.Idle }

    private companion object {
        private const val TAG = "DigestController"
        private const val DIGEST_WINDOW_MS = 7L * 24 * 60 * 60 * 1000 // last 7 days
        private const val DIGEST_MAX_ITEMS = 40                       // cap tokens/cost per digest
    }
}
