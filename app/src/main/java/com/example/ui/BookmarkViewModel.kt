package com.example.ui

import android.graphics.Bitmap
import android.os.CountDownTimer
import android.util.Log
import androidx.lifecycle.ViewModel
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
import com.example.interop.ChronosReminderChoice
import com.example.notifications.CurioTask
import com.example.domain.model.Space
import com.example.domain.model.SourceType
import com.example.domain.model.SpaceRules
import com.example.domain.repo.BookmarkRepository
import com.example.ui.theme.GlassTier
import kotlinx.coroutines.delay
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

enum class AppThemeSetting { SYSTEM, LIGHT, DARK }
enum class SearchMode { KEYWORD, SEMANTIC }
enum class QuickFilter { ALL, FAVORITES, READ_LATER }

/** Insights stat-tile drill-down filter applied on the bookmark feed. */
enum class LibraryFilter { ALL, HAS_OCR, HAS_SOURCE, DEEP_ANALYZED }

sealed interface SyncUiState {
    object Idle : SyncUiState
    /**
     * A long-running operation is in flight. [message] is an optional live progress note (e.g.
     * "Embedding 12/50…"); when null the UI falls back to the X.com feed-sync copy. Making this a
     * data class lets embed/resolve/dedup surface running counts so the user can see it working.
     */
    data class Loading(val message: String? = null) : SyncUiState
    data class Success(val message: String) : SyncUiState
    data class Error(val error: String) : SyncUiState
    data class RateLimited(val secondsLeft: Int) : SyncUiState
}

sealed interface AnalysisUiState {
    object Idle : AnalysisUiState
    data class Processing(val bookmarkId: String) : AnalysisUiState
    data class Success(val bookmarkId: String) : AnalysisUiState
    data class Error(val error: String, val bookmarkId: String? = null) : AnalysisUiState
}

/** State of the on-demand weekly AI digest (themed summary of the last 7 days of saves). */
sealed interface DigestUiState {
    object Idle : DigestUiState
    object Loading : DigestUiState
    data class Ready(val markdown: String, val itemCount: Int) : DigestUiState
    data class Empty(val reason: String) : DigestUiState
    data class Error(val message: String) : DigestUiState
}

/** How the active xAI key got into memory — shown verbatim to the user in Settings. */
enum class XaiKeyOrigin { LOADED_FROM_STORAGE, JUST_SAVED }

/** Verification progress/result for the active xAI key (Settings → xAI API Key status line). */
sealed interface XaiKeyCheck {
    object Checking : XaiKeyCheck
    object Live : XaiKeyCheck
    data class Invalid(val reason: String) : XaiKeyCheck
    /** Key is stored, but xAI couldn't be reached to confirm it works (e.g. offline). */
    object Unreachable : XaiKeyCheck
}

/**
 * Full key state for the Settings card: no key at all, or a present key annotated with where it
 * came from ([XaiKeyOrigin]) and whether it actually works ([XaiKeyCheck]).
 */
sealed interface XaiKeyStatus {
    /** Initial state before the async TokenStore read completes. */
    object Unknown : XaiKeyStatus
    object NotSet : XaiKeyStatus
    data class Present(val origin: XaiKeyOrigin, val check: XaiKeyCheck) : XaiKeyStatus
}

