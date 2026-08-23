import Foundation
import Combine
import Observation
import os
#if canImport(UIKit)
import UIKit
#endif

// ============================================================================
// Feed/UI enums + sealed UI-state types + value types owned by the VM surface.
//
// `SearchMode`, `QuickFilter`, `ChatMessage`, `ChatSender`, `ChatSource`, and
// `DigestUiState` are defined ONCE in their owning controllers (SearchController,
// ChatController, DigestController) — DESIGN slots them onto the VM surface but the
// controllers are their natural home, and they are NOT redefined here. The VM facades
// the controllers so the UI is unchanged.
// ============================================================================

/// User-selectable theme. Port of `enum class AppThemeSetting { SYSTEM, LIGHT, DARK }`.
enum AppThemeSetting: String, CaseIterable, Sendable, Hashable {
    case system = "SYSTEM"
    case light = "LIGHT"
    case dark = "DARK"
}

/// State of the X bookmarks sync. Port of `sealed interface SyncUiState`.
/// User-facing strings are produced by the VM and surfaced verbatim (CONVENTIONS §4).
enum SyncUiState: Sendable, Equatable {
    case idle
    /// A long-running operation is in flight, with an optional live progress note (e.g.
    /// "Embedding 12/50…"). Port of Android `SyncUiState.Loading(message: String?)`.
    case loading(String?)
    /// Success carrying the toast message.
    case success(String)
    /// Error carrying the user-facing message.
    case error(String)
    /// X is rate-limited; `secondsLeft` counts down to resume.
    case rateLimited(secondsLeft: Int)
}

/// State of a single per-bookmark analysis/OCR/source/image pipeline run. Port of
/// `sealed interface AnalysisUiState`.
enum AnalysisUiState: Sendable, Equatable {
    case idle
    case processing(bookmarkId: String)
    case success(bookmarkId: String)
    case error(message: String, bookmarkId: String? = nil)
}

/// Aggregated library statistics for the Insights dashboard. Port of `data class CurioStats`.
/// `topTags` mirrors the Kotlin `List<Pair<String, Int>>` (tag, count) ordering.
struct CurioStats: Sendable, Equatable {
    let totalCount: Int
    let curatedCount: Int
    let ocrCount: Int
    let categoryCounts: [String: Int]
    let topTags: [(String, Int)]
    let sourceCount: Int
    let deepAnalyzedCount: Int
    let favoriteCount: Int
    let readLaterCount: Int

    init(
        totalCount: Int = 0,
        curatedCount: Int = 0,
        ocrCount: Int = 0,
        categoryCounts: [String: Int] = [:],
        topTags: [(String, Int)] = [],
        sourceCount: Int = 0,
        deepAnalyzedCount: Int = 0,
        favoriteCount: Int = 0,
        readLaterCount: Int = 0
    ) {
        self.totalCount = totalCount
        self.curatedCount = curatedCount
        self.ocrCount = ocrCount
        self.categoryCounts = categoryCounts
        self.topTags = topTags
        self.sourceCount = sourceCount
        self.deepAnalyzedCount = deepAnalyzedCount
        self.favoriteCount = favoriteCount
        self.readLaterCount = readLaterCount
    }

    // `[(String, Int)]` is not `Equatable` synthesised; provide an explicit comparison so the
    // `@Observable` diffing / tests can compare two stats values.
    static func == (lhs: CurioStats, rhs: CurioStats) -> Bool {
        lhs.totalCount == rhs.totalCount &&
        lhs.curatedCount == rhs.curatedCount &&
        lhs.ocrCount == rhs.ocrCount &&
        lhs.categoryCounts == rhs.categoryCounts &&
        lhs.topTags.count == rhs.topTags.count &&
        zip(lhs.topTags, rhs.topTags).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 } &&
        lhs.sourceCount == rhs.sourceCount &&
        lhs.deepAnalyzedCount == rhs.deepAnalyzedCount &&
        lhs.favoriteCount == rhs.favoriteCount &&
        lhs.readLaterCount == rhs.readLaterCount
    }
}

// ============================================================================
// BookmarkViewModel
// ============================================================================

/// Central `@MainActor @Observable` view model. Direct port of `class BookmarkViewModel : ViewModel`
/// in `ui/BookmarkViewModel.kt`.
///
/// CONVENTIONS mapping:
/// - §4: `@MainActor @Observable final class` (Observation replaces `MutableStateFlow`/`StateFlow`;
///   plain stored `var`s are auto-tracked). Derived flows (`bookmarks`, `spaces`, `stats`,
///   `rediscoverPicks`) become **computed properties** recomputed from the source arrays + the
///   search controller's input state — the 5-input feed filter is ported verbatim.
/// - §4 "Eager source stream": `rawBookmarks` (Kotlin `SharingStarted.Eagerly`) is a stored property
///   continuously fed by a Combine subscription started in `init` and kept alive for the VM lifetime,
///   so background jobs (`embedAllBookmarks`, `resolveNewSources`, …) read it with no view subscriber.
/// - §4 "Async pattern": every `viewModelScope.launch` → `Task { … }` on the main actor; heavy work
///   runs in actor-isolated services and results are assigned back on the main actor.
/// - §4 "Cancellation": the ubiquitous Kotlin `if (e is CancellationException) throw e` collapses to
///   cooperative `Task` cancellation + `catch is CancellationError { throw … }`; never swallowed.
/// - §4 "Countdown": the rate-limit `CountDownTimer` → a cancellable `Task` loop with
///   `Task.sleep(for: .seconds(1))`; cancelled in `close()`.
///
/// The Kotlin god-class delegated search/chat/curation/digest into four controllers; those are
/// already ported (SearchController/ChatController/CurationController/DigestController). The VM
/// constructs them with suppliers reading its live state and facades their public API verbatim.
@MainActor
@Observable
final class BookmarkViewModel {

    // MARK: - Injected dependencies (CONVENTIONS §2 constructor injection)

    @ObservationIgnored private let repository: BookmarkRepository
    @ObservationIgnored private let ocrAnalyzer: OcrAnalyzer
    @ObservationIgnored private let aiAnalyzer: XAiAnalyzer
    @ObservationIgnored private let embeddingService: EmbeddingProvider
    @ObservationIgnored private let sourceResolver: SourceResolver
    @ObservationIgnored private let textGenerator: TextGeneratorSelector
    @ObservationIgnored private let grokImageService: GrokImageService
    @ObservationIgnored private let embeddingModelManager: EmbeddingModelManager
    @ObservationIgnored private let tokenStore: TokenStore
    @ObservationIgnored private let chronosFlowBridge: ChronosFlowBridge
    @ObservationIgnored private let liveActivityManager: LiveActivityManager
    @ObservationIgnored private let reminderScheduler: ReminderScheduler
    @ObservationIgnored private let semanticLayer: OnDeviceSemanticLayer
    /// Synchronous resolver for the runtime xAI key. The Kotlin VM called `XaiKeyStore.isConfigured()`
    /// on the global `object`; here it is a trivial `struct` wrapping the same process-global slot.
    @ObservationIgnored private let xaiKeyStore = XaiKeyStore()

    @ObservationIgnored private static let logger = Logger(subsystem: "com.curio.app", category: "BookmarkViewModel")

    // MARK: - Constants (Kotlin `companion object`)

    /// Only resurface ~2-week-old saves. Port of `REDISCOVER_MIN_AGE_MS = 14L * 24 * 60 * 60 * 1000`.
    @ObservationIgnored private static let rediscoverMinAgeMs: Int64 = 14 * 24 * 60 * 60 * 1000
    /// Rediscovery picks shown at once. Port of `REDISCOVER_BATCH = 3`.
    @ObservationIgnored private static let rediscoverBatch = 3

    // MARK: - Embedding model state (Settings card)

    /// Download state of the on-device EmbeddingGemma model. The Kotlin VM aliased
    /// `embeddingModelManager.state` (a `StateFlow`); here the manager is itself `@MainActor
    /// @Observable`, so reading its `state` through this computed property keeps the Settings card
    /// reactive without duplicating the value. Port of `val embeddingModelState = …state`.
    var embeddingModelState: EmbeddingModelManager.ModelState { embeddingModelManager.state }

    /// Whether the on-device semantic layer (cache + compression + routing) is enabled.
    private(set) var semanticLayerEnabled: Bool = SemanticPreference.isEnabled()

