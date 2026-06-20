package com.example.ui

import com.example.domain.model.Bookmark
import com.example.domain.repo.BookmarkRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Per-bookmark mutation actions (personal curation toggles, notes, deletion, category and Space
 * assignment). Extracted from [BookmarkViewModel] to continue shrinking the god class; these are
 * thin repository delegations with no own state, so the VM facades them and the UI is unchanged.
 */
internal class CurationController(
    private val scope: CoroutineScope,
    private val repository: BookmarkRepository
) {
    fun toggleFavorite(bookmark: Bookmark) {
        scope.launch { repository.setFavorite(bookmark.id, !bookmark.isFavorite) }
    }

    fun toggleSavedForLater(bookmark: Bookmark) {
        scope.launch { repository.setSavedForLater(bookmark.id, !bookmark.isSavedForLater) }
    }

    /** Saves (or clears, when blank) the user's personal note on an entry. */
    fun updateNotes(bookmarkId: String, notes: String?) {
        scope.launch { repository.updateNotes(bookmarkId, notes) }
    }

    fun assignToSpace(ids: List<String>, spaceId: String?) {
        if (ids.isEmpty()) return
        scope.launch { repository.assignToSpace(ids, spaceId) }
    }

    fun delete(ids: List<String>) {
        scope.launch { repository.deleteBookmarks(ids) }
    }

    fun updateCategory(ids: List<String>, category: String) {
        scope.launch { repository.updateCategoryForIds(ids, category) }
    }
}
