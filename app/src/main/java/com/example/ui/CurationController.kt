package com.example.ui

import com.example.domain.model.Bookmark
import com.example.domain.repo.BookmarkRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * Per-bookmark mutation actions (personal curation toggles, notes, deletion, category and Space
 * assignment). Extracted from [BookmarkViewModel] to continue shrinking the god class; these are
 * thin repository delegations with no own state, so the VM facades them and the UI is unchanged.
 */
internal class CurationController(
    private val scope: CoroutineScope,
    private val repository: BookmarkRepository
) {
    private val _curationError = MutableSharedFlow<String>(extraBufferCapacity = 1)
    val curationError: SharedFlow<String> = _curationError.asSharedFlow()

    fun toggleFavorite(bookmark: Bookmark) {
        scope.launch {
            try {
                repository.setFavorite(bookmark.id, !bookmark.isFavorite)
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                _curationError.tryEmit("Failed to update bookmark: ${e.message}")
            }
        }
    }

    fun toggleSavedForLater(bookmark: Bookmark) {
        scope.launch {
            try {
                repository.setSavedForLater(bookmark.id, !bookmark.isSavedForLater)
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                _curationError.tryEmit("Failed to update bookmark: ${e.message}")
            }
        }
    }

    /** Saves (or clears, when blank) the user's personal note on an entry. */
    fun updateNotes(bookmarkId: String, notes: String?) {
        scope.launch {
            try {
                repository.updateNotes(bookmarkId, notes)
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                _curationError.tryEmit("Failed to update bookmark: ${e.message}")
            }
        }
    }

    fun assignToSpace(ids: List<String>, spaceId: String?) {
        if (ids.isEmpty()) return
        scope.launch {
            try {
                repository.assignToSpace(ids, spaceId)
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                _curationError.tryEmit("Failed to update bookmark: ${e.message}")
            }
        }
    }

    fun delete(ids: List<String>) {
        scope.launch {
            try {
                repository.deleteBookmarks(ids)
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                _curationError.tryEmit("Failed to update bookmark: ${e.message}")
            }
        }
    }

    fun updateCategory(ids: List<String>, category: String) {
        scope.launch {
            try {
                repository.updateCategoryForIds(ids, category)
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                _curationError.tryEmit("Failed to update bookmark: ${e.message}")
            }
        }
    }
}