    func setSemanticLayerEnabled(_ enabled: Bool) {
        semanticLayer.setEnabled(enabled)
        semanticLayerEnabled = enabled
    }

    // MARK: - Identity

    /// Backing for `userId`. Mutated only through `setUserId`. Port of `_userId`/`userId`.
    private(set) var userId: String? = nil

    // MARK: - Eager source stream (Kotlin `rawBookmarks` / `SharingStarted.Eagerly`)

    /// The full, unfiltered library for the current user, fed eagerly by a Combine subscription so
    /// background jobs read it even with no UI subscriber. Re-emits on every repository write.
    private(set) var rawBookmarks: [Bookmark] = []

    /// Subscription to the current user's bookmarks publisher. Re-subscribed on every `setUserId`.
    @ObservationIgnored private var rawBookmarksCancellable: AnyCancellable?
    /// Subscription to the current user's Spaces publisher.
    @ObservationIgnored private var spacesCancellable: AnyCancellable?

    /// Live Spaces for the current user (without counts). Fed by `getSpacesFlow`. The membership
    /// counts are folded in by the `spaces` computed property (it reads `rawBookmarks`), mirroring
    /// the Kotlin `combine(getSpacesFlow, rawBookmarks)`.
    private(set) var rawSpaces: [Space] = []

    /// Embedding-derived Space suggestions for unfiled cards (medium-confidence matches).
    private(set) var spaceSuggestions: [String: SpaceSuggestion] = [:]

    @ObservationIgnored private var organizeAfterEmbedTask: Task<Void, Never>?
    @ObservationIgnored private var foregroundOrganizeTask: Task<Void, Never>?

    // Controllers that read the VM's live state capture `self` through `@MainActor` suppliers, so they
    // are `lazy` — the closures can only be formed once `self` is fully initialized. Their inits are
    // pure assignments (no eager side effects), so deferring construction to first access is
    // behaviourally identical to eager construction.
    @ObservationIgnored private lazy var searchController = SearchController(
        embeddingService: embeddingService,
        repository: repository,
        rawBookmarks: { [weak self] in self?.rawBookmarks ?? [] },
        currentUserId: { [weak self] in self?.userId }
    )
    @ObservationIgnored private let curationController: CurationController
    @ObservationIgnored private lazy var digestController = DigestController(
        aiAnalyzer: aiAnalyzer,
        rawBookmarks: { [weak self] in self?.rawBookmarks ?? [] },
        liveActivityManager: liveActivityManager
    )
    @ObservationIgnored private lazy var chatController = ChatController(
        aiAnalyzer: aiAnalyzer,
        embeddingService: embeddingService,
        repository: repository,
        semanticLayer: semanticLayer,
        rawBookmarks: { [weak self] in self?.rawBookmarks ?? [] },
        currentUserId: { [weak self] in self?.userId }
    )

    // MARK: - Search/filter facades (read the controller's published input state)

    var searchQuery: String { searchController.searchQuery }
    var searchMode: SearchMode { searchController.searchMode }
    var semanticResults: [Bookmark] { searchController.semanticResults }
    var isSemanticLoading: Bool { searchController.isSemanticLoading }
    var selectedCategory: String? { searchController.selectedCategory }
    var selectedTag: String? { searchController.selectedTag }
    var quickFilter: QuickFilter { searchController.quickFilter }
    /// When non-nil, the feed is scoped to bookmarks filed in this Space.
    var selectedSpaceId: String? { searchController.selectedSpaceId }

    func setQuickFilter(_ filter: QuickFilter) { searchController.setQuickFilter(filter) }
    func setLibraryFilter(_ filter: LibraryFilter) { searchController.setLibraryFilter(filter) }
    func selectSpace(_ spaceId: String?) { searchController.selectSpace(spaceId) }
    func updateSearchQuery(_ query: String) { searchController.updateQuery(query) }
    func setSearchMode(_ mode: SearchMode) { searchController.setMode(mode) }
    func selectCategory(_ category: String?) { searchController.selectCategory(category) }
    func selectTag(_ tag: String?) { searchController.selectTag(tag) }
    func clearAllFilters() { searchController.clearAll() }

    // MARK: - Theme

    private(set) var themeSetting: AppThemeSetting = .dark

    func setThemeSetting(_ setting: AppThemeSetting) { themeSetting = setting }

    // MARK: - Sync / analysis / key state

    private(set) var syncState: SyncUiState = .idle
    private(set) var analysisState: AnalysisUiState = .idle

    func dismissSyncBanner() {
        syncState = .idle
    }

    func clearAnalysisError() {
        if case .error = analysisState {
            analysisState = .idle
        }
    }

    var curationError: AsyncStream<String> {
        curationController.curationError
    }

    /// Initialised to `true`; the real value is loaded asynchronously in `init` so we never call
    /// `XaiKeyStore.isConfigured()` synchronously at construction time — `TokenStore` may not have
    /// finished loading yet, which would return a stale `false`. Port of `_forceLocalNano`.
    private(set) var forceLocalNano: Bool = true

    /// Whether a usable xAI key is configured (drives the Settings key card). Port of `_xaiKeyConfigured`.
    private(set) var xaiKeyConfigured: Bool = false

    /// Whether on-device AI agents / assistants may invoke Curio's *write* App Intents (add
    /// bookmark, add note, toggle favourite). Surfaced as a Settings toggle; the intent-side gate
    /// reads `TokenStore.isAgentWritesAllowed`. Defaults to true. Port of `allowAgentWrites`.
    private(set) var allowAgentWrites: Bool = true

    func setAllowAgentWrites(_ allowed: Bool) {
        allowAgentWrites = allowed
        launch { [weak self] in
            await self?.tokenStore.setAgentWritesAllowed(allowed)
        }
    }

    /// True when ChronosFlow is installed; gates the ChronosFlow actions in the card options sheet.
    /// Resolved once at construction and cached (see `init`). Port of `chronosFlowInstalled`.
    private(set) var chronosFlowInstalled: Bool = false

    func isChronosFlowInstalled() -> Bool { chronosFlowInstalled }

    // MARK: - Chat facades

    var chatMessages: [ChatMessage] { chatController.chatMessages }
    var isChatLoading: Bool { chatController.isChatLoading }
    var chatSources: OrderedChatSourceSet { chatController.chatSources }

    func toggleChatSource(_ source: ChatSource) { chatController.toggleSource(source) }
    func clearChat() { chatController.clear() }
    func sendChatMessage(_ textInput: String) { chatController.send(textInput) }
    func retryChatMessage(_ failedMessageId: String) { chatController.retryMessage(failedMessageId) }
    func submitSemanticFeedback(messageId: String, accepted: Bool) {
        chatController.submitSemanticFeedback(messageId: messageId, accepted: accepted)
    }

    // MARK: - Digest facades

    var digestState: DigestUiState { digestController.digestState }
    func generateWeeklyDigest() { digestController.generate() }
    func dismissDigest() { digestController.dismiss() }

    // MARK: - Imagen (Grok image generation)

    /// Bookmark ids whose cover image has been generated (or the procedural fallback chosen).
    private(set) var imagenGeneratedIds: Set<String> = []
    /// Bookmark id → Grok-generated cover image URL (empty when the procedural fallback is used).
    private(set) var imagenUrls: [String: String] = [:]

    // MARK: - Rediscover

    /// Rotating offset into the oldest-first rediscovery candidates. Port of `_rediscoverOffset`.
    private(set) var rediscoverOffset: Int = 0

    // MARK: - Rate-limit countdown + share capture

    /// The in-flight rate-limit countdown loop; cancelled before a new countdown and in `close()`.
    /// Replaces the Android `CountDownTimer`.
    @ObservationIgnored private var rateLimitTask: Task<Void, Never>?

    /// Text/URL shared into Curio before the user signed in. Held here and flushed by `setUserId`
    /// once a user id is available (e.g. a share that cold-starts the app). Port of `pendingSharedCapture`.
    @ObservationIgnored private var pendingSharedCapture: String?

    // MARK: - Init

