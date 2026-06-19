package com.example.ui

import android.graphics.Bitmap
import android.os.CountDownTimer
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.example.data.AnalysisConfig
import com.example.data.DeepAnalysisResult
import com.example.data.XAiAnalyzer
import com.example.data.embedding.EmbeddingService
import com.example.data.embedding.VectorSearch
import com.example.data.embedding.VectorSearch.toByteArray
import com.example.data.embedding.VectorSearch.toFloatArray
import com.example.data.export.BibtexExporter
import com.example.data.ocr.OcrAnalyzer
import com.example.data.repo.RateLimitException
import com.example.data.source.SourceResolver
import com.example.domain.model.Bookmark
import com.example.domain.model.Space
import com.example.domain.model.SpaceRules
import com.example.domain.repo.BookmarkRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

enum class AppThemeSetting { SYSTEM, LIGHT, DARK }
enum class SearchMode { KEYWORD, SEMANTIC }
enum class QuickFilter { ALL, FAVORITES, READ_LATER }

sealed interface SyncUiState {
    object Idle : SyncUiState
    object Loading : SyncUiState
    data class Success(val message: String) : SyncUiState
    data class Error(val error: String) : SyncUiState
    data class RateLimited(val secondsLeft: Int) : SyncUiState
}

sealed interface AnalysisUiState {
    object Idle : AnalysisUiState
    data class Processing(val bookmarkId: String) : AnalysisUiState
    data class Success(val bookmarkId: String) : AnalysisUiState
    data class Error(val error: String) : AnalysisUiState
}

/** State of the on-demand weekly AI digest (themed summary of the last 7 days of saves). */
sealed interface DigestUiState {
    object Idle : DigestUiState
    object Loading : DigestUiState
    data class Ready(val markdown: String, val itemCount: Int) : DigestUiState
    data class Empty(val reason: String) : DigestUiState
    data class Error(val message: String) : DigestUiState
}

data class CurioStats(
    val totalCount: Int = 0,
    val curatedCount: Int = 0,
    val ocrCount: Int = 0,
    val categoryCounts: Map<String, Int> = emptyMap(),
    val topTags: List<Pair<String, Int>> = emptyList(),
    val sourceCount: Int = 0,
    val deepAnalyzedCount: Int = 0,
    val favoriteCount: Int = 0,
    val readLaterCount: Int = 0
)