/** State of the user-supplied X OAuth client ID (BYOK for bookmark sync). */
enum class XClientIdStatus {
    /** No custom ID saved — the build-time/built-in client ID is in use. */
    BUILT_IN,
    /** A custom ID was found in encrypted storage at startup. */
    CUSTOM_LOADED,
    /** A custom ID was saved in this session. */
    CUSTOM_SAVED
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
    private val embeddingModelManager: com.example.data.embedding.EmbeddingModelManager,
    private val tokenStore: com.example.data.remote.TokenStore,
    private val chronosFlowBridge: com.example.interop.ChronosFlowBridge,
    private val curioActivityController: com.example.notifications.CurioActivityController,
    private val reminderScheduler: com.example.notifications.ReminderScheduler,
    private val semanticLayer: com.example.data.semantic.OnDeviceSemanticLayer
) : ViewModel() {

    /** Download state of the on-device EmbeddingGemma model (for the Settings card). */
    val embeddingModelState = embeddingModelManager.state

    /** Whether the on-device semantic layer (cache + compression + routing) is enabled. */
    private val _semanticLayerEnabled = MutableStateFlow(semanticLayer.isEnabled())
    val semanticLayerEnabled: StateFlow<Boolean> = _semanticLayerEnabled.asStateFlow()

    fun setSemanticLayerEnabled(enabled: Boolean) {
        semanticLayer.setEnabled(enabled)
        _semanticLayerEnabled.value = enabled
    }

    /**
     * Downloads the on-device EmbeddingGemma weights + tokenizer. An optional Hugging Face [token]
     * (for the Gemma-license-gated repo) is persisted by the manager and reused on later attempts.
     */
    fun downloadEmbeddingModel(token: String? = null) {
        viewModelScope.launch {
            embeddingModelManager.download(token)
            // Mirror the *actual* terminal state into the global banner rather than the raw boolean:
            // a `false` can also mean "ignored a re-entrant tap while a download is already running",
            // which must not surface as a failure. Reading the state also gives the real error text.
            when (val s = embeddingModelManager.state.value) {
                is com.example.data.embedding.EmbeddingModelManager.State.Ready ->
                    setTransientSyncState(SyncUiState.Success("On-device model ready"))
                is com.example.data.embedding.EmbeddingModelManager.State.Failed ->
                    _syncState.value = SyncUiState.Error(s.message)
                else -> { /* still downloading (elsewhere) or no-op — leave the banner untouched */ }
            }
        }
    }

    /** Removes the downloaded model — embeddings fall back to the cloud path. */
    fun deleteEmbeddingModel() {
        embeddingModelManager.onDeleted?.invoke()
        embeddingModelManager.delete()
    }

    /** Drops all stored vectors so they get rebuilt (use when switching embedding models/dimensions). */
    fun clearEmbeddingsForReindex() {
        _spaceSuggestions.value = emptyMap()
        viewModelScope.launch { repository.clearAllEmbeddings() }
    }

    private val _userId = MutableStateFlow<String?>(null)
    val userId: StateFlow<String?> = _userId.asStateFlow()

    // Search/filter input state lives in SearchController to shrink this god class; the VM facades
    // its flows + setters so the UI is unchanged. rawBookmarks/_userId are read lazily via the
    // suppliers, so the forward reference to rawBookmarks (declared below) is safe.
    private val searchController = SearchController(
        scope = viewModelScope,
        embeddingService = embeddingService,
        repository = repository,
        rawBookmarks = { rawBookmarks.value },
        currentUserId = { _userId.value }
    )
    val searchQuery: StateFlow<String> = searchController.searchQuery
    val searchMode: StateFlow<SearchMode> = searchController.searchMode
    val semanticResults: StateFlow<List<Bookmark>> = searchController.semanticResults
    val isSemanticLoading: StateFlow<Boolean> = searchController.isSemanticLoading
    val selectedCategory: StateFlow<String?> = searchController.selectedCategory
    val selectedTag: StateFlow<String?> = searchController.selectedTag
    val quickFilter: StateFlow<QuickFilter> = searchController.quickFilter
    /** When non-null, the feed is scoped to bookmarks filed in this Space. */
    val selectedSpaceId: StateFlow<String?> = searchController.selectedSpaceId

    fun setQuickFilter(filter: QuickFilter) = searchController.setQuickFilter(filter)
    fun setLibraryFilter(filter: LibraryFilter) = searchController.setLibraryFilter(filter)
    fun selectSpace(spaceId: String?) = searchController.selectSpace(spaceId)

    // Embedding-derived Space suggestions, keyed by bookmark id — the medium-confidence matches the
    // auto-organiser wasn't sure enough to file. The card surfaces these as a tap-to-file pill.
    private val _spaceSuggestions = MutableStateFlow<Map<String, com.example.domain.model.SpaceSuggestion>>(emptyMap())
    val spaceSuggestions: StateFlow<Map<String, com.example.domain.model.SpaceSuggestion>> = _spaceSuggestions.asStateFlow()

    /** OS dark-style preference; persisted across app restarts. */
    val themeSetting: StateFlow<AppThemeSetting> =
        tokenStore.themeSettingFlow
            .map { raw ->
                raw?.let { runCatching { AppThemeSetting.valueOf(it) }.getOrNull() }
                    ?: AppThemeSetting.DARK
            }
            .stateIn(viewModelScope, SharingStarted.Eagerly, AppThemeSetting.DARK)

    fun setThemeSetting(setting: AppThemeSetting) {
        viewModelScope.launch { tokenStore.setThemeSetting(setting.name) }
    }

    /** Material You dynamic-color toggle; persisted across app restarts. */
    val useDynamicColor: StateFlow<Boolean> =
        tokenStore.useDynamicColorFlow.stateIn(viewModelScope, SharingStarted.Eagerly, false)

    fun setUseDynamicColor(enabled: Boolean) {
        viewModelScope.launch { tokenStore.setUseDynamicColor(enabled) }
    }

    /** Manual glass-tier override (null = Auto); persisted across app restarts. */
    val glassTierOverride: StateFlow<GlassTier?> =
        tokenStore.glassTierOverrideFlow
            .map { raw ->
                raw?.takeIf { it.isNotBlank() }
                    ?.let { runCatching { GlassTier.valueOf(it) }.getOrNull() }
            }
            .stateIn(viewModelScope, SharingStarted.Eagerly, null)

    fun setGlassTierOverride(tier: GlassTier?) {
        viewModelScope.launch { tokenStore.setGlassTierOverride(tier?.name) }
    }

    val rawBookmarks: StateFlow<List<Bookmark>> = _userId
        .flatMapLatest { uid ->
            if (uid != null) repository.getBookmarksFlow(uid) else flowOf(emptyList())
        }
        // Eagerly because background jobs (embedAllBookmarks, resolveNewSources, etc.) read
        // rawBookmarks.value even when there is no UI subscriber — WhileSubscribed would let the
        // upstream DB flow lapse and those jobs would see a stale empty list.
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    // Bundle search-mode + semantic results + quick filter + space into one flow so the main combine stays within 5 args
    private data class SearchContext(
        val mode: SearchMode,
        val semanticResults: List<Bookmark>,
        val quickFilter: QuickFilter,
        val spaceId: String?,
        val libraryFilter: LibraryFilter
    )
    private val _searchContext = combine(
        searchController.searchMode, searchController.semanticResults,
        searchController.quickFilter, searchController.selectedSpaceId,
        searchController.libraryFilter
    ) { mode, results, quick, space, library ->
        SearchContext(mode, results, quick, space, library)
    }

    val bookmarks: StateFlow<List<Bookmark>> = combine(
        rawBookmarks, searchController.searchQuery, searchController.selectedCategory,
        searchController.selectedTag, _searchContext
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
            val matchLibrary = when (ctx.libraryFilter) {
                LibraryFilter.ALL -> true
                LibraryFilter.HAS_OCR -> !item.ocrText.isNullOrBlank()
                LibraryFilter.HAS_SOURCE -> item.sourceType != null
                LibraryFilter.DEEP_ANALYZED -> item.isDeepAnalyzed
            }
            matchQuery && matchCategory && matchTag && matchQuick && matchSpace && matchLibrary
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

    init {
        viewModelScope.launch {
            combine(rawBookmarks, spaces) { books, sp -> books to sp.map { it.id }.toSet() }
                .collect { (books, spaceIds) -> pruneStaleSuggestions(books, spaceIds) }
        }
    }

    val stats: StateFlow<CurioStats> = rawBookmarks
        .map { list ->
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
            CurioStats(
                totalCount = list.size, curatedCount = curated, ocrCount = ocr,
                categoryCounts = counts, topTags = tagsMap.toList().sortedByDescending { it.second }.take(8),
                sourceCount = withSource, deepAnalyzedCount = deepAnalyzed,
                favoriteCount = favorites, readLaterCount = readLater
            )
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), CurioStats())

    fun updateSearchQuery(query: String) = searchController.updateQuery(query)
    fun setSearchMode(mode: SearchMode) = searchController.setMode(mode)
    fun selectCategory(category: String?) = searchController.selectCategory(category)
    fun selectTag(tag: String?) = searchController.selectTag(tag)
    fun clearAllFilters() = searchController.clearAll()

    // ── Spaces ───────────────────────────────────────────────────────────────

    fun createSpace(
        name: String, color: Long, icon: String,
        description: String = "", rules: SpaceRules = SpaceRules.EMPTY, isPinned: Boolean = false
    ) {
        val uid = _userId.value ?: return
        val trimmed = name.trim().ifBlank { return }
        viewModelScope.launch {
            val space = repository.createSpace(uid, trimmed, color, icon, description, rules, isPinned)
            if (rules.isActive) {
                val count = repository.applySpaceRules(space.id)
                if (rules.autoFile) repository.applyRulesToLibrary(uid)
                reportSpaceRulesResult(count, trimmed)
                scheduleOrganizeAfterEmbed()
            }
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
            if (uid != null && rules.isActive) {
                val count = repository.applySpaceRules(id)
                if (rules.autoFile) repository.applyRulesToLibrary(uid)
                reportSpaceRulesResult(count, trimmed)
                scheduleOrganizeAfterEmbed()
            }
        }
    }

    fun deleteSpace(id: String) {
        viewModelScope.launch {
            searchController.clearSpaceIf(id)
            _spaceSuggestions.value = _spaceSuggestions.value.filterValues { it.spaceId != id }
            repository.deleteSpace(id)
            scheduleOrganizeAfterEmbed()
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
            reportSpaceRulesResult(count, space.name)
            if (count > 0) scheduleOrganizeAfterEmbed()
        }
    }

    private fun reportSpaceRulesResult(count: Int, spaceName: String) {
        setTransientSyncState(
            SyncUiState.Success(
                if (count == 0) "No new matches for \"$spaceName\""
                else "Filed $count bookmark${if (count == 1) "" else "s"} into \"$spaceName\""
            )
        )
    }

    /** Files (or unfiles, when [spaceId] is null) the given bookmarks into a Space. */
    // Per-bookmark mutations (curation toggles, notes, delete, category/space assignment) live in
    // CurationController to shrink this god class; the VM facades them so the UI is unchanged.
    private val curationController = CurationController(viewModelScope, repository)
    val curationError: kotlinx.coroutines.flow.SharedFlow<String> = curationController.curationError

    fun assignBookmarksToSpace(ids: List<String>, spaceId: String?) {
        if (ids.isNotEmpty()) {
            _spaceSuggestions.value = _spaceSuggestions.value - ids.toSet()
        }
        curationController.assignToSpace(ids, spaceId)
        // Filing or un-filing changes centroids and the unfiled set → refresh suggestions.
        if (ids.isNotEmpty()) scheduleOrganizeAfterEmbed()
    }

    /**
     * Accepts the AI-category suggestion for an unfiled bookmark: ensures the Space matching its
     * [Bookmark.category] exists and files the bookmark into it. Categories never organise the UI
     * directly — they only *suggest* a Space here.
     */
    fun acceptCategorySuggestion(bookmark: Bookmark) {
        val uid = _userId.value ?: return
        val category = bookmark.category?.takeIf { it.isNotBlank() } ?: return
        _spaceSuggestions.value = _spaceSuggestions.value - bookmark.id
        viewModelScope.launch {
            repository.ensureCategorySpace(uid, category)?.let { spaceId ->
                repository.assignToSpace(listOf(bookmark.id), spaceId)
                scheduleOrganizeAfterEmbed()
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
            if (rules.isActive) {
                val count = repository.applySpaceRules(space.id)
                if (rules.autoFile) repository.applyRulesToLibrary(uid)
                reportSpaceRulesResult(count, trimmed)
            }
            if (ids.isNotEmpty() || rules.isActive) scheduleOrganizeAfterEmbed()
        }
    }

    /**
     * Runs the embedding-driven auto-organiser: files high-confidence cards into their nearest Space,
     * spins up new Spaces from clusters, and stashes the medium-confidence remainder as per-card
     * suggestions. Silent unless [announce] is set (the manual "Embed All" flow reports the outcome).
     * Safe to call repeatedly — it only ever touches *unfiled* bookmarks.
     */
    fun organizeByEmbedding(announce: Boolean = false) {
        val uid = _userId.value ?: return
        viewModelScope.launch {
            val result = runCatching { repository.organizeByEmbedding(uid) }
                .getOrElse { e ->
                    if (e is kotlinx.coroutines.CancellationException) throw e
                    Log.e(TAG, "organizeByEmbedding failed", e)
                    return@launch
                }
            _spaceSuggestions.value = result.suggestions.associateBy { it.bookmarkId }
            if (announce) {
                result.announceMessage()?.let { msg ->
                    setTransientSyncState(SyncUiState.Success(msg))
                }
            }
        }
    }

    /** Files a suggested bookmark into its suggested Space and drops the now-consumed suggestion. */
    fun acceptSpaceSuggestion(bookmarkId: String) {
        val suggestion = _spaceSuggestions.value[bookmarkId] ?: return
        assignBookmarksToSpace(listOf(bookmarkId), suggestion.spaceId)
        _spaceSuggestions.value = _spaceSuggestions.value - bookmarkId
    }

    // ── Phase 12: Personal curation toggles ─────────────────────────────────

    fun toggleFavorite(bookmark: Bookmark) = curationController.toggleFavorite(bookmark)
    fun toggleSavedForLater(bookmark: Bookmark) = curationController.toggleSavedForLater(bookmark)
    /** Saves (or clears, when blank) the user's personal note on an entry. */
    fun updateNotes(bookmarkId: String, notes: String?) = curationController.updateNotes(bookmarkId, notes)

    // ── ChronosFlow handoff (productivity integration) ───────────────────────
    // Hands a bookmark to the companion ChronosFlow planner app via its interop provider. Each call
    // reports its outcome through [syncState] (the same channel sync messages use). Off the main
    // thread because ContentResolver.insert crosses an IPC boundary into ChronosFlow's process.

    /**
     * True when ChronosFlow is installed; gates the ChronosFlow actions in the card options sheet.
     * Resolved once and cached: the underlying check is a PackageManager IPC, and the feed asks per
     * card, so we avoid a main-thread binder call on every card. (Install state changing mid-session
     * is rare; it refreshes on next process start.)
     */
    private val chronosFlowInstalled: Boolean by lazy { chronosFlowBridge.isAvailable() }

    fun isChronosFlowInstalled(): Boolean = chronosFlowInstalled

    /**
     * "Remind me to read later" for [bookmark]. Curio now owns the reminder in-house: it schedules
     * its own local notification (via [reminderScheduler]) for the time implied by [choice], so the
     * reminder fires whether or not the companion ChronosFlow app is installed. When ChronosFlow IS
     * installed we also mirror the item into its reading list (best-effort) so it appears in the
     * user's planner — but that no longer gates the reminder or the confirmation.
     */
    fun remindToReadLaterInChronosFlow(bookmark: Bookmark, choice: ChronosReminderChoice) {
        val url = bookmark.url?.takeIf { it.isNotBlank() } ?: bookmark.text.takeIf { it.isNotBlank() }
        if (url == null) {
            setTransientSyncState(SyncUiState.Error("This bookmark has no link to read later."))
            return
        }
        val title = (bookmark.sourceTitle ?: bookmark.title)?.takeIf { it.isNotBlank() }
        val remindAt = choice.toEpochMillis()

        // Primary: Curio's own scheduled reminder notification.
        if (remindAt != null) {
            reminderScheduler.schedule(bookmark.id, title, url, remindAt)
        }

        // Optional mirror to ChronosFlow (only if installed). Best-effort; failures are ignored.
        if (chronosFlowInstalled) {
            viewModelScope.launch {
                withContext(Dispatchers.IO) {
                    chronosFlowBridge.sendToReadingList(
                        url = url, title = title,
                        reminderAtEpochMillis = remindAt, notes = bookmark.notes
                    )
                }
            }
        }

        setTransientSyncState(
            SyncUiState.Success(
                if (choice == ChronosReminderChoice.NONE) "Saved to read later"
                else "Curio will remind you ${choice.label.lowercase()}"
            )
        )
    }

    /** Drops [bookmark] into ChronosFlow's quick-capture inbox. */
    fun captureToChronosFlowInbox(bookmark: Bookmark) {
        val text = listOfNotNull(
            (bookmark.sourceTitle ?: bookmark.title)?.takeIf { it.isNotBlank() },
            bookmark.url?.takeIf { it.isNotBlank() } ?: bookmark.text
        ).distinct().joinToString("\n").ifBlank { bookmark.text }
        viewModelScope.launch {
            val result = withContext(Dispatchers.IO) { chronosFlowBridge.captureToInbox(text) }
            setTransientSyncState(result.fold(
                onSuccess = { SyncUiState.Success("Captured to ChronosFlow inbox") },
                onFailure = { SyncUiState.Error(chronosFlowError(it)) }
            ))
        }
    }

    /** Creates a follow-up task in ChronosFlow from [bookmark]. */
    fun createChronosFlowTask(bookmark: Bookmark) {
        val title = (bookmark.sourceTitle ?: bookmark.title)?.takeIf { it.isNotBlank() }
            ?: bookmark.text.take(80)
        viewModelScope.launch {
            val result = withContext(Dispatchers.IO) {
                chronosFlowBridge.createTask(
                    title = title,
                    notes = bookmark.summary ?: bookmark.notes,
                    url = bookmark.url?.takeIf { it.isNotBlank() }
                )
            }
            setTransientSyncState(result.fold(
                onSuccess = { SyncUiState.Success("Created a task in ChronosFlow") },
                onFailure = { SyncUiState.Error(chronosFlowError(it)) }
            ))
        }
    }

    private fun chronosFlowError(t: Throwable): String = when (t) {
        is SecurityException -> "ChronosFlow declined the item — check its handoff settings."
        else -> t.message ?: "Couldn't reach ChronosFlow."
    }

    /** Sets a transient ChronosFlow result on [_syncState] and clears it after [delayMs] so it
     *  doesn't masquerade as a persistent sync error in the feed banner. */
    private fun setTransientSyncState(state: SyncUiState, delayMs: Long = 4_000L) {
        _syncState.value = state
        viewModelScope.launch {
            delay(delayMs)
            if (_syncState.value === state) _syncState.value = SyncUiState.Idle
        }
    }

    // ── Weekly AI digest (delegated to DigestController) ─────────────────────
    private val digestController = DigestController(viewModelScope, aiAnalyzer, { rawBookmarks.value })
    val digestState: StateFlow<DigestUiState> = digestController.digestState
    fun generateWeeklyDigest() = digestController.generate()
    fun dismissDigest() = digestController.dismiss()

    init {
        // Mirror the digest lifecycle into the unified live activity: "Preparing your digest…" while
        // it generates, then a dismissible "Your weekly digest is ready" when it lands.
        viewModelScope.launch {
            digestController.digestState.collect { s ->
                when (s) {
                    is DigestUiState.Loading -> curioActivityController.taskStarted(CurioTask.DIGEST)
                    is DigestUiState.Ready -> {
                        curioActivityController.taskFinished(CurioTask.DIGEST)
                        curioActivityController.digestReady(s.itemCount)
                    }
                    else -> curioActivityController.taskFinished(CurioTask.DIGEST)
                }
            }
        }
    }

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

    fun dismissSyncBanner() {
        _syncState.value = SyncUiState.Idle
    }

    fun clearAnalysisError() {
        if (_analysisState.value is AnalysisUiState.Error) {
            _analysisState.value = AnalysisUiState.Idle
        }
    }

    // Initialise to false; the true value is loaded asynchronously in init{} so we never call
    // XaiKeyStore.isConfigured() synchronously at construction time — TokenStore may not have
    // finished loading its EncryptedSharedPreferences yet, which would return a stale false.
    private val _forceLocalNano = MutableStateFlow(true)
    val forceLocalNano: StateFlow<Boolean> = _forceLocalNano.asStateFlow()

    private val _xaiKeyConfigured = MutableStateFlow(false)
    /** Whether a usable xAI key is configured (drives the Settings key card). */
    val xaiKeyConfigured: StateFlow<Boolean> = _xaiKeyConfigured.asStateFlow()

    private val _xaiKeyStatus = MutableStateFlow<XaiKeyStatus>(XaiKeyStatus.Unknown)
    /**
     * Rich key state for the Settings card: tells the user whether a key is loaded (from encrypted
     * storage) or was just saved, and whether it is live (verified against xAI) — not merely present.
     */
    val xaiKeyStatus: StateFlow<XaiKeyStatus> = _xaiKeyStatus.asStateFlow()

    init {
        viewModelScope.launch {
            // Read the key from TokenStore directly rather than trusting XaiKeyStore: the
            // Application-level startup load runs on a separate IO coroutine and may not have
            // completed yet. Re-setting the runtime key here is idempotent and closes that race,
            // so the "key loaded" feedback below is never a stale false.
            val storedKey = runCatching { tokenStore.getXaiKey() }.getOrNull()
            if (!storedKey.isNullOrBlank()) com.example.data.XaiKeyStore.setRuntimeKey(storedKey)
            val configured = com.example.data.XaiKeyStore.isConfigured()
            _xaiKeyConfigured.value = configured
            _forceLocalNano.value = !configured
            if (configured) {
                verifyXaiKey(origin = XaiKeyOrigin.LOADED_FROM_STORAGE)
            } else {
                _xaiKeyStatus.value = XaiKeyStatus.NotSet
            }
        }
    }

    /** Re-evaluates whether a cloud key is available (call after the user saves/clears their key). */
    fun refreshKeyAvailability() {
        viewModelScope.launch {
            val configured = com.example.data.XaiKeyStore.isConfigured()
            _xaiKeyConfigured.value = configured
            _forceLocalNano.value = !configured
        }
    }

    /**
     * Persists a user-supplied xAI API key (encrypted) and activates it immediately. A blank value
     * clears it (reverting to the build-time key, if any). Lets users run AI features on their own
     * key instead of one baked into the APK.
     */
    fun saveXaiKey(key: String) {
        viewModelScope.launch {
            tokenStore.saveXaiKey(key.trim())
            com.example.data.XaiKeyStore.setRuntimeKey(key.trim())
            // Refresh both _xaiKeyConfigured and _forceLocalNano together.
            refreshKeyAvailability()
            if (com.example.data.XaiKeyStore.isConfigured()) {
                verifyXaiKey(origin = XaiKeyOrigin.JUST_SAVED)
            } else {
                _xaiKeyStatus.value = XaiKeyStatus.NotSet
            }
        }
    }

    /**
     * Probes the active key against xAI's key-introspection endpoint (no tokens consumed) and
     * publishes the result to [xaiKeyStatus]. [origin] is preserved through the check so the UI
     * can keep saying "loaded from storage" vs "just saved". Null origin = re-check in place
     * (retry button), keeping whatever origin is currently shown.
     */
    fun verifyXaiKey(origin: XaiKeyOrigin? = null) {
        val effectiveOrigin = origin
            ?: (xaiKeyStatus.value as? XaiKeyStatus.Present)?.origin
            ?: XaiKeyOrigin.LOADED_FROM_STORAGE
        viewModelScope.launch {
            if (!com.example.data.XaiKeyStore.isConfigured()) {
                _xaiKeyStatus.value = XaiKeyStatus.NotSet
                return@launch
            }
            _xaiKeyStatus.value = XaiKeyStatus.Present(effectiveOrigin, XaiKeyCheck.Checking)
            val check = when (val result = aiAnalyzer.verifyKey()) {
                is com.example.data.KeyVerification.Valid -> XaiKeyCheck.Live
                is com.example.data.KeyVerification.Invalid -> XaiKeyCheck.Invalid(result.reason)
                is com.example.data.KeyVerification.Unreachable -> XaiKeyCheck.Unreachable
            }
            _xaiKeyStatus.value = XaiKeyStatus.Present(effectiveOrigin, check)
        }
    }

    /** X display name of the signed-in account (Settings account card). */
    val accountName: StateFlow<String?> =
        tokenStore.nameFlow.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    /** X handle (without @) of the signed-in account. */
    val accountUsername: StateFlow<String?> =
        tokenStore.usernameFlow.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    /** X profile photo URL ("_normal" 48×48 variant); the UI upgrades it for display. */
    val accountAvatarUrl: StateFlow<String?> =
        tokenStore.profileImageUrlFlow.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    private val _xClientIdStatus = MutableStateFlow(XClientIdStatus.BUILT_IN)
    /**
     * Whether X bookmark sync is using the built-in OAuth client ID or one the user supplied
     * (BYOK), and — when custom — whether it was just saved or loaded from storage.
     */
    val xClientIdStatus: StateFlow<XClientIdStatus> = _xClientIdStatus.asStateFlow()

    init {
        viewModelScope.launch {
            val custom = runCatching { tokenStore.getXClientId() }.getOrNull()
            if (!custom.isNullOrBlank()) _xClientIdStatus.value = XClientIdStatus.CUSTOM_LOADED
        }
    }

    /**
     * Persists a user-supplied X OAuth client ID (BYOK for bookmark sync); blank clears it and
     * reverts to the built-in ID. Existing tokens were minted for the OLD client, so the user must
     * sign out and back in afterwards — the Settings card says so.
     */
    fun saveXClientId(clientId: String) {
        viewModelScope.launch {
            tokenStore.saveXClientId(clientId.trim())
            _xClientIdStatus.value =
                if (clientId.isBlank()) XClientIdStatus.BUILT_IN else XClientIdStatus.CUSTOM_SAVED
        }
    }

    /**
     * Whether on-device AI agents / assistants may invoke Curio's *write* AppFunctions (add
     * bookmark, add note, toggle favourite). Surfaced as a Settings toggle; the function-side gate
     * reads [com.example.data.remote.TokenStore.isAgentWritesAllowed]. Defaults to true.
     */
    val allowAgentWrites: StateFlow<Boolean> =
        tokenStore.allowAgentWritesFlow.stateIn(viewModelScope, SharingStarted.Eagerly, true)

    fun setAllowAgentWrites(allowed: Boolean) {
        viewModelScope.launch { tokenStore.setAgentWritesAllowed(allowed) }
    }

    private var rateLimitTimer: CountDownTimer? = null

    /**
     * Text/URL shared into Curio from another app before the user was signed in. Held here and
     * flushed by [setUserId] once a user id is available (e.g. a share that cold-starts the app).
     */
    private var pendingSharedCapture: String? = null
    /** Debounced organise pass after incremental embedding so a single analysed card can auto-file. */
    private var organizeAfterEmbedJob: kotlinx.coroutines.Job? = null
    /** Debounced foreground refresh — picks up suggestions after background embedding/indexing. */
    private var foregroundOrganizeJob: kotlinx.coroutines.Job? = null

    /**
     * Refreshes embedding suggestions after returning to the app. Background indexing auto-files
     * and discovers clusters in the DB but only the ViewModel holds medium-confidence suggestions.
     */
    fun refreshSuggestionsOnForeground() {
        if (_userId.value == null) return
        foregroundOrganizeJob?.cancel()
        foregroundOrganizeJob = viewModelScope.launch {
            delay(300)
            organizeByEmbedding(announce = false)
        }
    }

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
                .onFailure { e ->
                    if (e is kotlinx.coroutines.CancellationException) throw e
                    Log.e(TAG, "applyRulesToLibrary failed", e)
                }
            runCatching { repository.backfillCategorySpaces(userId) }
                .onFailure { e ->
                    if (e is kotlinx.coroutines.CancellationException) throw e
                    Log.e(TAG, "backfillCategorySpaces failed", e)
                }
            // Finally, embedding-driven organisation for anything the rules/categories didn't file:
            // auto-files semantic matches, discovers new clusters, and stages suggestions. Silent on
            // login (no toast) — it only refines what the deterministic passes above left unfiled.
            organizeByEmbedding(announce = false)
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
            _syncState.value = SyncUiState.Loading()
            curioActivityController.taskStarted(CurioTask.SYNC)
            repository.syncBookmarks(uid, fetchNextPage)
                .onSuccess {
                    // Transient: a sticky Success outranked every lower status slot and kept
                    // global AI-error banners suppressed indefinitely after any sync.
                    setTransientSyncState(SyncUiState.Success("Synchronized successfully"))
                    resolveNewSources()
                    scheduleOrganizeAfterEmbed()
                }
                .onFailure { exception ->
                    if (exception is RateLimitException) startRateLimitCountDown(exception.resetTimeSeconds.toInt())
                    else {
                        val message = humanReadableError(exception, ErrorContext.SYNC)
                        _syncState.value = SyncUiState.Error(message)
                        curioActivityController.syncError(message)
                    }
                }
            curioActivityController.taskFinished(CurioTask.SYNC)
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
            try {
                repository.updateOcrContent(bookmarkId, ocrText = null, isOcrScheduled = true)
                val text = ocrAnalyzer.analyze(bitmap)
                repository.updateOcrContent(bookmarkId, ocrText = text, isOcrScheduled = false)
                _analysisState.value = AnalysisUiState.Success(bookmarkId)
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                Log.e(TAG, "OCR processing failed for bookmark $bookmarkId", e)
                _analysisState.value = AnalysisUiState.Error(humanReadableError(e, ErrorContext.AI), bookmarkId)
            } finally {
                // Only clear Processing on cancellation; leave Error intact so the UI can show it.
                if (_analysisState.value is AnalysisUiState.Processing) {
                    _analysisState.value = AnalysisUiState.Idle
                }
            }
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
                if (uid != null && bookmark.spaceId.isNullOrBlank()) {
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
                if (e is kotlinx.coroutines.CancellationException) throw e
                _analysisState.value = AnalysisUiState.Error(humanReadableError(e, ErrorContext.AI), bookmark.id)
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
                if (e is kotlinx.coroutines.CancellationException) throw e
                _analysisState.value = AnalysisUiState.Error(humanReadableError(e, ErrorContext.AI), bookmark.id)
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
                if (e is kotlinx.coroutines.CancellationException) throw e
                _analysisState.value = AnalysisUiState.Error(humanReadableError(e, ErrorContext.SOURCE), bookmark.id)
            }
        }
    }

    fun resolveNewSources() {
        viewModelScope.launch {
            val unresolved = rawBookmarks.value.filter { it.sourceType == null && it.url != null }
            val batch = unresolved.take(10)
            if (batch.isEmpty()) {
                setTransientSyncState(SyncUiState.Success("No unresolved sources — nothing to fetch"))
                return@launch
            }
            var resolved = 0
            var failed = 0
            batch.forEachIndexed { index, bookmark ->
                // Live progress so the user can see the batch working (arXiv/GitHub/HF lookups are
                // network-bound and can take a few seconds each).
                _syncState.value = SyncUiState.Loading("Resolving sources… ${index + 1}/${batch.size}")
                try {
                    val info = withContext(Dispatchers.IO) {
                        sourceResolver.resolve(bookmark.text, bookmark.url)
                    }
                    if (info != null) {
                        repository.updateSourceInfo(
                            id = bookmark.id, sourceType = info.sourceType, sourceId = info.sourceId,
                            sourceTitle = info.sourceTitle, sourceAuthors = info.sourceAuthors,
                            sourceAbstract = info.sourceAbstract, sourceExtra = info.sourceExtra
                        )
                        resolved++
                    } else {
                        failed++
                    }
                } catch (e: Exception) {
                    if (e is kotlinx.coroutines.CancellationException) throw e
                    // Per-bookmark resolution failures are non-fatal — one bad URL shouldn't
                    // abort the batch — but log so a systemic failure (bad key, no network)
                    // is diagnosable instead of vanishing.
                    failed++
                    Log.w(TAG, "Source resolution failed for ${bookmark.id}", e)
                }
            }
            setTransientSyncState(
                SyncUiState.Success(
                    "Resolved $resolved of ${batch.size} sources" + if (failed > 0) " ($failed unresolved)" else ""
                )
            )
        }
    }

    fun deduplicateBySource() {
        val uid = _userId.value ?: return
        viewModelScope.launch {
            try {
                _syncState.value = SyncUiState.Loading("Deduplicating sources…")
                val removed = repository.deduplicateBySource(uid)
                setTransientSyncState(
                    SyncUiState.Success(
                        if (removed > 0) "Merged $removed duplicate${if (removed == 1) "" else "s"}"
                        else "No duplicates found"
                    )
                )
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                _syncState.value = SyncUiState.Error("Dedup failed: ${e.localizedMessage}")
            }
        }
    }

    // ── Phase 10: Semantic search ───────────────────────────────────────────

    private fun generateEmbeddingForBookmark(bookmarkId: String) {
        viewModelScope.launch {
            try {
                val bookmark = rawBookmarks.value.find { it.id == bookmarkId } ?: return@launch
                val embedding = embeddingService.embedDocument(bookmark) ?: return@launch
                repository.updateEmbedding(bookmarkId, embedding.toByteArray())
                scheduleOrganizeAfterEmbed()
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                Log.w(TAG, "Embedding generation failed for $bookmarkId", e)
            }
        }
    }

    /** Drops suggestions for deleted/filed bookmarks or Spaces that no longer exist. */
    private fun pruneStaleSuggestions(bookmarks: List<Bookmark>, validSpaceIds: Set<String>) {
        val byId = bookmarks.associateBy { it.id }
        val pruned = _spaceSuggestions.value.filterKeys { id ->
            val b = byId[id]
            b != null && b.spaceId.isNullOrBlank()
        }.filterValues { it.spaceId in validSpaceIds }
        if (pruned != _spaceSuggestions.value) _spaceSuggestions.value = pruned
    }

    /** Coalesce rapid per-card embeds into one organise pass (500 ms debounce). */
    private fun scheduleOrganizeAfterEmbed() {
        organizeAfterEmbedJob?.cancel()
        organizeAfterEmbedJob = viewModelScope.launch {
            delay(500)
            organizeByEmbedding(announce = false)
        }
    }

    fun embedAllBookmarks() {
        viewModelScope.launch {
            val uid = _userId.value ?: run {
                _syncState.value = SyncUiState.Error("Sign in to embed bookmarks")
                return@launch
            }
            // Embed *every* bookmark that still lacks a vector, analyzed or not — the button is
            // "Embed All Bookmarks". The old path filtered to isAnalyzed and capped at 50, so a
            // library with few analyzed items (or more than 50) was only partially embedded and
            // never made progress on the rest. This pulls the full unembedded work list from the DB
            // (which already excludes items that have a vector), so re-runs only do outstanding work.
            val batch = repository.getAllUnembedded(uid)
            if (batch.isEmpty()) {
                setTransientSyncState(SyncUiState.Success("Nothing to embed — all bookmarks already have vectors"))
                return@launch
            }
            val engine = if (embeddingService.isOnDevice()) "on-device" else "xAI"
            var succeeded = 0
            var failed = 0
            batch.forEachIndexed { index, bookmark ->
                // Live progress: each embed is a model inference (on-device) or an xAI API round-trip,
                // so a 50-item batch is slow enough that the user needs to see it advancing.
                _syncState.value = SyncUiState.Loading(
                    "Embedding ($engine)… ${index + 1}/${batch.size}"
                )
                try {
                    val embedding = withContext(Dispatchers.IO) {
                        embeddingService.embedDocument(bookmark)
                    } ?: run { failed++; return@forEachIndexed }
                    repository.updateEmbedding(bookmark.id, embedding.toByteArray())
                    succeeded++
                } catch (e: Exception) {
                    if (e is kotlinx.coroutines.CancellationException) throw e
                    failed++
                    Log.w(TAG, "Embedding generation failed for ${bookmark.id}", e)
                }
            }
            // Report the real outcome: if every item failed, the previous code still claimed
            // success, hiding a broken embedding provider from the user. Prefer the provider's
            // specific reason (e.g. xAI 404 / no model provisioned) over a generic message.
            if (succeeded == 0 && failed > 0) {
                _syncState.value =
                    SyncUiState.Error(embeddingService.lastError ?: "Embedding unavailable — generated 0 of $failed items")
            } else {
                _syncState.value =
                    SyncUiState.Success("Embeddings generated for $succeeded items" + if (failed > 0) " ($failed skipped)" else "")
                // Fresh vectors → immediately auto-organise so the user sees cards flow into Spaces
                // right after embedding (the whole point of embedding, from their perspective).
                if (succeeded > 0) organizeByEmbedding(announce = true)
            }
        }
    }

    // ── Citation export (BibTeX / RIS / CSL-JSON / Markdown) ─────────────────

    fun exportBibtex(bookmarks: List<Bookmark>): String =
        BibtexExporter.toBibtexList(bookmarks)

    fun exportSingleBibtex(bookmark: Bookmark): String? =
        BibtexExporter.toBibtex(bookmark)

    fun exportRis(bookmarks: List<Bookmark>): String =
        BibtexExporter.toRisList(bookmarks)

    fun exportCslJson(bookmarks: List<Bookmark>): String =
        BibtexExporter.toCslJsonList(bookmarks)

    fun exportMarkdown(bookmarks: List<Bookmark>): String =
        BibtexExporter.toMarkdownList(bookmarks)

    // ── Existing operations ─────────────────────────────────────────────────

    fun deleteBookmarks(ids: List<String>) {
        if (ids.isNotEmpty()) {
            _spaceSuggestions.value = _spaceSuggestions.value - ids.toSet()
        }
        curationController.delete(ids)
    }

    /** Re-inserts bookmarks removed by [deleteBookmarks] — backs the feed's Undo snackbar action. */
    fun restoreBookmarks(bookmarks: List<Bookmark>) {
        if (bookmarks.isEmpty()) return
        viewModelScope.launch { repository.restoreBookmarks(bookmarks) }
    }
    fun updateCategoryForBookmarks(ids: List<String>, category: String) {
        if (ids.isNotEmpty()) {
            _spaceSuggestions.value = _spaceSuggestions.value - ids.toSet()
            scheduleOrganizeAfterEmbed()
        }
        curationController.updateCategory(ids, category)
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
                // Single @Transaction call: both UPDATEs are atomic — no TOCTOU window.
                repository.swapCreatedAt(bookmark.id, bookmark.createdAt, upper.id, upper.createdAt)
            }
        }
    }

    fun moveBookmarkDown(bookmark: Bookmark) {
        viewModelScope.launch {
            val list = rawBookmarks.value
            val index = list.indexOfFirst { it.id == bookmark.id }
            if (index != -1 && index < list.size - 1) {
                val lower = list[index + 1]
                // Single @Transaction call: both UPDATEs are atomic — no TOCTOU window.
                repository.swapCreatedAt(bookmark.id, bookmark.createdAt, lower.id, lower.createdAt)
            }
        }
    }

    fun getInstantSummaryPreview(text: String, onCompleted: (String) -> Unit) {
        viewModelScope.launch {
            try {
                val result = textGenerator.analyze(text, null, null, forceLocal = false)
                onCompleted("✨ Category: ${result.category}\n🏷️ Tags: ${result.tags.joinToString(", ")}\n📝 Summary: ${result.summary}")
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                onCompleted("❌ Analysis failed: ${e.localizedMessage ?: "Unknown error"}. Add your xAI API key in Settings.")
            }
        }
    }

    // ── Chat with RAG + Live Search grounding (delegated to ChatController) ──────
    // Chat state was extracted into ChatController to shrink this god class. The VM keeps the same
    // public API (facade) so the chat UI is unchanged; the controller reads live library/user state
    // through the suppliers below.
    private val chatController = ChatController(
        scope = viewModelScope,
        aiAnalyzer = aiAnalyzer,
        embeddingService = embeddingService,
        repository = repository,
        semanticLayer = semanticLayer,
        rawBookmarks = { rawBookmarks.value },
        currentUserId = { _userId.value }
    )
    val chatMessages: StateFlow<List<ChatMessage>> = chatController.chatMessages
    val isChatLoading: StateFlow<Boolean> = chatController.isChatLoading
    val chatSources: StateFlow<Set<ChatSource>> = chatController.chatSources

    fun toggleChatSource(source: ChatSource) = chatController.toggleSource(source)
    fun clearChat() = chatController.clear()
    fun sendChatMessage(textInput: String) = chatController.send(textInput)
    fun retryChatMessage(failedMessageId: String) = chatController.retryMessage(failedMessageId)
    fun submitSemanticFeedback(messageId: String, accepted: Boolean) =
        chatController.submitSemanticFeedback(messageId, accepted)

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
            try {
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
            } catch (e: Exception) {
                if (e is kotlinx.coroutines.CancellationException) throw e
                android.util.Log.e(TAG, "Image generation failed for $bookmarkId", e)
                _imagenGeneratedIds.value = _imagenGeneratedIds.value + bookmarkId
                _analysisState.value = AnalysisUiState.Idle
            } finally {
                if (_analysisState.value is AnalysisUiState.Processing) {
                    _analysisState.value = AnalysisUiState.Idle
                }
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        rateLimitTimer?.cancel()
        searchController.close()
    }

    companion object {
        private const val TAG = "BookmarkViewModel"
        private const val REDISCOVER_MIN_AGE_MS = 14L * 24 * 60 * 60 * 1000 // only resurface 2-week-old saves
        private const val REDISCOVER_BATCH = 3                              // picks shown at once
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
    val groundedIn: List<ChatSource> = emptyList(),
    /** True when the AI turn failed — renders as an error bubble with retry. */
    val isError: Boolean = false,
    /** Original user prompt to re-send on retry (only set for error bubbles). */
    val retryPrompt: String? = null,
    /** Semantic sidecar cache entry id (enables thumbs up/down feedback). */
    val semanticCacheEntryId: String? = null,
    /** Cache lookup similarity when the sidecar served this reply. */
    val semanticSimilarity: Float? = null,
    /** True when the sidecar returned a cache hit for this reply. */
    val semanticCacheHit: Boolean = false,
    /** Sidecar model tier (`cached`, `fast`, `standard`, …). */
    val semanticModelTier: String? = null,
    /** User feedback on sidecar quality; null = not yet submitted. */
    val semanticFeedbackAccepted: Boolean? = null
) {
    val showsSemanticFeedback: Boolean
        get() = semanticCacheEntryId != null && semanticFeedbackAccepted == null
}

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