    init(
        repository: BookmarkRepository,
        ocrAnalyzer: OcrAnalyzer,
        aiAnalyzer: XAiAnalyzer,
        embeddingService: EmbeddingProvider,
        sourceResolver: SourceResolver,
        textGenerator: TextGeneratorSelector,
        grokImageService: GrokImageService,
        embeddingModelManager: EmbeddingModelManager,
        tokenStore: TokenStore,
        chronosFlowBridge: ChronosFlowBridge,
        liveActivityManager: LiveActivityManager,
        reminderScheduler: ReminderScheduler,
        semanticLayer: OnDeviceSemanticLayer
    ) {
        self.repository = repository
        self.ocrAnalyzer = ocrAnalyzer
        self.aiAnalyzer = aiAnalyzer
        self.embeddingService = embeddingService
        self.sourceResolver = sourceResolver
        self.textGenerator = textGenerator
        self.grokImageService = grokImageService
        self.embeddingModelManager = embeddingModelManager
        self.tokenStore = tokenStore
        self.chronosFlowBridge = chronosFlowBridge
        self.liveActivityManager = liveActivityManager
        self.reminderScheduler = reminderScheduler
        self.semanticLayer = semanticLayer

        // `searchController` / `digestController` / `chatController` are `lazy` (they capture `self`
        // through main-actor suppliers and so can only be built post-init). `curationController` takes
        // no supplier, so it is constructed eagerly here.
        self.curationController = CurationController(repository: repository)

        // Load the real xAI-key gate asynchronously (see `forceLocalNano` doc). Port of the Kotlin
        // `init { viewModelScope.launch { … } }`.
        launch { [weak self] in
            guard let self else { return }
            let configured = self.xaiKeyStore.isConfigured()
            self.xaiKeyConfigured = configured
            self.forceLocalNano = !configured
        }

        // Load the persisted agent-write permission (Android `stateIn(Eagerly, initial = true)`).
        launch { [weak self] in
            guard let self else { return }
            self.allowAgentWrites = await self.tokenStore.isAgentWritesAllowed()
        }

        // Resolved once and cached (mirrors the Android `by lazy` — install state changing
        // mid-session is rare; it refreshes on next launch). `ChronosFlowBridge.isAvailable()` is
        // main-actor, matching this VM.
        self.chronosFlowInstalled = ChronosFlowBridge.isAvailable()
    }

    // MARK: - Derived state (computed; recomputed from source arrays + controller input)

    /// The displayed, filtered feed. **Verbatim** port of the Kotlin 5-input `combine` filter
    /// (CONVENTIONS §4 "the 5-input feed filter predicate is ported verbatim").
    var bookmarks: [Bookmark] {
        let list = rawBookmarks
        let query = searchController.searchQuery
        let category = searchController.selectedCategory
        let tag = searchController.selectedTag
        let mode = searchController.searchMode
        let semanticList = searchController.semanticResults
        let quick = searchController.quickFilter
        let library = searchController.libraryFilter
        let spaceId = searchController.selectedSpaceId

        let base = (mode == .semantic && !query.isBlankVM) ? semanticList : list
        return base.filter { item in
            let matchQuery = mode == .semantic || query.isBlankVM ||
                item.text.containsCI(query) ||
                (item.title?.containsCI(query) ?? false) ||
                (item.url?.containsCI(query) ?? false) ||
                (item.summary?.containsCI(query) ?? false) ||
                (item.ocrText?.containsCI(query) ?? false) ||
                (item.sourceTitle?.containsCI(query) ?? false) ||
                (item.sourceAbstract?.containsCI(query) ?? false) ||
                item.tags.contains { $0.containsCI(query) }

            let matchCategory = category == nil || (item.category?.caseInsensitiveEquals(category!) ?? false)
            let matchTag = tag == nil || item.tags.contains { $0.caseInsensitiveEquals(tag!) }
            let matchQuick: Bool
            switch quick {
            case .all: matchQuick = true
            case .favorites: matchQuick = item.isFavorite
            // The Kotlin `READ_LATER` case maps to the Swift enum's `.saved`.
            case .saved: matchQuick = item.isSavedForLater
            // The Swift `QuickFilter` defines three extra pills the Kotlin VM never had
            // (`.unread`/`.papers`/`.code`). Parity-preserving definitions (see NOTE in result):
            case .unread: matchQuick = !item.isAnalyzed
            case .papers: matchQuick = item.sourceType == .ARXIV || item.sourceType == .DOI
            case .code: matchQuick = item.sourceType == .GITHUB || item.sourceType == .HUGGING_FACE
            }
            let matchSpace = spaceId == nil || item.spaceId == spaceId
            let matchLibrary: Bool
            switch library {
            case .all: matchLibrary = true
            case .hasOCR: matchLibrary = !(item.ocrText?.isBlank ?? true)
            case .hasSource: matchLibrary = item.sourceType != nil
            case .deepAnalyzed: matchLibrary = item.isDeepAnalyzed
            }
            return matchQuery && matchCategory && matchTag && matchQuick && matchSpace && matchLibrary
        }
    }

    /// User-created Spaces with live membership counts, newest first. Port of the Kotlin
    /// `combine(getSpacesFlow(uid), rawBookmarks)` mapping (`groupingBy { it.spaceId }.eachCount()`).
    var spaces: [Space] {
        if userId == nil { return [] }
        var counts: [String: Int] = [:]
        for b in rawBookmarks {
            if let sid = b.spaceId { counts[sid, default: 0] += 1 }
        }
        return rawSpaces.map { space in
            Space(
                id: space.id, userId: space.userId, name: space.name, color: space.color,
                icon: space.icon, createdAt: space.createdAt, count: counts[space.id] ?? 0,
                description: space.description, isPinned: space.isPinned,
                sortIndex: space.sortIndex, rules: space.rules
            )
        }
    }

    /// Aggregated library statistics. Port of the Kotlin `rawBookmarks.map { … CurioStats(...) }`.
    var stats: CurioStats {
        let list = rawBookmarks
        let curated = list.count { $0.isAnalyzed }
        let ocr = list.count { !($0.ocrText?.isBlankVM ?? true) }
        let withSource = list.count { $0.sourceType != nil }
        let deepAnalyzed = list.count { $0.isDeepAnalyzed }
        let favorites = list.count { $0.isFavorite }
        let readLater = list.count { $0.isSavedForLater }
        var counts: [String: Int] = [:]
        // `tagsMap` mirrors Kotlin `mutableMapOf` (a LinkedHashMap — **insertion-ordered**). The order
        // is load-bearing: `sortedByDescending` is a *stable* sort, so tied tag counts keep first-seen
        // order. A plain Swift `Dictionary` has no stable iteration order, so first-seen order is
        // tracked explicitly in `tagOrder`.
        var tagsMap: [String: Int] = [:]
        var tagOrder: [String] = []
        for item in list {
            if let cat = item.category?.trimmingCharacters(in: .whitespacesAndNewlines), !cat.isEmpty {
                counts[cat, default: 0] += 1
            }
            for tag in item.tags {
                let normalized = tag.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if normalized.isEmpty { continue }
                if tagsMap[normalized] == nil { tagOrder.append(normalized) }
                tagsMap[normalized, default: 0] += 1
            }
        }
        // Kotlin `tagsMap.toList().sortedByDescending { it.second }.take(8)`: stable descending sort
        // over insertion order, then top 8.
        let topTags = tagOrder.enumerated()
            .sorted { a, b in
                let ca = tagsMap[a.element] ?? 0
                let cb = tagsMap[b.element] ?? 0
                if ca != cb { return ca > cb }
                return a.offset < b.offset
            }
            .map { ($0.element, tagsMap[$0.element] ?? 0) }
            .prefix(8)
        return CurioStats(
            totalCount: list.count, curatedCount: curated, ocrCount: ocr,
            categoryCounts: counts, topTags: Array(topTags),
            sourceCount: withSource, deepAnalyzedCount: deepAnalyzed,
            favoriteCount: favorites, readLaterCount: readLater
        )
    }

    /// A small rotating set of older, not-yet-starred saves with a source link — items worth
    /// revisiting. Oldest-first; `shuffleRediscover` rotates the window. Port of `rediscoverPicks`.
    var rediscoverPicks: [Bookmark] {
        let cutoff = Self.nowMillis() - Self.rediscoverMinAgeMs
        let candidates = rawBookmarks
            .filter { !$0.isFavorite && !($0.url?.isBlankVM ?? true) && $0.createdAt <= cutoff }
            .sorted { $0.createdAt < $1.createdAt }
        if candidates.isEmpty { return [] }
        let start = rediscoverOffset % candidates.count
        return (0..<min(Self.rediscoverBatch, candidates.count)).map {
            candidates[(start + $0) % candidates.count]
        }
    }

