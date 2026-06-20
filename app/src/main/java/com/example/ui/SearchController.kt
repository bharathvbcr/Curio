package com.example.ui

import android.util.Log
import com.example.data.embedding.EmbeddingProvider
import com.example.data.embedding.VectorSearch
import com.example.data.embedding.VectorSearch.toFloatArray
import com.example.domain.model.Bookmark
import com.example.domain.repo.BookmarkRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Owns the feed's search/filter INPUT state — query, mode, semantic results, category/tag/quick/space
 * filters — plus the on-device semantic-search run. Extracted from [BookmarkViewModel] to shrink the
 * god class.
 *
 * Deliberately scoped to the *inputs only*: the central `combine(...)` that produces the filtered
 * bookmark list stays in the ViewModel and simply reads these public flows, so the fragile reactive
 * graph is repointed (not rewritten). The VM facades the setters so the UI is unchanged.
 */
internal class SearchController(
    private val scope: CoroutineScope,
    private val embeddingService: EmbeddingProvider,
    private val repository: BookmarkRepository,
    private val rawBookmarks: () -> List<Bookmark>,
    private val currentUserId: () -> String?
) {
    private val _searchQuery = MutableStateFlow("")
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    private val _searchMode = MutableStateFlow(SearchMode.KEYWORD)
    val searchMode: StateFlow<SearchMode> = _searchMode.asStateFlow()

    private val _semanticResults = MutableStateFlow<List<Bookmark>>(emptyList())
    val semanticResults: StateFlow<List<Bookmark>> = _semanticResults.asStateFlow()

    private val _isSemanticLoading = MutableStateFlow(false)
    val isSemanticLoading: StateFlow<Boolean> = _isSemanticLoading.asStateFlow()

    private val _selectedCategory = MutableStateFlow<String?>(null)
    val selectedCategory: StateFlow<String?> = _selectedCategory.asStateFlow()

    private val _selectedTag = MutableStateFlow<String?>(null)
    val selectedTag: StateFlow<String?> = _selectedTag.asStateFlow()

    private val _quickFilter = MutableStateFlow(QuickFilter.ALL)
    val quickFilter: StateFlow<QuickFilter> = _quickFilter.asStateFlow()

    private val _selectedSpaceId = MutableStateFlow<String?>(null)
    val selectedSpaceId: StateFlow<String?> = _selectedSpaceId.asStateFlow()

    private var semanticSearchJob: Job? = null

    fun setQuickFilter(filter: QuickFilter) {
        _quickFilter.value = if (_quickFilter.value == filter) QuickFilter.ALL else filter
    }

    fun selectSpace(spaceId: String?) { _selectedSpaceId.value = spaceId }

    /** Clears the space filter only if it currently points at [id] (used when a Space is deleted). */
    fun clearSpaceIf(id: String) { if (_selectedSpaceId.value == id) _selectedSpaceId.value = null }

    fun selectCategory(category: String?) { _selectedCategory.value = category }
    fun selectTag(tag: String?) { _selectedTag.value = tag }

    fun updateQuery(query: String) {
        _searchQuery.value = query
        if (_searchMode.value == SearchMode.SEMANTIC && query.isNotBlank()) {
            // Debounce: a semantic search embeds the query and scans every stored vector, so it
            // must not fire on every keystroke. Coalesce rapid typing into one search.
            semanticSearchJob?.cancel()
            semanticSearchJob = scope.launch {
                delay(DEBOUNCE_MS)
                runSemanticSearch(query)
            }
        }
    }

    fun setMode(mode: SearchMode) {
        _searchMode.value = mode
        if (mode == SearchMode.KEYWORD) {
            semanticSearchJob?.cancel()
            _semanticResults.value = emptyList()
        } else if (_searchQuery.value.isNotBlank()) {
            semanticSearchJob?.cancel()
            semanticSearchJob = scope.launch {
                runSemanticSearch(_searchQuery.value)
            }
        }
    }

    fun clearAll() {
        _searchQuery.value = ""; _selectedCategory.value = null; _selectedTag.value = null
        _semanticResults.value = emptyList(); _searchMode.value = SearchMode.KEYWORD
        _quickFilter.value = QuickFilter.ALL; _selectedSpaceId.value = null
    }

    private suspend fun runSemanticSearch(query: String) {
        val uid = currentUserId() ?: return
        _isSemanticLoading.value = true
        try {
            val queryEmbedding = embeddingService.embedQuery(query) ?: return
            val allEmbeddings = repository.getBookmarksWithEmbeddings(uid)
                .map { (id, bytes) -> id to bytes.toFloatArray() }

            if (allEmbeddings.isEmpty()) return

            val topIds = VectorSearch.topK(queryEmbedding, allEmbeddings, k = 20).toSet()
            val bookmarkMap = rawBookmarks().associateBy { it.id }
            _semanticResults.value = topIds.mapNotNull { bookmarkMap[it] }
        } catch (e: Exception) {
            if (e is kotlinx.coroutines.CancellationException) throw e
            Log.w(TAG, "Semantic search failed for query \"$query\"", e)
        } finally {
            _isSemanticLoading.value = false
        }
    }

    /** Cancels any in-flight search job. Call from [BookmarkViewModel.onCleared]. */
    fun close() {
        semanticSearchJob?.cancel()
    }

    private companion object {
        private const val TAG = "SearchController"
        private const val DEBOUNCE_MS = 300L
    }
}