class BookmarkViewModel(
    private val repository: BookmarkRepository,
    private val ocrAnalyzer: OcrAnalyzer,
    private val aiAnalyzer: XAiAnalyzer,
    private val embeddingService: com.example.data.embedding.EmbeddingProvider,
    private val sourceResolver: SourceResolver,
    private val textGenerator: com.example.data.ai.TextGeneratorSelector,
    private val grokImageService: com.example.data.GrokImageService,
    private val embeddingModelManager: com.example.data.embedding.EmbeddingModelManager
) : ViewModel() {

    /** Download state of the on-device EmbeddingGemma model (for the Settings card). */
    val embeddingModelState = embeddingModelManager.state

    /**
     * Downloads the on-device EmbeddingGemma weights + tokenizer. An optional Hugging Face [token]
     * (for the Gemma-license-gated repo) is persisted by the manager and reused on later attempts.
     */
    fun downloadEmbeddingModel(token: String? = null) {
        viewModelScope.launch {
            val ok = embeddingModelManager.download(token)
            _syncState.value = if (ok) SyncUiState.Success("On-device model ready")
            else SyncUiState.Error("Model download failed")
        }
    }

    /** Removes the downloaded model — embeddings fall back to the cloud path. */
    fun deleteEmbeddingModel() = embeddingModelManager.delete()

    /** Drops all stored vectors so they get rebuilt (use when switching embedding models/dimensions). */
    fun clearEmbeddingsForReindex() {
        viewModelScope.launch { repository.clearAllEmbeddings() }
    }

    private val _userId = MutableStateFlow<String?>(null)
    val userId: StateFlow<String?> = _userId.asStateFlow()

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
    fun setQuickFilter(filter: QuickFilter) {
        _quickFilter.value = if (_quickFilter.value == filter) QuickFilter.ALL else filter
    }

    /** When non-null, the feed is scoped to bookmarks filed in this Space. */
    private val _selectedSpaceId = MutableStateFlow<String?>(null)
    val selectedSpaceId: StateFlow<String?> = _selectedSpaceId.asStateFlow()
    fun selectSpace(spaceId: String?) { _selectedSpaceId.value = spaceId }

    private val _themeSetting = MutableStateFlow(AppThemeSetting.SYSTEM)
    val themeSetting: StateFlow<AppThemeSetting> = _themeSetting.asStateFlow()

    fun setThemeSetting(setting: AppThemeSetting) { _themeSetting.value = setting }

    val rawBookmarks: StateFlow<List<Bookmark>> = _userId
        .flatMapLatest { uid ->
            if (uid != null) repository.getBookmarksFlow(uid) else flowOf(emptyList())
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    // Bundle search-mode + semantic results + quick filter + space into one flow so the main combine stays within 5 args
    private data class SearchContext(
        val mode: SearchMode,
        val semanticResults: List<Bookmark>,
        val quickFilter: QuickFilter,
        val spaceId: String?
    )
    private val _searchContext = combine(_searchMode, _semanticResults, _quickFilter, _selectedSpaceId) { mode, results, quick, space ->
        SearchContext(mode, results, quick, space)
    }

    val bookmarks: StateFlow<List<Bookmark>> = combine(
        rawBookmarks, _searchQuery, _selectedCategory, _selectedTag, _searchContext
    ) { list, query, category, tag, ctx ->
        val mode = ctx.mode
        val semanticList = ctx.semanticResults
        val base = if (mode == SearchMode.SEMANTIC && query.isNotBlank()) semanticList else list
        base.filter { item ->
            val matchQuery = mode == SearchMode.SEMANTIC || query.isBlank() ||
                item.text.contains(query, ignoreCase = true) ||
                (item.title?.contains(query, ignoreCase = true) == true) ||
                (item.url?.contains(query, ignoreCase = true) == true) ||
                (item.summary?.contains(query, ignoreCase = true) == true) ||
                (item.ocrText?.contains(query, ignoreCase = true) == true) ||
                (item.sourceTitle?.contains(query, ignoreCase = true) == true) ||
                (item.sourceAbstract?.contains(query, ignoreCase = true) == true) ||
                item.tags.any { it.contains(query, ignoreCase = true) }

            val matchCategory = category == null || item.category?.equals(category, ignoreCase = true) == true
            val matchTag = tag == null || item.tags.any { it.equals(tag, ignoreCase = true) }
            val matchQuick = when (ctx.quickFilter) {
                QuickFilter.ALL -> true
                QuickFilter.FAVORITES -> item.isFavorite
                QuickFilter.READ_LATER -> item.isSavedForLater
            }
            val matchSpace = ctx.spaceId == null || item.spaceId == ctx.spaceId
            matchQuery && matchCategory && matchTag && matchQuick && matchSpace
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    /** User-created Spaces with live membership counts, newest first. */
    val spaces: StateFlow<List<Space>> = _userId
        .flatMapLatest { uid ->
            if (uid != null) {
                combine(repository.getSpacesFlow(uid), rawBookmarks) { spaceList, books ->
                    val counts = books.groupingBy { it.spaceId }.eachCount()
                    spaceList.map { it.copy(count = counts[it.id] ?: 0) }
                }
            } else flowOf(emptyList())
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val stats: StateFlow<CurioStats> = rawBookmarks
        .flatMapLatest { list ->
            val curated = list.count { it.isAnalyzed }
            val ocr = list.count { !it.ocrText.isNullOrBlank() }
            val withSource = list.count { it.sourceType != null }
            val deepAnalyzed = list.count { it.isDeepAnalyzed }
            val favorites = list.count { it.isFavorite }
            val readLater = list.count { it.isSavedForLater }
            val counts = mutableMapOf<String, Int>()
            val tagsMap = mutableMapOf<String, Int>()
            list.forEach { item ->
                item.category?.trim()?.takeIf { it.isNotEmpty() }?.let { counts[it] = (counts[it] ?: 0) + 1 }
                item.tags.forEach { tag -> tag.lowercase().trim().takeIf { it.isNotEmpty() }?.let { tagsMap[it] = (tagsMap[it] ?: 0) + 1 } }
            }
            flowOf(CurioStats(
                totalCount = list.size, curatedCount = curated, ocrCount = ocr,
                categoryCounts = counts, topTags = tagsMap.toList().sortedByDescending { it.second }.take(8),
                sourceCount = withSource, deepAnalyzedCount = deepAnalyzed,
                favoriteCount = favorites, readLaterCount = readLater
            ))
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), CurioStats())

    fun updateSearchQuery(query: String) {
        _searchQuery.value = query
        if (_searchMode.value == SearchMode.SEMANTIC && query.isNotBlank()) {
            runSemanticSearch(query)
        }
    }

    fun setSearchMode(mode: SearchMode) {
        _searchMode.value = mode
        if (mode == SearchMode.KEYWORD) _semanticResults.value = emptyList()
        else if (_searchQuery.value.isNotBlank()) runSemanticSearch(_searchQuery.value)
    }

    fun selectCategory(category: String?) { _selectedCategory.value = category }
    fun selectTag(tag: String?) { _selectedTag.value = tag }
    fun clearAllFilters() {
        _searchQuery.value = ""; _selectedCategory.value = null; _selectedTag.value = null
        _semanticResults.value = emptyList(); _searchMode.value = SearchMode.KEYWORD
        _quickFilter.value = QuickFilter.ALL; _selectedSpaceId.value = null
    }

    // ── Spaces ───────────────────────────────────────────────────────────────

    fun createSpace(
        name: String, color: Long, icon: String,
        description: String = "", rules: SpaceRules = SpaceRules.EMPTY, isPinned: Boolean = false
    ) {
        val uid = _userId.value ?: return
        val trimmed = name.trim().ifBlank { return }
        viewModelScope.launch {
            repository.createSpace(uid, trimmed, color, icon, description, rules, isPinned)
            // A brand-new Smart Space immediately sweeps in matching items that are still unfiled.
            if (rules.isActive) repository.applyRulesToLibrary(uid)
        }
    }

    fun updateSpace(
        id: String, name: String, color: Long, icon: String,
        description: String = "", rules: SpaceRules = SpaceRules.EMPTY, isPinned: Boolean = false
    ) {
        val trimmed = name.trim().ifBlank { return }
        viewModelScope.launch {
            repository.updateSpace(id, trimmed, color, icon, description, rules, isPinned)
            val uid = _userId.value
            if (uid != null && rules.isActive) repository.applyRulesToLibrary(uid)
        }
    }

    fun deleteSpace(id: String) {
        viewModelScope.launch {
            if (_selectedSpaceId.value == id) _selectedSpaceId.value = null
            repository.deleteSpace(id)
        }
    }

    /** Pins (or unpins) a Space so it sorts to the top of the list. */
    fun setSpacePinned(id: String, pinned: Boolean) {
        viewModelScope.launch { repository.setSpacePinned(id, pinned) }
    }

    /**
     * Explicit "Apply rules now" for a Smart Space — files every unfiled matching bookmark into it
     * and reports how many were swept in.
     */
    fun applySpaceRules(space: Space) {
        viewModelScope.launch {
            val count = repository.applySpaceRules(space.id)
            _syncState.value = SyncUiState.Success(
                if (count == 0) "No new matches for \"${space.name}\""
                else "Filed $count bookmark${if (count == 1) "" else "s"} into \"${space.name}\""
            )
        }
    }

    /** Files (or unfiles, when [spaceId] is null) the given bookmarks into a Space. */
    fun assignBookmarksToSpace(ids: List<String>, spaceId: String?) {
        if (ids.isEmpty()) return
        viewModelScope.launch { repository.assignToSpace(ids, spaceId) }
    }

    /**
     * Accepts the AI-category suggestion for an unfiled bookmark: ensures the Space matching its
     * [Bookmark.category] exists and files the bookmark into it. Categories never organise the UI
     * directly — they only *suggest* a Space here.
     */
    fun acceptCategorySuggestion(bookmark: Bookmark) {
        val uid = _userId.value ?: return
        val category = bookmark.category?.takeIf { it.isNotBlank() } ?: return
        viewModelScope.launch {
            repository.ensureCategorySpace(uid, category)?.let { spaceId ->
                repository.assignToSpace(listOf(bookmark.id), spaceId)
            }
        }
    }

    /** Creates a new Space and immediately files [ids] into it — the bulk "new space" shortcut. */
    fun createSpaceAndAssign(
        name: String, color: Long, icon: String, ids: List<String>,
        description: String = "", rules: SpaceRules = SpaceRules.EMPTY, isPinned: Boolean = false
    ) {
        val uid = _userId.value ?: return
        val trimmed = name.trim().ifBlank { return }
        viewModelScope.launch {
            val space = repository.createSpace(uid, trimmed, color, icon, description, rules, isPinned)
            if (ids.isNotEmpty()) repository.assignToSpace(ids, space.id)
            if (rules.isActive) repository.applyRulesToLibrary(uid)
        }
    }

    // ── Phase 12: Personal curation toggles ─────────────────────────────────

    fun toggleFavorite(bookmark: Bookmark) {
        viewModelScope.launch { repository.setFavorite(bookmark.id, !bookmark.isFavorite) }
    }

    fun toggleSavedForLater(bookmark: Bookmark) {
        viewModelScope.launch { repository.setSavedForLater(bookmark.id, !bookmark.isSavedForLater) }
    }

    /** Saves (or clears, when blank) the user's personal note on an entry. */
    fun updateNotes(bookmarkId: String, notes: String?) {
        viewModelScope.launch { repository.updateNotes(bookmarkId, notes) }
    }

    // ── Weekly AI digest ────────────────────────────────────────────────────
    private val _digestState = MutableStateFlow<DigestUiState>(DigestUiState.Idle)
    val digestState: StateFlow<DigestUiState> = _digestState.asStateFlow()

    /**
     * Generates a themed markdown digest of the last 7 days of saves via Grok. Surfaces an explicit
     * Empty state when nothing was saved this week so the UI never shows a misleading blank digest.
     */
    fun generateWeeklyDigest() {
        viewModelScope.launch {
            _digestState.value = DigestUiState.Loading
            val cutoff = System.currentTimeMillis() - DIGEST_WINDOW_MS
            val recent = rawBookmarks.value.filter { it.createdAt >= cutoff }
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
                _digestState.value = DigestUiState.Error(e.localizedMessage ?: "Digest generation failed")
            }
        }
    }

    fun dismissDigest() { _digestState.value = DigestUiState.Idle }

    // ── Resurfacing / spaced review ─────────────────────────────────────────
    private val _rediscoverOffset = MutableStateFlow(0)

    /**
     * A small rotating set of older, not-yet-starred saves that have a source link — items worth
     * revisiting. Oldest-first so genuinely forgotten saves resurface; [shuffleRediscover] rotates
     * the window. Empty until there are saves older than [REDISCOVER_MIN_AGE_MS].
     */
    val rediscoverPicks: StateFlow<List<Bookmark>> = combine(rawBookmarks, _rediscoverOffset) { all, offset ->
        val cutoff = System.currentTimeMillis() - REDISCOVER_MIN_AGE_MS
        val candidates = all
            .filter { !it.isFavorite && !it.url.isNullOrBlank() && it.createdAt <= cutoff }
            .sortedBy { it.createdAt }
        if (candidates.isEmpty()) emptyList()
        else {
            val start = offset % candidates.size
            (0 until minOf(REDISCOVER_BATCH, candidates.size)).map { candidates[(start + it) % candidates.size] }
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    /** Rotates to the next batch of rediscovery picks. */
    fun shuffleRediscover() { _rediscoverOffset.value += REDISCOVER_BATCH }

    private val _syncState = MutableStateFlow<SyncUiState>(SyncUiState.Idle)
    val syncState: StateFlow<SyncUiState> = _syncState.asStateFlow()

    private val _analysisState = MutableStateFlow<AnalysisUiState>(AnalysisUiState.Idle)
    val analysisState: StateFlow<AnalysisUiState> = _analysisState.asStateFlow()

    private val _forceLocalNano = MutableStateFlow(
        com.example.BuildConfig.XAI_API_KEY.isEmpty() ||
        com.example.BuildConfig.XAI_API_KEY == "MY_XAI_API_KEY"
    )
    val forceLocalNano: StateFlow<Boolean> = _forceLocalNano.asStateFlow()

    private var rateLimitTimer: CountDownTimer? = null

    /**
     * Text/URL shared into Curio from another app before the user was signed in. Held here and
     * flushed by [setUserId] once a user id is available (e.g. a share that cold-starts the app).
     */
    private var pendingSharedCapture: String? = null

    fun setUserId(userId: String) {
        _userId.value = userId
        // A share that cold-started the app may have queued a capture before we had a user id.
        pendingSharedCapture?.let { pending ->
            pendingSharedCapture = null
            addManualBookmark(pending)
        }
        // Auto-organisation on login: Smart-Space rules sweep first (user intent wins), then AI
        // categories seed default Spaces for anything still unfiled.
        viewModelScope.launch {
            runCatching { repository.applyRulesToLibrary(userId) }
            runCatching { repository.backfillCategorySpaces(userId) }
        }
        syncBookmarks(fetchNextPage = false)
    }

    /**
     * Ingests text or a URL shared into Curio from another app's share sheet, reusing the manual-add
     * path (persist → resolve primary source). If no user is signed in yet, the text is queued and
     * [setUserId] ingests it on sign-in.
     *
     * @return true if ingested immediately; false if deferred until the user signs in.
     */
    fun captureSharedText(rawText: String): Boolean {
        val text = rawText.trim()
        if (text.isEmpty()) return false
        return if (_userId.value != null) {
            addManualBookmark(text)
            true
        } else {
            pendingSharedCapture = text
            false
        }
    }

    fun setForceLocalNano(enabled: Boolean) { _forceLocalNano.value = enabled }

    fun syncBookmarks(fetchNextPage: Boolean = false) {
        val uid = _userId.value ?: return
        if (_syncState.value is SyncUiState.Loading || _syncState.value is SyncUiState.RateLimited) return
        viewModelScope.launch {
            _syncState.value = SyncUiState.Loading
            repository.syncBookmarks(uid, fetchNextPage)
                .onSuccess {
                    _syncState.value = SyncUiState.Success("Synchronized successfully")
                    resolveNewSources()
                }
                .onFailure { exception ->
                    if (exception is RateLimitException) startRateLimitCountDown(exception.resetTimeSeconds)
                    else _syncState.value = SyncUiState.Error(exception.localizedMessage ?: "Sync failed")
                }
        }
    }

    private fun startRateLimitCountDown(seconds: Int) {
        rateLimitTimer?.cancel()
        _syncState.value = SyncUiState.RateLimited(seconds)
        rateLimitTimer = object : CountDownTimer(seconds * 1000L, 1000) {
            override fun onTick(ms: Long) { _syncState.value = SyncUiState.RateLimited((ms / 1000).toInt()) }
            override fun onFinish() { _syncState.value = SyncUiState.Idle }
        }.start()
    }

    fun processOcrForBookmark(bookmarkId: String, bitmap: Bitmap) {
        viewModelScope.launch {
            _analysisState.value = AnalysisUiState.Processing(bookmarkId)
            repository.updateOcrContent(bookmarkId, ocrText = null, isOcrScheduled = true)
            val text = ocrAnalyzer.analyze(bitmap)
            repository.updateOcrContent(bookmarkId, ocrText = text, isOcrScheduled = false)
            _analysisState.value = AnalysisUiState.Success(bookmarkId)
        }
    }

    fun runAiAnalysis(bookmark: Bookmark) {
        viewModelScope.launch {
            _analysisState.value = AnalysisUiState.Processing(bookmark.id)
            try {
                val result = textGenerator.analyze(
                    text = bookmark.text,
                    ocrText = bookmark.ocrText,
                    sourceAbstract = bookmark.sourceAbstract,
                    forceLocal = _forceLocalNano.value,
                    // Let Grok read the bookmark's image directly (vision) when one is attached.
                    imageUrl = bookmark.imageUrl
                )
                val suggestedTags = if (result.category.isNotBlank()) {
                    val catTag = result.category.lowercase().trim()
                    if (!result.tags.map { it.lowercase().trim() }.contains(catTag)) result.tags + catTag
                    else result.tags
                } else result.tags

                repository.updateAnalysisAndTags(
                    id = bookmark.id, summary = result.summary, category = result.category,
                    tags = suggestedTags, entities = result.entities
                )

                // Auto-filing precedence (only for still-unfiled items, never overriding a manual
                // choice): a user-authored Smart Space rule wins; otherwise the AI category seeds
                // its default Space. The freshly-analysed bookmark carries the new category/tags so
                // rules can match on them.
                val uid = _userId.value
                if (uid != null && bookmark.spaceId == null) {
                    val analysed = bookmark.copy(
                        summary = result.summary, category = result.category,
                        tags = suggestedTags, entities = result.entities, isAnalyzed = true
                    )
                    val filedByRule = repository.fileByRules(analysed)
                    if (filedByRule == null && result.category.isNotBlank()) {
                        repository.ensureCategorySpace(uid, result.category)?.let { spaceId ->
                            repository.assignToSpace(listOf(bookmark.id), spaceId)
                        }
                    }
                }

                _analysisState.value = AnalysisUiState.Success(bookmark.id)

                // Auto-generate embedding after successful analysis
                if (!_forceLocalNano.value) {
                    generateEmbeddingForBookmark(bookmark.id)
                }
            } catch (e: Exception) {
                _analysisState.value = AnalysisUiState.Error(e.localizedMessage ?: "AI analysis error")
            }
        }
    }

    fun runDeepAnalysis(bookmark: Bookmark) {
        viewModelScope.launch {
            _analysisState.value = AnalysisUiState.Processing(bookmark.id)
            try {
                val result: DeepAnalysisResult = aiAnalyzer.deepAnalyzeBookmark(
                    text = bookmark.text,
                    ocrText = bookmark.ocrText,
                    sourceAbstract = bookmark.sourceAbstract
                )
                repository.updateDeepSummary(bookmark.id, result.formatted())
                _analysisState.value = AnalysisUiState.Success(bookmark.id)
            } catch (e: Exception) {
                _analysisState.value = AnalysisUiState.Error(e.localizedMessage ?: "Deep analysis error")
            }
        }
    }

    // ── Phase 8: Source resolution ─────────────────────────────────────────

    fun resolveSource(bookmark: Bookmark) {
        viewModelScope.launch {
            _analysisState.value = AnalysisUiState.Processing(bookmark.id)
            try {
                val info = sourceResolver.resolve(bookmark.text, bookmark.url)
                if (info != null) {
                    val uid = _userId.value ?: return@launch
                    val existingWithSource = if (info.sourceId != null) {
                        rawBookmarks.value.find {
                            it.id != bookmark.id && it.sourceId == info.sourceId
                        }
                    } else null

                    if (existingWithSource != null) {
                        repository.incrementReferenceCount(info.sourceId!!, uid)
                        repository.deleteBookmarks(listOf(bookmark.id))
                    } else {
                        repository.updateSourceInfo(
                            id = bookmark.id,
                            sourceType = info.sourceType,
                            sourceId = info.sourceId,
                            sourceTitle = info.sourceTitle,
                            sourceAuthors = info.sourceAuthors,
                            sourceAbstract = info.sourceAbstract,
                            sourceExtra = info.sourceExtra
                        )
                    }
                }
                _analysisState.value = AnalysisUiState.Success(bookmark.id)
            } catch (e: Exception) {
                _analysisState.value = AnalysisUiState.Error(e.localizedMessage ?: "Source resolution failed")
            }
        }
    }

    fun resolveNewSources() {
        viewModelScope.launch {
            val unresolved = rawBookmarks.value.filter { it.sourceType == null && it.url != null }
            unresolved.take(10).forEach { bookmark ->
                try {
                    val info = sourceResolver.resolve(bookmark.text, bookmark.url)
                    if (info != null) {
                        repository.updateSourceInfo(
                            id = bookmark.id, sourceType = info.sourceType, sourceId = info.sourceId,
                            sourceTitle = info.sourceTitle, sourceAuthors = info.sourceAuthors,
                            sourceAbstract = info.sourceAbstract, sourceExtra = info.sourceExtra
                        )
                    }
                } catch (e: Exception) {
                    // Per-bookmark resolution failures are non-fatal — one bad URL shouldn't
                    // abort the batch — but log so a systemic failure (bad key, no network)
                    // is diagnosable instead of vanishing.
                    Log.w(TAG, "Source resolution failed for ${bookmark.id}", e)
                }
            }
        }
    }

    fun deduplicateBySource() {
        val uid = _userId.value ?: return
        viewModelScope.launch {
            try {
                repository.deduplicateBySource(uid)
                _syncState.value = SyncUiState.Success("Deduplication complete")
            } catch (e: Exception) {
                _syncState.value = SyncUiState.Error("Dedup failed: ${e.localizedMessage}")
            }
        }
    }

    // ── Phase 10: Semantic search ───────────────────────────────────────────

    private fun runSemanticSearch(query: String) {
        val uid = _userId.value ?: return
        viewModelScope.launch {
            _isSemanticLoading.value = true
            try {
                val queryEmbedding = embeddingService.embedQuery(query) ?: run {
                    _isSemanticLoading.value = false
                    return@launch
                }
                val allEmbeddings = repository.getBookmarksWithEmbeddings(uid)
                    .map { (id, bytes) -> id to bytes.toFloatArray() }

                if (allEmbeddings.isEmpty()) {
                    _isSemanticLoading.value = false
                    return@launch
                }

                val topIds = VectorSearch.topK(queryEmbedding, allEmbeddings, k = 20).toSet()
                val bookmarkMap = rawBookmarks.value.associateBy { it.id }
                _semanticResults.value = topIds.mapNotNull { bookmarkMap[it] }
            } catch (e: Exception) {
                Log.w(TAG, "Semantic search failed for query \"$query\"", e)
                _isSemanticLoading.value = false
            } finally {
                _isSemanticLoading.value = false
            }
        }
    }

    private fun generateEmbeddingForBookmark(bookmarkId: String) {
        viewModelScope.launch {
            try {
                val bookmark = rawBookmarks.value.find { it.id == bookmarkId } ?: return@launch
                val embedding = embeddingService.embedDocument(bookmark) ?: return@launch
                repository.updateEmbedding(bookmarkId, embedding.toByteArray())
            } catch (e: Exception) {
                Log.w(TAG, "Embedding generation failed for $bookmarkId", e)
            }
        }
    }

    fun embedAllBookmarks() {
        viewModelScope.launch {
            val unembedded = rawBookmarks.value.filter { it.isAnalyzed }
            var succeeded = 0
            var failed = 0
            unembedded.take(50).forEach { bookmark ->
                try {
                    val embedding = embeddingService.embedDocument(bookmark) ?: run { failed++; return@forEach }
                    repository.updateEmbedding(bookmark.id, embedding.toByteArray())
                    succeeded++
                } catch (e: Exception) {
                    failed++
                    Log.w(TAG, "Embedding generation failed for ${bookmark.id}", e)
                }
            }
            // Report the real outcome: if every item failed, the previous code still claimed
            // success, hiding a broken embedding provider from the user.
            _syncState.value = if (succeeded == 0 && failed > 0) {
                SyncUiState.Error("Embedding unavailable — generated 0 of $failed items")
            } else {
                SyncUiState.Success("Embeddings generated for $succeeded items" + if (failed > 0) " ($failed skipped)" else "")
            }
        }
    }

    // ── Phase 11: BibTeX export ─────────────────────────────────────────────

    fun exportBibtex(bookmarks: List<Bookmark>): String =
        BibtexExporter.toBibtexList(bookmarks)

    fun exportSingleBibtex(bookmark: Bookmark): String? =
        BibtexExporter.toBibtex(bookmark)

    // ── Existing operations ─────────────────────────────────────────────────

    fun deleteBookmarks(ids: List<String>) {
        viewModelScope.launch { repository.deleteBookmarks(ids) }
    }

    fun updateCategoryForBookmarks(ids: List<String>, category: String) {
        viewModelScope.launch { repository.updateCategoryForIds(ids, category) }
    }

    fun clearAllData() {
        val uid = _userId.value ?: return
        viewModelScope.launch { repository.clearAll(uid) }
    }

    fun moveBookmarkUp(bookmark: Bookmark) {
        viewModelScope.launch {
            val list = rawBookmarks.value
            val index = list.indexOfFirst { it.id == bookmark.id }
            if (index > 0) {
                val upper = list[index - 1]
                repository.updateCreatedAt(bookmark.id, upper.createdAt)
                repository.updateCreatedAt(upper.id, bookmark.createdAt)
            }
        }
    }

    fun moveBookmarkDown(bookmark: Bookmark) {
        viewModelScope.launch {
            val list = rawBookmarks.value
            val index = list.indexOfFirst { it.id == bookmark.id }
            if (index != -1 && index < list.size - 1) {
                val lower = list[index + 1]
                repository.updateCreatedAt(bookmark.id, lower.createdAt)
                repository.updateCreatedAt(lower.id, bookmark.createdAt)
            }
        }
    }

    fun getInstantSummaryPreview(text: String, onCompleted: (String) -> Unit) {
        viewModelScope.launch {
            try {
                val result = textGenerator.analyze(text, null, null, forceLocal = false)
                onCompleted("✨ Category: ${result.category}\n🏷️ Tags: ${result.tags.joinToString(", ")}\n📝 Summary: ${result.summary}")
            } catch (e: Exception) {
                onCompleted("❌ Analysis failed: ${e.localizedMessage ?: "Unknown error"}. Ensure a valid XAI_API_KEY is set.")
            }
        }
    }

    // ── Chat with RAG + Live Search grounding ───────────────────────────────

    private val _chatMessages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val chatMessages: StateFlow<List<ChatMessage>> = _chatMessages.asStateFlow()

    private val _isChatLoading = MutableStateFlow(false)
    val isChatLoading: StateFlow<Boolean> = _isChatLoading.asStateFlow()

    /** Grounding sources the user has toggled on. [ChatSource.LIBRARY] is on by default. */
    private val _chatSources = MutableStateFlow(setOf(ChatSource.LIBRARY))
    val chatSources: StateFlow<Set<ChatSource>> = _chatSources.asStateFlow()

    fun toggleChatSource(source: ChatSource) {
        _chatSources.value = _chatSources.value.toMutableSet().apply {
            if (!add(source)) remove(source)
        }.ifEmpty { setOf(ChatSource.LIBRARY) }
    }

    /** Resets the conversation back to the empty welcome state. */
    fun clearChat() {
        _chatMessages.value = emptyList()
        _isChatLoading.value = false
    }

    fun sendChatMessage(textInput: String) {
        if (textInput.isBlank()) return
        val sources = _chatSources.value
        val userMsg = ChatMessage(id = java.util.UUID.randomUUID().toString(), sender = ChatSender.USER, text = textInput)
        _chatMessages.value = _chatMessages.value + userMsg
        _isChatLoading.value = true
        viewModelScope.launch {
            try {
                val uid = _userId.value
                val useLibrary = ChatSource.LIBRARY in sources
                val contextItems = if (useLibrary) {
                    if (uid != null) retrieveRagContext(textInput, uid) else rawBookmarks.value.take(15)
                } else emptyList()

                val contextPrompt = buildString {
                    if (contextItems.isNotEmpty()) {
                        appendLine("Research library context (semantically retrieved):")
                        contextItems.forEach { b ->
                            val sourceInfo = if (b.sourceType != null) "[${b.sourceType?.name}:${b.sourceId}] " else ""
                            appendLine("- ${sourceInfo}${b.sourceTitle ?: b.title ?: "Untitled"}")
                            if (!b.sourceAuthors.isNullOrBlank()) appendLine("  Authors: ${b.sourceAuthors}")
                            appendLine("  Category: ${b.category ?: "?"} | Tags: ${b.tags.take(4).joinToString(",")}")
                            if (!b.summary.isNullOrBlank()) appendLine("  Summary: ${b.summary}")
                            if (!b.deepSummary.isNullOrBlank()) appendLine("  Deep: ${b.deepSummary?.take(200)}")
                        }
                    } else if (useLibrary) {
                        appendLine("Library is empty.")
                    }
                    appendLine("\nUser query: \"$textInput\"")
                }

                // Live Search sources beyond the local library (web / x / news).
                val liveSources = sources.mapNotNull { src ->
                    when (src) {
                        ChatSource.WEB -> com.example.data.remote.XAiSearchSource.web()
                        ChatSource.X -> com.example.data.remote.XAiSearchSource.x()
                        ChatSource.NEWS -> com.example.data.remote.XAiSearchSource.news()
                        ChatSource.LIBRARY -> null
                    }
                }
                val searchParams = if (liveSources.isNotEmpty()) {
                    com.example.data.remote.XAiSearchParameters(
                        mode = com.example.data.remote.GrokSearchMode.ON,
                        returnCitations = true,
                        maxSearchResults = 12,
                        sources = liveSources
                    )
                } else null

                val liveLabels = sources.filter { it != ChatSource.LIBRARY }.joinToString("/") { it.label }
                val sysInst = buildString {
                    appendLine("You are Curio Research Assistant — a personal AI for an ML researcher's saved papers and repos.")
                    if (useLibrary) appendLine("Prefer the retrieved library context. Cite paper titles and arXiv IDs when relevant.")
                    if (searchParams != null) appendLine("You also have live $liveLabels search — use it to ground claims and cite sources with markdown links.")
                    appendLine("Use markdown (headings, bold, bullets, links). Keep answers concise and formatted for mobile screens.")
                }.trimIndent()

                val aiResponse = aiAnalyzer.generateChatResponse(contextPrompt, sysInst, searchParams)
                _chatMessages.value = _chatMessages.value + ChatMessage(
                    id = java.util.UUID.randomUUID().toString(),
                    sender = ChatSender.AI,
                    text = aiResponse.text,
                    citations = aiResponse.citations,
                    groundedIn = sources.toList()
                )
            } catch (e: Exception) {
                _chatMessages.value = _chatMessages.value + ChatMessage(
                    id = java.util.UUID.randomUUID().toString(), sender = ChatSender.AI,
                    text = "Failed to respond: ${e.localizedMessage}"
                )
            } finally {
                _isChatLoading.value = false
            }
        }
    }

    private suspend fun retrieveRagContext(query: String, userId: String): List<Bookmark> {
        return try {
            val queryEmbedding = embeddingService.embedQuery(query) ?: return rawBookmarks.value.take(15)
            val allEmbeddings = repository.getBookmarksWithEmbeddings(userId)
                .map { (id, bytes) -> id to bytes.toFloatArray() }
            if (allEmbeddings.isEmpty()) return rawBookmarks.value.take(15)
            val topIds = VectorSearch.topK(queryEmbedding, allEmbeddings, k = 15).toSet()
            val bookmarkMap = rawBookmarks.value.associateBy { it.id }
            topIds.mapNotNull { bookmarkMap[it] }
        } catch (e: Exception) {
            rawBookmarks.value.take(15)
        }
    }

    fun addManualBookmark(text: String, onResult: (Result<Bookmark>) -> Unit = {}) {
        val uid = _userId.value ?: return
        viewModelScope.launch {
            val res = repository.addBookmark(uid, text)
            onResult(res)
            res.getOrNull()?.let { bookmark -> resolveSource(bookmark) }
        }
    }

    private val _imagenGeneratedIds = MutableStateFlow<Set<String>>(emptySet())
    val imagenGeneratedIds = _imagenGeneratedIds.asStateFlow()

    /** Bookmark id -> Grok-generated cover image URL (empty when the procedural fallback is used). */
    private val _imagenUrls = MutableStateFlow<Map<String, String>>(emptyMap())
    val imagenUrls = _imagenUrls.asStateFlow()

    /**
     * Generates a representative cover image for a bookmark via Grok's image model. Falls back to
     * the procedural category graphic (no URL stored) when the API key is absent or the call fails,
     * so the card always ends up in the "generated" state.
     */
    fun generateImagenImage(bookmarkId: String) {
        viewModelScope.launch {
            _analysisState.value = AnalysisUiState.Processing(bookmarkId)
            val bookmark = rawBookmarks.value.firstOrNull { it.id == bookmarkId }
            val prompt = grokImageService.promptForCategory(
                category = bookmark?.category,
                title = bookmark?.sourceTitle ?: bookmark?.title
            )
            val generated = grokImageService.generate(prompt)
            if (generated != null) {
                _imagenUrls.value = _imagenUrls.value + (bookmarkId to generated.url)
            }
            _imagenGeneratedIds.value = _imagenGeneratedIds.value + bookmarkId
            _analysisState.value = AnalysisUiState.Success(bookmarkId)
        }
    }

    override fun onCleared() {
        super.onCleared()
        rateLimitTimer?.cancel()
    }

    companion object {
        private const val TAG = "BookmarkViewModel"
        private const val DIGEST_WINDOW_MS = 7L * 24 * 60 * 60 * 1000 // last 7 days
        private const val DIGEST_MAX_ITEMS = 40                       // cap tokens/cost per digest
        private const val REDISCOVER_MIN_AGE_MS = 14L * 24 * 60 * 60 * 1000 // only resurface 2-week-old saves
        private const val REDISCOVER_BATCH = 3                              // picks shown at once
    }

    class Factory(
        private val repository: BookmarkRepository,
        private val ocrAnalyzer: OcrAnalyzer,
        private val aiAnalyzer: XAiAnalyzer,
        private val embeddingService: com.example.data.embedding.EmbeddingProvider,
        private val sourceResolver: SourceResolver,
        private val textGenerator: com.example.data.ai.TextGeneratorSelector,
        private val grokImageService: com.example.data.GrokImageService,
        private val embeddingModelManager: com.example.data.embedding.EmbeddingModelManager
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            BookmarkViewModel(repository, ocrAnalyzer, aiAnalyzer, embeddingService, sourceResolver, textGenerator, grokImageService, embeddingModelManager) as T
    }
}

data class ChatMessage(
    val id: String,
    val sender: ChatSender,
    val text: String,
    val timestamp: Long = System.currentTimeMillis(),
    /** Source URLs that grounded an AI reply (from xAI Live Search). */
    val citations: List<String> = emptyList(),
    /** Which live sources were queried for this reply, for the "grounded in" badge. */
    val groundedIn: List<ChatSource> = emptyList()
)

enum class ChatSender { USER, AI }

/**
 * A grounding source the user can toggle on for a chat turn. [LIBRARY] is the always-on
 * semantic search over saved bookmarks; the rest enable xAI Live Search against the
 * corresponding real-time source. [apiType] is the xAI source identifier (null for the
 * local library, which never hits Live Search).
 */
enum class ChatSource(val label: String, val apiType: String?) {
    LIBRARY("Library", null),
    WEB("Web", "web"),
    X("X", "x"),
    NEWS("News", "news")
}