    /// Rotates to the next batch of rediscovery picks. Port of `shuffleRediscover`.
    func shuffleRediscover() { rediscoverOffset += Self.rediscoverBatch }

    // MARK: - Embedding model management

    /// Downloads the on-device EmbeddingGemma weights + tokenizer. An optional Hugging Face `token`
    /// (for the Gemma-license-gated repo) is persisted by the manager (once confirmed working) and
    /// reused on later attempts.
    func downloadEmbeddingModel(token: String? = nil) {
        launch { [weak self] in
            guard let self else { return }
            await self.embeddingModelManager.download(overrideToken: token)
            // Mirror the *actual* terminal state into the global banner rather than the raw boolean:
            // a `false` can also mean "ignored a re-entrant tap while a download is already running",
            // which must not surface as a failure. Reading the state also gives the real error text.
            switch self.embeddingModelManager.state {
            case .ready:
                self.syncState = .success("On-device model ready")
            case .failed(let message):
                self.syncState = .error(message)
            default:
                break // still downloading (elsewhere) or no-op — leave the banner untouched
            }
        }
    }

    /// Removes the downloaded model — embeddings fall back to the cloud path. Port of `deleteEmbeddingModel`.
    func deleteEmbeddingModel() { embeddingModelManager.delete() }

    /// Drops all stored vectors so they get rebuilt (use when switching embedding models/dimensions).
    func clearEmbeddingsForReindex() {
        spaceSuggestions = [:]
        launch { [weak self] in
            await self?.repository.clearAllEmbeddings()
        }
    }

    // MARK: - Spaces

    func createSpace(
        name: String, color: Int64, icon: String,
        description: String = "", rules: SpaceRules = .empty, isPinned: Bool = false
    ) {
        guard let uid = userId else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        launch { [weak self] in
            guard let self else { return }
            let space = await self.repository.createSpace(
                userId: uid, name: trimmed, color: color, icon: icon,
                description: description, rules: rules, isPinned: isPinned
            )
            if rules.isActive {
                let count = await self.repository.applySpaceRules(spaceId: space.id)
                if rules.autoFile { _ = await self.repository.applyRulesToLibrary(userId: uid) }
                self.reportSpaceRulesResult(count: count, spaceName: trimmed)
                self.scheduleOrganizeAfterEmbed()
            }
        }
    }

    func updateSpace(
        id: String, name: String, color: Int64, icon: String,
        description: String = "", rules: SpaceRules = .empty, isPinned: Bool = false
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        launch { [weak self] in
            guard let self else { return }
            await self.repository.updateSpace(
                id: id, name: trimmed, color: color, icon: icon,
                description: description, rules: rules, isPinned: isPinned
            )
            if let uid = self.userId, rules.isActive {
                let count = await self.repository.applySpaceRules(spaceId: id)
                if rules.autoFile { _ = await self.repository.applyRulesToLibrary(userId: uid) }
                self.reportSpaceRulesResult(count: count, spaceName: trimmed)
                self.scheduleOrganizeAfterEmbed()
            }
        }
    }

    func deleteSpace(id: String) {
        launch { [weak self] in
            guard let self else { return }
            self.searchController.clearSpaceIf(id)
            self.spaceSuggestions = self.spaceSuggestions.filter { $0.value.spaceId != id }
            await self.repository.deleteSpace(id: id)
            self.scheduleOrganizeAfterEmbed()
        }
    }

    /// Pins (or unpins) a Space so it sorts to the top of the list. Port of `setSpacePinned`.
    func setSpacePinned(id: String, pinned: Bool) {
        launch { [weak self] in
            await self?.repository.setSpacePinned(id: id, pinned: pinned)
        }
    }

    /// Explicit "Apply rules now" for a Smart Space — files every unfiled matching bookmark into it
    /// and reports how many were swept in. Port of `applySpaceRules`.
    func applySpaceRules(_ space: Space) {
        launch { [weak self] in
            guard let self else { return }
            let count = await self.repository.applySpaceRules(spaceId: space.id)
            self.reportSpaceRulesResult(count: count, spaceName: space.name)
            if count > 0 { self.scheduleOrganizeAfterEmbed() }
        }
    }

    private func reportSpaceRulesResult(count: Int, spaceName: String) {
        syncState = .success(
            count == 0
                ? "No new matches for \"\(spaceName)\""
                : "Filed \(count) bookmark\(count == 1 ? "" : "s") into \"\(spaceName)\""
        )
    }

    /// Files (or unfiles, when `spaceId` is nil) the given bookmarks into a Space. Port of
    /// `assignBookmarksToSpace` (facades CurationController).
    func assignBookmarksToSpace(ids: [String], spaceId: String?) {
        if !ids.isEmpty {
            spaceSuggestions = spaceSuggestions.filter { !ids.contains($0.key) }
        }
        curationController.assignToSpace(ids: ids, spaceId: spaceId)
        // Filing or un-filing changes centroids and the unfiled set → refresh suggestions.
        if !ids.isEmpty { scheduleOrganizeAfterEmbed() }
    }

    /// Runs embedding-driven auto-organisation and stashes medium-confidence suggestions.
    func organizeByEmbedding(announce: Bool = false) {
        guard let uid = userId else { return }
        launch { [weak self] in
            guard let self else { return }
            do {
                let result = await self.repository.organizeByEmbedding(userId: uid)
                self.spaceSuggestions = Dictionary(uniqueKeysWithValues: result.suggestions.map { ($0.bookmarkId, $0) })
                if announce, let msg = result.announceMessage() {
                    self.syncState = .success(msg)
                }
            } catch is CancellationError {
                return
            } catch {
                Self.logger.error("organizeByEmbedding failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Refreshes embedding suggestions after returning to the app. Background indexing auto-files
    /// and discovers clusters in the DB but only the ViewModel holds medium-confidence suggestions.
    func refreshSuggestionsOnForeground() {
        guard userId != nil else { return }
        foregroundOrganizeTask?.cancel()
        foregroundOrganizeTask = launch { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.organizeByEmbedding(announce: false)
        }
    }

    /// Files a suggested bookmark into its suggested Space and drops the consumed suggestion.
    func acceptSpaceSuggestion(bookmarkId: String) {
        guard let suggestion = spaceSuggestions[bookmarkId] else { return }
        assignBookmarksToSpace(ids: [bookmarkId], spaceId: suggestion.spaceId)
    }

    /// Accepts the AI-category suggestion for an unfiled bookmark: ensures the Space matching its
    /// `category` exists and files the bookmark into it. Categories never organise the UI directly —
    /// they only *suggest* a Space here. Port of `acceptCategorySuggestion`.
    func acceptCategorySuggestion(_ bookmark: Bookmark) {
        guard let uid = userId else { return }
        guard let category = bookmark.category, !category.isBlankVM else { return }
        spaceSuggestions.removeValue(forKey: bookmark.id)
        launch { [weak self] in
            guard let self else { return }
            if let spaceId = await self.repository.ensureCategorySpace(userId: uid, category: category) {
                await self.repository.assignToSpace(ids: [bookmark.id], spaceId: spaceId)
                self.scheduleOrganizeAfterEmbed()
            }
        }
    }

    /// Creates a new Space and immediately files `ids` into it — the bulk "new space" shortcut.
    /// Port of `createSpaceAndAssign`.
    func createSpaceAndAssign(
        name: String, color: Int64, icon: String, ids: [String],
        description: String = "", rules: SpaceRules = .empty, isPinned: Bool = false
    ) {
        guard let uid = userId else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        launch { [weak self] in
            guard let self else { return }
            let space = await self.repository.createSpace(
                userId: uid, name: trimmed, color: color, icon: icon,
                description: description, rules: rules, isPinned: isPinned
            )
            if !ids.isEmpty { await self.repository.assignToSpace(ids: ids, spaceId: space.id) }
            if rules.isActive {
                let count = await self.repository.applySpaceRules(spaceId: space.id)
                if rules.autoFile { _ = await self.repository.applyRulesToLibrary(userId: uid) }
                self.reportSpaceRulesResult(count: count, spaceName: trimmed)
            }
            if !ids.isEmpty || rules.isActive { self.scheduleOrganizeAfterEmbed() }
        }
    }

    // MARK: - Personal curation toggles (facade CurationController)

    func toggleFavorite(_ bookmark: Bookmark) { curationController.toggleFavorite(bookmark) }
    func toggleSavedForLater(_ bookmark: Bookmark) { curationController.toggleSavedForLater(bookmark) }
    /// Saves (or clears, when blank) the user's personal note on an entry. Port of `updateNotes`.
    func updateNotes(bookmarkId: String, notes: String?) {
        curationController.updateNotes(bookmarkId: bookmarkId, notes: notes)
    }

    // MARK: - ChronosFlow handoff (productivity integration)
    //
    // Hands a bookmark to the companion ChronosFlow planner app via its interop handoff queue
    // (`ChronosFlowBridge`). Each call reports its outcome through `syncState` (the same channel
    // sync messages use). The bridge is an actor, so the file I/O runs off the main actor —
    // the analogue of the Kotlin `withContext(Dispatchers.IO)` hop.

    /// "Remind me to read later" for `bookmark`. Curio now owns the reminder in-house: it schedules
    /// its own local `UNUserNotificationCenter` notification (via `reminderScheduler`) for the time
    /// implied by `choice`, so the reminder fires whether or not the companion ChronosFlow app is
    /// installed. When ChronosFlow IS installed we also mirror the item into its reading list
    /// (best-effort) so it appears in the user's planner — but that no longer gates the confirmation.
    func remindToReadLaterInChronosFlow(_ bookmark: Bookmark, choice: ChronosReminderChoice) {
        let url = bookmark.url?.nilIfBlankVM ?? bookmark.text.nilIfBlankVM
        guard let url else {
            setTransientSyncState(.error("This bookmark has no link to read later."))
            return
        }
        let title = (bookmark.sourceTitle ?? bookmark.title)?.nilIfBlankVM
        let remindAt = choice.toEpochMillis()
        let notes = bookmark.notes
        let bookmarkId = bookmark.id
        launch { [weak self] in
            guard let self else { return }
            // Primary: Curio's own scheduled local reminder.
            if let remindAt {
                await self.reminderScheduler.schedule(
                    bookmarkId: bookmarkId, title: title, url: url, atEpochMillis: remindAt
                )
            }
            // Optional mirror to ChronosFlow (only if installed). Best-effort; failures are ignored.
            if self.chronosFlowInstalled {
                try? await self.chronosFlowBridge.sendToReadingList(
                    url: url, title: title, reminderAtEpochMillis: remindAt, notes: notes
                )
            }
            self.setTransientSyncState(.success(
                choice == .none
                    ? "Saved to read later"
                    : "Curio will remind you \(choice.label.lowercased())"
            ))
        }
    }

    /// Drops `bookmark` into ChronosFlow's quick-capture inbox. Port of `captureToChronosFlowInbox`.
    func captureToChronosFlowInbox(_ bookmark: Bookmark) {
        var parts: [String] = []
        if let title = (bookmark.sourceTitle ?? bookmark.title)?.nilIfBlankVM { parts.append(title) }
        parts.append(bookmark.url?.nilIfBlankVM ?? bookmark.text)
        // Kotlin `listOfNotNull(...).distinct().joinToString("\n").ifBlank { bookmark.text }`.
        var seen = Set<String>()
        let text = parts.filter { seen.insert($0).inserted }.joined(separator: "\n")
        let payload = text.isBlankVM ? bookmark.text : text
        launch { [weak self] in
            guard let self else { return }
            do {
                try await self.chronosFlowBridge.captureToInbox(payload)
                self.setTransientSyncState(.success("Captured to ChronosFlow inbox"))
            } catch {
                self.setTransientSyncState(.error(Self.chronosFlowError(error)))
            }
        }
    }

    /// Creates a follow-up task in ChronosFlow from `bookmark`. Port of `createChronosFlowTask`.
    func createChronosFlowTask(_ bookmark: Bookmark) {
        let title = (bookmark.sourceTitle ?? bookmark.title)?.nilIfBlankVM
            ?? String(bookmark.text.prefix(80))
        launch { [weak self] in
            guard let self else { return }
            do {
                try await self.chronosFlowBridge.createTask(
                    title: title,
                    notes: bookmark.summary ?? bookmark.notes,
                    url: bookmark.url?.nilIfBlankVM
                )
                self.setTransientSyncState(.success("Created a task in ChronosFlow"))
            } catch {
                self.setTransientSyncState(.error(Self.chronosFlowError(error)))
            }
        }
    }

    /// User-facing ChronosFlow failure text. Port of `chronosFlowError` (the Android
    /// `SecurityException` arm maps to the bridge's declined/unavailable errors).
    private static func chronosFlowError(_ error: Error) -> String {
        let message = (error as? LocalizedError)?.errorDescription
            ?? (error as NSError).localizedDescription
        return message.isEmpty ? "Couldn't reach ChronosFlow." : message
    }

    /// Monotonic generation for `setTransientSyncState`. Kotlin compares by reference identity
    /// (`===`), so an older timer never clears a NEWER banner that happens to carry an equal value
    /// (e.g. the same ChronosFlow message set twice in quick succession). Swift value types have no
    /// identity, so each transient gets a generation number and the timer clears only its own.
    @ObservationIgnored private var transientSyncGeneration = 0

    /// Sets a transient ChronosFlow result on `syncState` and clears it after `delaySeconds` so it
    /// doesn't masquerade as a persistent sync error in the feed banner. Port of
    /// `setTransientSyncState` (identity-checked clear — see `transientSyncGeneration`).
    private func setTransientSyncState(_ state: SyncUiState, delaySeconds: Double = 4) {
        transientSyncGeneration += 1
        let generation = transientSyncGeneration
        syncState = state
        launch { [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard let self else { return }
            if self.transientSyncGeneration == generation, self.syncState == state {
                self.syncState = .idle
            }
        }
    }

    // MARK: - Identity / share capture

    func setUserId(_ userId: String) {
        self.userId = userId
        // (Re)subscribe the eager bookmarks + spaces streams for this user.
        subscribeStreams(userId: userId)

        // A share that cold-started the app may have queued a capture before we had a user id.
        if let pending = pendingSharedCapture {
            pendingSharedCapture = nil
            addManualBookmark(pending)
        }

        // Auto-organisation on login: Smart-Space rules sweep first (user intent wins), then AI
        // categories seed default Spaces for anything still unfiled.
        launch { [weak self] in
            guard let self else { return }
            // `applyRulesToLibrary` / `backfillCategorySpaces` are non-throwing resilient repository
            // calls (CONVENTIONS §3), so the Kotlin `runCatching { … }.onFailure { … }` reduces to a
            // cooperative cancellation check between the two — if the Task is cancelled we bail (the
            // Kotlin `if (e is CancellationException) throw e`); there is otherwise nothing to log.
            _ = await self.repository.applyRulesToLibrary(userId: userId)
            if Task.isCancelled { return }
            await self.repository.backfillCategorySpaces(userId: userId)
            if Task.isCancelled { return }
            self.organizeByEmbedding(announce: false)
        }

        syncBookmarks(fetchNextPage: false)
    }

    /// Ingests text or a URL shared into Curio from another app's share sheet, reusing the manual-add
    /// path (persist → resolve primary source). If no user is signed in yet, the text is queued and
    /// `setUserId` ingests it on sign-in. Port of `captureSharedText`.
    ///
    /// - Returns: `true` if ingested immediately; `false` if deferred until the user signs in.
    @discardableResult
    func captureSharedText(_ rawText: String) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return false }
        if userId != nil {
            addManualBookmark(text)
            return true
        } else {
            pendingSharedCapture = text
            return false
        }
    }

    func setForceLocalNano(_ enabled: Bool) { forceLocalNano = enabled }

    // MARK: - xAI key management

    /// Re-evaluates whether a cloud key is available (call after the user saves/clears their key).
    /// Port of `refreshKeyAvailability`.
    func refreshKeyAvailability() {
        launch { [weak self] in
            guard let self else { return }
            let configured = self.xaiKeyStore.isConfigured()
            self.xaiKeyConfigured = configured
            self.forceLocalNano = !configured
        }
    }

    /// Persists a user-supplied xAI API key (encrypted) and activates it immediately. A blank value
    /// clears it (reverting to the build-time key, if any). Port of `saveXaiKey`.
    func saveXaiKey(_ key: String) {
        launch { [weak self] in
            guard let self else { return }
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            await self.tokenStore.saveXaiKey(trimmed)
            XaiKeyStore.setRuntimeKey(trimmed)
            // Refresh both `xaiKeyConfigured` and `forceLocalNano` together.
            self.refreshKeyAvailability()
        }
    }

    // MARK: - Sync

    func syncBookmarks(fetchNextPage: Bool = false) {
        guard let uid = userId else { return }
        // Guard: don't start a new sync while one is loading or while rate-limited.
        switch syncState {
        case .loading, .rateLimited: return
        default: break
        }
        launch { [weak self] in
            guard let self else { return }
            self.syncState = .loading(nil)
            self.liveActivityManager.taskStarted(.sync)
            defer { self.liveActivityManager.taskFinished(.sync) }
            do {
                try await self.repository.syncBookmarks(userId: uid, fetchNextPage: fetchNextPage)
                self.syncState = .success("Synchronized successfully")
                self.resolveNewSources()
                self.scheduleOrganizeAfterEmbed()
            } catch let rateLimit as RateLimitError {
                self.startRateLimitCountdown(seconds: Int(rateLimit.resetTimeSeconds))
            } catch is CancellationError {
                // Cooperative cancellation — leave state as-is (the VM is tearing down).
            } catch {
                let message = humanReadableError(error, context: .sync)
                self.syncState = .error(message)
                self.liveActivityManager.syncError(message)
            }
        }
    }

    /// Starts (or restarts) the rate-limit countdown. Replaces the Android `CountDownTimer` with a
    /// cancellable `Task` loop ticking once per second. Port of `startRateLimitCountDown`.
    private func startRateLimitCountdown(seconds: Int) {
        rateLimitTask?.cancel()
        syncState = .rateLimited(secondsLeft: seconds)
        rateLimitTask = Task { [weak self] in
            // Tick down once per second from `seconds-1` to `0`, then snap to idle (matching the
            // Android `CountDownTimer(seconds*1000, 1000)` ticks + `onFinish`).
            var remaining = seconds
            while remaining > 0 {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return // cancelled
                }
                remaining -= 1
                guard let self else { return }
                if remaining > 0 {
                    self.syncState = .rateLimited(secondsLeft: remaining)
                } else {
                    self.syncState = .idle
                }
            }
            // seconds == 0 edge: finish immediately.
            if seconds == 0 { self?.syncState = .idle }
        }
    }

    // MARK: - OCR

    #if canImport(UIKit)
    /// Runs Vision OCR on a picked image for a bookmark, persisting the scheduled flag then the result.
    /// Port of `processOcrForBookmark`. The Android `Bitmap` becomes a `UIImage`.
    func processOcrForBookmark(bookmarkId: String, image: UIImage) {
        launch { [weak self] in
            guard let self else { return }
            self.analysisState = .processing(bookmarkId: bookmarkId)
            do {
                try Task.checkCancellation()
                await self.repository.updateOcrContent(id: bookmarkId, ocrText: nil, isOcrScheduled: true)
                let text = await self.ocrAnalyzer.analyze(image)
                try Task.checkCancellation()
                await self.repository.updateOcrContent(id: bookmarkId, ocrText: text, isOcrScheduled: false)
                self.analysisState = .success(bookmarkId: bookmarkId)
            } catch is CancellationError {
                // The scheduled flag was persisted BEFORE Vision ran; on cancel nothing else
                // ever clears it, so the card would show "OCR pending" forever. Reset it —
                // harmless during teardown (SwiftData writes are best-effort there).
                await self.repository.updateOcrContent(id: bookmarkId, ocrText: nil, isOcrScheduled: false)
            } catch {
                Self.logger.error("OCR processing failed for bookmark \(bookmarkId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                self.analysisState = .error(message: humanReadableError(error, context: .ai), bookmarkId: bookmarkId)
            }
            // Kotlin `finally`: only clear a still-Processing state on cancellation/exit; leave
            // Error intact so the UI can show it.
            if case .processing = self.analysisState {
                self.analysisState = .idle
            }
        }
    }
    #endif

    // MARK: - AI analysis

    func runAiAnalysis(_ bookmark: Bookmark) {
        launch { [weak self] in
            guard let self else { return }
            self.analysisState = .processing(bookmarkId: bookmark.id)
            do {
                let result = try await self.textGenerator.analyze(
                    text: bookmark.text,
                    ocrText: bookmark.ocrText,
                    sourceAbstract: bookmark.sourceAbstract,
                    forceLocal: self.forceLocalNano,
                    // Let Grok read the bookmark's image directly (vision) when one is attached.
                    imageUrl: bookmark.imageUrl
                )
                let suggestedTags: [String]
                if !result.category.isBlankVM {
                    let catTag = result.category.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    let lowered = result.tags.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                    suggestedTags = lowered.contains(catTag) ? result.tags : result.tags + [catTag]
                } else {
                    suggestedTags = result.tags
                }

                await self.repository.updateAnalysisAndTags(
                    id: bookmark.id, summary: result.summary, category: result.category,
                    tags: suggestedTags, entities: result.entities
                )

                // Auto-filing precedence (only for still-unfiled items, never overriding a manual
                // choice): a user-authored Smart Space rule wins; otherwise the AI category seeds its
                // default Space. The freshly-analysed bookmark carries the new category/tags so rules
                // can match on them.
                let uid = self.userId
                if let uid, bookmark.spaceId == nil || bookmark.spaceId == "" {
                    let analysed = Self.analysedCopy(
                        of: bookmark, summary: result.summary, category: result.category,
                        tags: suggestedTags, entities: result.entities
                    )
                    let filedByRule = await self.repository.fileByRules(bookmark: analysed)
                    if filedByRule == nil && !result.category.isBlankVM {
                        if let spaceId = await self.repository.ensureCategorySpace(userId: uid, category: result.category) {
                            await self.repository.assignToSpace(ids: [bookmark.id], spaceId: spaceId)
                        }
                    }
                }

                self.analysisState = .success(bookmarkId: bookmark.id)

                // Auto-generate embedding after successful analysis (only when not forcing local —
                // matching the Kotlin gate).
                if !self.forceLocalNano {
                    self.generateEmbeddingForBookmark(bookmark.id)
                }
            } catch is CancellationError {
                // Never swallow cancellation (CONVENTIONS §4).
            } catch {
                self.analysisState = .error(message: humanReadableError(error, context: .ai), bookmarkId: bookmark.id)
            }
        }
    }

    func runDeepAnalysis(_ bookmark: Bookmark) {
        launch { [weak self] in
            guard let self else { return }
            self.analysisState = .processing(bookmarkId: bookmark.id)
            do {
                let result = try await self.aiAnalyzer.deepAnalyzeBookmark(
                    text: bookmark.text,
                    ocrText: bookmark.ocrText,
                    sourceAbstract: bookmark.sourceAbstract
                )
                await self.repository.updateDeepSummary(id: bookmark.id, deepSummary: result.formatted())
                self.analysisState = .success(bookmarkId: bookmark.id)
            } catch is CancellationError {
            } catch {
                self.analysisState = .error(message: humanReadableError(error, context: .ai), bookmarkId: bookmark.id)
            }
        }
    }

    // MARK: - Source resolution

    func resolveSource(_ bookmark: Bookmark) {
        launch { [weak self] in
            guard let self else { return }
            self.analysisState = .processing(bookmarkId: bookmark.id)
            do {
                let info = await self.sourceResolver.resolve(text: bookmark.text, url: bookmark.url)
                if let info {
                    guard let uid = self.userId else { return }
                    // `SourceInfo.sourceId` is a non-optional `String` in the Swift port, so the
                    // Kotlin `if (info.sourceId != null)` branch is always the resolved one.
                    let existingWithSource = self.rawBookmarks.first {
                        $0.id != bookmark.id && $0.sourceId == info.sourceId
                    }

                    if existingWithSource != nil {
                        await self.repository.incrementReferenceCount(sourceId: info.sourceId, userId: uid)
                        await self.repository.deleteBookmarks(ids: [bookmark.id])
                    } else {
                        await self.repository.updateSourceInfo(
                            id: bookmark.id,
                            sourceType: info.sourceType,
                            sourceId: info.sourceId,
                            sourceTitle: info.sourceTitle,
                            sourceAuthors: info.sourceAuthors,
                            sourceAbstract: info.sourceAbstract,
                            sourceExtra: info.sourceExtra
                        )
                    }
                }
                self.analysisState = .success(bookmarkId: bookmark.id)
            } catch is CancellationError {
            } catch {
                self.analysisState = .error(message: humanReadableError(error, context: .source), bookmarkId: bookmark.id)
            }
        }
    }

    /// Resolves primary sources for up to 10 still-unresolved bookmarks with a URL. Per-bookmark
    /// failures are non-fatal (logged, not aborting the batch). Port of `resolveNewSources`.
    func resolveNewSources() {
        launch { [weak self] in
            guard let self else { return }
            let unresolved = self.rawBookmarks.filter { $0.sourceType == nil && $0.url != nil }
            for bookmark in unresolved.prefix(10) {
                do {
                    try Task.checkCancellation()
                    // Heavy resolution work runs in the actor-isolated SourceResolver (off the main
                    // actor); the Kotlin `withContext(Dispatchers.IO)` hop is implicit here.
                    let info = await self.sourceResolver.resolve(text: bookmark.text, url: bookmark.url)
                    if let info {
                        await self.repository.updateSourceInfo(
                            id: bookmark.id, sourceType: info.sourceType, sourceId: info.sourceId,
                            sourceTitle: info.sourceTitle, sourceAuthors: info.sourceAuthors,
                            sourceAbstract: info.sourceAbstract, sourceExtra: info.sourceExtra
                        )
                    }
                } catch is CancellationError {
                    return
                } catch {
                    Self.logger.warning("Source resolution failed for \(bookmark.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func deduplicateBySource() {
        guard let uid = userId else { return }
        launch { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                await self.repository.deduplicateBySource(userId: uid)
                self.syncState = .success("Deduplication complete")
            } catch is CancellationError {
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? (error as NSError).localizedDescription
                self.syncState = .error("Dedup failed: \(message)")
            }
        }
    }

    // MARK: - Semantic embeddings

    /// Generates + persists the embedding for a single bookmark (best-effort). Port of
    /// `generateEmbeddingForBookmark`.
    private func generateEmbeddingForBookmark(_ bookmarkId: String) {
        launch { [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                guard let bookmark = self.rawBookmarks.first(where: { $0.id == bookmarkId }) else { return }
                guard let embedding = await self.embeddingService.embedDocument(bookmark) else { return }
                await self.repository.updateEmbedding(id: bookmarkId, embedding: VectorSearch.floatArrayToData(embedding))
                self.scheduleOrganizeAfterEmbed()
            } catch is CancellationError {
            } catch {
                Self.logger.warning("Embedding generation failed for \(bookmarkId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func scheduleOrganizeAfterEmbed() {
        organizeAfterEmbedTask?.cancel()
        organizeAfterEmbedTask = launch { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.organizeByEmbedding(announce: false)
        }
    }

    /// Embeds all unembedded bookmarks and auto-organises afterward. Port of `embedAllBookmarks`.
    func embedAllBookmarks() {
        launch { [weak self] in
            guard let self else { return }
            guard let uid = self.userId else {
                self.syncState = .error("Sign in to embed bookmarks")
                return
            }
            let batch = await self.repository.getAllUnembedded(userId: uid)
            if batch.isEmpty {
                self.syncState = .success("Nothing to embed — all bookmarks already have vectors")
                return
            }
            let engine = self.embeddingService.isOnDevice() ? "on-device" : "xAI"
            var succeeded = 0
            var failed = 0
            for (index, bookmark) in batch.enumerated() {
                self.syncState = .loading("Embedding (\(engine))… \(index + 1)/\(batch.count)")
                do {
                    try Task.checkCancellation()
                    guard let embedding = await self.embeddingService.embedDocument(bookmark) else {
                        failed += 1
                        continue
                    }
                    await self.repository.updateEmbedding(
                        id: bookmark.id,
                        embedding: VectorSearch.floatArrayToData(embedding)
                    )
                    succeeded += 1
                } catch is CancellationError {
                    return
                } catch {
                    failed += 1
                    Self.logger.warning("Embedding generation failed for \(bookmark.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            if succeeded == 0 && failed > 0 {
                let detail = self.embeddingService.lastError
                    ?? "Embedding unavailable — generated 0 of \(failed) items"
                self.syncState = .error(detail)
            } else {
                let suffix = failed > 0 ? " (\(failed) skipped)" : ""
                self.syncState = .success("Embeddings generated for \(succeeded) items\(suffix)")
                if succeeded > 0 { self.organizeByEmbedding(announce: true) }
            }
        }
    }

    // MARK: - Citation export (BibTeX / RIS / CSL-JSON / Markdown)

    func exportBibtex(_ bookmarks: [Bookmark]) -> String { BibtexExporter.toBibtexList(bookmarks) }
    func exportSingleBibtex(_ bookmark: Bookmark) -> String? { BibtexExporter.toBibtex(bookmark) }
    func exportRis(_ bookmarks: [Bookmark]) -> String { BibtexExporter.toRisList(bookmarks) }
    func exportCslJson(_ bookmarks: [Bookmark]) -> String { BibtexExporter.toCslJsonList(bookmarks) }
    func exportMarkdown(_ bookmarks: [Bookmark]) -> String { BibtexExporter.toMarkdownList(bookmarks) }

    // MARK: - Existing operations (facade CurationController)

    func deleteBookmarks(ids: [String]) {
        if !ids.isEmpty {
            spaceSuggestions = spaceSuggestions.filter { !ids.contains($0.key) }
        }
        curationController.delete(ids: ids)
    }
    func updateCategoryForBookmarks(ids: [String], category: String) {
        if !ids.isEmpty {
            spaceSuggestions = spaceSuggestions.filter { !ids.contains($0.key) }
            scheduleOrganizeAfterEmbed()
        }
        curationController.updateCategory(ids: ids, category: category)
    }

    func clearAllData() {
        guard let uid = userId else { return }
        launch { [weak self] in
            await self?.repository.clearAll(userId: uid)
        }
    }

    func moveBookmarkUp(_ bookmark: Bookmark) {
        launch { [weak self] in
            guard let self else { return }
            let list = self.rawBookmarks
            guard let index = list.firstIndex(where: { $0.id == bookmark.id }) else { return }
            if index > 0 {
                let upper = list[index - 1]
                // Single transaction: both UPDATEs are atomic — no TOCTOU window.
                await self.repository.swapCreatedAt(
                    id1: bookmark.id, ts1: bookmark.createdAt, id2: upper.id, ts2: upper.createdAt
                )
            }
        }
    }

    func moveBookmarkDown(_ bookmark: Bookmark) {
        launch { [weak self] in
            guard let self else { return }
            let list = self.rawBookmarks
            guard let index = list.firstIndex(where: { $0.id == bookmark.id }) else { return }
            if index != -1 && index < list.count - 1 {
                let lower = list[index + 1]
                await self.repository.swapCreatedAt(
                    id1: bookmark.id, ts1: bookmark.createdAt, id2: lower.id, ts2: lower.createdAt
                )
            }
        }
    }

    /// Runs a quick cloud analysis and hands a formatted preview string back via the callback. Port of
    /// `getInstantSummaryPreview` (exact emoji template + failure string preserved).
    func getInstantSummaryPreview(text: String, onCompleted: @escaping @MainActor (String) -> Void) {
        launch { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.textGenerator.analyze(
                    text: text, ocrText: nil, sourceAbstract: nil, forceLocal: false
                )
                onCompleted("✨ Category: \(result.category)\n🏷️ Tags: \(result.tags.joined(separator: ", "))\n📝 Summary: \(result.summary)")
            } catch is CancellationError {
                // Cooperative cancellation — drop silently (the VM is tearing down); Kotlin's
                // `if (e is CancellationException) throw e` aborts the coroutine, which here is the
                // non-throwing `Task` simply ending.
                return
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? (error as NSError).localizedDescription
                let detail = message.isEmpty ? "Unknown error" : message
                onCompleted("❌ Analysis failed: \(detail). Add your xAI API key in Settings.")
            }
        }
    }

    // MARK: - Manual add

    /// Manually adds a bookmark from raw text, then resolves its primary source. Port of
    /// `addManualBookmark` (the `Result<Bookmark>` callback collapses to a `Swift.Result`).
    func addManualBookmark(_ text: String, onResult: @escaping @MainActor (Result<Bookmark, Error>) -> Void = { _ in }) {
        guard let uid = userId else { return }
        launch { [weak self] in
            guard let self else { return }
            do {
                let bookmark = try await self.repository.addBookmark(userId: uid, text: text)
                onResult(.success(bookmark))
                self.resolveSource(bookmark)
            } catch is CancellationError {
                // Cooperative cancellation — drop silently (the non-throwing `Task` simply ends).
                return
            } catch {
                onResult(.failure(error))
            }
        }
    }

    // MARK: - Grok image generation

    /// Generates a representative cover image for a bookmark via Grok's image model. Falls back to the
    /// procedural category graphic (no URL stored) when the API key is absent or the call fails, so the
    /// card always ends up in the "generated" state. Port of `generateImagenImage`.
    func generateImagenImage(bookmarkId: String) {
        launch { [weak self] in
            guard let self else { return }
            do {
                self.analysisState = .processing(bookmarkId: bookmarkId)
                let bookmark = self.rawBookmarks.first { $0.id == bookmarkId }
                let prompt = self.grokImageService.promptForCategory(
                    category: bookmark?.category,
                    title: bookmark?.sourceTitle ?? bookmark?.title
                )
                let generated = await self.grokImageService.generate(prompt: prompt)
                if let generated {
                    self.imagenUrls[bookmarkId] = generated.url
                }
                self.imagenGeneratedIds.insert(bookmarkId)
                self.analysisState = .success(bookmarkId: bookmarkId)
            } catch is CancellationError {
                // Cooperative cancellation — drop silently; the `finally`-equivalent below still
                // clears a residual Processing state. The non-throwing `Task` simply ends.
                if case .processing = self.analysisState { self.analysisState = .idle }
                return
            } catch {
                Self.logger.error("Image generation failed for \(bookmarkId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                self.imagenGeneratedIds.insert(bookmarkId)
                self.analysisState = .idle
            }
            // Kotlin `finally { if (state is Processing) Idle }` — clear only a still-Processing state.
            if case .processing = self.analysisState {
                self.analysisState = .idle
            }
        }
    }

    // MARK: - Teardown

    /// In-flight VM work spawned via `launch` — the iOS analogue of `viewModelScope`'s children.
    /// Kotlin cancels every launched coroutine when the VM clears; without tracking, Swift `Task`s
    /// would run to completion after teardown (still mutating `syncState`/`analysisState`) and pin
    /// the VM alive through their strong `guard let self` promotions.
    @ObservationIgnored private var inFlightTasks: [UUID: Task<Void, Never>] = [:]

    /// Spawns a tracked main-actor task (the Kotlin `viewModelScope.launch` analogue). The task
    /// removes itself on completion; `close()` cancels whatever is still running.
    @discardableResult
    private func launch(_ body: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let id = UUID()
        let task = Task { [weak self] in
            await body()
            self?.inFlightTasks[id] = nil
        }
        inFlightTasks[id] = task
        return task
    }

    /// Cancels the rate-limit countdown, every tracked `launch` task, the controllers' in-flight
    /// work, and the eager subscriptions. Port of `onCleared()` (where `viewModelScope.cancel()`
    /// covered all of these structurally). Called from the owning scene's teardown (CONVENTIONS §2).
    func close() {
        rateLimitTask?.cancel()
        for task in inFlightTasks.values { task.cancel() }
        inFlightTasks.removeAll()
        searchController.close()
        chatController.close()
        digestController.close()
        rawBookmarksCancellable?.cancel()
        spacesCancellable?.cancel()
    }

    deinit {
        // `AnyCancellable` subscriptions cancel themselves when the stored cancellables deallocate, so
        // only the in-flight `Task`s (Sendable) need an explicit cancel here.
        rateLimitTask?.cancel()
        for task in inFlightTasks.values { task.cancel() }
    }

    // MARK: - Private helpers

    /// (Re)subscribes the eager `rawBookmarks` + `rawSpaces` streams for `userId`. Mirrors the Kotlin
    /// `_userId.flatMapLatest { repository.getBookmarksFlow(uid) }` (and Spaces) — the old subscription
    /// is dropped and a new one started whenever the user changes.
    private func subscribeStreams(userId: String) {
        rawBookmarksCancellable?.cancel()
        spacesCancellable?.cancel()
        rawBookmarksCancellable = repository.getBookmarksFlow(userId: userId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] list in
                self?.rawBookmarks = list
                self?.pruneStaleSuggestions()
            }
        spacesCancellable = repository.getSpacesFlow(userId: userId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] list in
                self?.rawSpaces = list
                self?.pruneStaleSuggestions()
            }
    }

    /// Drops suggestions for deleted/filed bookmarks or Spaces that no longer exist.
    private func pruneStaleSuggestions() {
        let byId = Dictionary(uniqueKeysWithValues: rawBookmarks.map { ($0.id, $0) })
        let validSpaceIds = Set(rawSpaces.map { $0.id })
        let pruned = spaceSuggestions.filter { id, suggestion in
            guard let b = byId[id], b.spaceId == nil || b.spaceId == "" else { return false }
            return validSpaceIds.contains(suggestion.spaceId)
        }
        if pruned.count != spaceSuggestions.count || pruned != spaceSuggestions {
            spaceSuggestions = pruned
        }
    }

    /// Rebuilds a `Bookmark` carrying the freshly-analysed AI fields (`isAnalyzed = true`). Replaces
    /// the Kotlin `bookmark.copy(...)` (Swift's `Bookmark` is an immutable value type with no
    /// synthesised `copy`). All other fields are preserved verbatim.
    private static func analysedCopy(
        of b: Bookmark, summary: String, category: String, tags: [String], entities: String?
    ) -> Bookmark {
        Bookmark(
            id: b.id, text: b.text, createdAt: b.createdAt, userId: b.userId,
            title: b.title, url: b.url, summary: summary, tags: tags, category: category,
            imageUrl: b.imageUrl, ocrText: b.ocrText, isOcrScheduled: b.isOcrScheduled,
            isAnalyzed: true, sourceType: b.sourceType, sourceId: b.sourceId,
            sourceTitle: b.sourceTitle, sourceAuthors: b.sourceAuthors,
            sourceAbstract: b.sourceAbstract, sourceExtra: b.sourceExtra,
            referenceCount: b.referenceCount, entities: entities,
            isDeepAnalyzed: b.isDeepAnalyzed, deepSummary: b.deepSummary,
            isFavorite: b.isFavorite, isSavedForLater: b.isSavedForLater,
            authorName: b.authorName, authorUsername: b.authorUsername,
            imageAltText: b.imageAltText, spaceId: b.spaceId, notes: b.notes
        )
    }

    /// `System.currentTimeMillis()` — Unix epoch milliseconds.
    private static func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}

// MARK: - Local string helpers
//
// Kotlin `contains(query, ignoreCase = true)` / `equals(x, ignoreCase = true)` are ASCII/locale-
// independent case-insensitive comparisons. Mirror with `.caseInsensitive` (NOT
// `localizedStandardContains`, per CONVENTIONS §6 search semantics). Named distinctly to avoid
// colliding with blank helpers in sibling files.

private extension String {
    /// Mirrors Kotlin `String.isBlank()` (whitespace-only ⇒ blank).
    var isBlankVM: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Mirrors Kotlin `takeIf { it.isNotBlank() }`.
    var nilIfBlankVM: String? {
        isBlankVM ? nil : self
    }

    /// Mirrors Kotlin `contains(other, ignoreCase = true)`.
    func containsCI(_ other: String) -> Bool {
        range(of: other, options: .caseInsensitive) != nil
    }

    /// Mirrors Kotlin `equals(other, ignoreCase = true)`.
    func caseInsensitiveEquals(_ other: String) -> Bool {
        compare(other, options: .caseInsensitive) == .orderedSame
    }
}

// MARK: - Count-by-predicate helper

private extension Array {
    /// Mirrors Kotlin `Iterable.count { predicate }`.
    func count(_ predicate: (Element) -> Bool) -> Int {
        reduce(0) { predicate($1) ? $0 + 1 : $0 }
    }
}
