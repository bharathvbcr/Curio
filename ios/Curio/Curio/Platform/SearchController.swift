import Foundation
import Observation
import os

/// Owns the feed's search/filter INPUT state — query, mode, semantic results, category/tag/quick/space
/// filters — plus the on-device semantic-search run. Ported 1:1 from `ui/SearchController.kt`.
///
/// Deliberately scoped to the *inputs only*: the central feed filter that produces the displayed list
/// lives in `BookmarkViewModel` and simply reads these published properties, so the fragile reactive
/// graph is repointed (not rewritten). The VM facades the setters so the UI is unchanged.
///
/// CONVENTIONS §4: `@MainActor @Observable final class` (Observation replaces `MutableStateFlow`;
/// plain stored `var`s are auto-tracked). The Kotlin `scope.launch` + cancellable `Job` debounce
/// becomes a cancellable `Task` (CONVENTIONS §4 "Async pattern"); cancellation is honored and never
/// swallowed.
@MainActor
@Observable
final class SearchController {

    // MARK: - Injected dependencies

    /// On-device (or cloud-fallback) embedding provider used to embed the query for semantic search.
    @ObservationIgnored private let embeddingService: EmbeddingProvider
    @ObservationIgnored private let repository: BookmarkRepository
    /// Reads the VM's live library so the controller stays a thin collaborator (no ownership duplication).
    @ObservationIgnored private let rawBookmarks: @MainActor () -> [Bookmark]
    @ObservationIgnored private let currentUserId: @MainActor () -> String?

    // MARK: - Published input state (StateFlow → @Observable stored vars)

    /// Backing for `searchQuery`. The Kotlin `_searchQuery` private/`searchQuery` public split collapses
    /// to a single `private(set)` property (mutated only through `updateQuery`/`clearAll`).
    private(set) var searchQuery: String = ""

    private(set) var searchMode: SearchMode = .keyword

    private(set) var semanticResults: [Bookmark] = []

    private(set) var isSemanticLoading: Bool = false

    private(set) var selectedCategory: String? = nil

    private(set) var selectedTag: String? = nil

    private(set) var quickFilter: QuickFilter = .all

    private(set) var libraryFilter: LibraryFilter = .all

    private(set) var selectedSpaceId: String? = nil

    /// The in-flight (debounced) semantic-search task; cancelled before a new search and on `close()`.
    @ObservationIgnored private var semanticSearchTask: Task<Void, Never>?

    @ObservationIgnored private static let logger = Logger(subsystem: "com.curio.app", category: "SearchController")
    /// Coalesce rapid typing into one semantic search (a semantic search embeds the query and scans
    /// every stored vector, so it must not fire on every keystroke). Port of `DEBOUNCE_MS = 300L`.
    @ObservationIgnored private static let debounceMs: UInt64 = 300

    init(
        embeddingService: EmbeddingProvider,
        repository: BookmarkRepository,
        rawBookmarks: @escaping @MainActor () -> [Bookmark],
        currentUserId: @escaping @MainActor () -> String?
    ) {
        self.embeddingService = embeddingService
        self.repository = repository
        self.rawBookmarks = rawBookmarks
        self.currentUserId = currentUserId
    }

    // MARK: - Setters (facaded by the VM; UI unchanged)

    /// Toggles a quick filter: re-tapping the active filter resets to `.all`. Port of `setQuickFilter`.
    func setQuickFilter(_ filter: QuickFilter) {
        quickFilter = (quickFilter == filter) ? .all : filter
    }

    func setLibraryFilter(_ filter: LibraryFilter) {
        libraryFilter = (libraryFilter == filter) ? .all : filter
    }

    func selectSpace(_ spaceId: String?) { selectedSpaceId = spaceId }

    /// Clears the space filter only if it currently points at `id` (used when a Space is deleted).
    func clearSpaceIf(_ id: String) { if selectedSpaceId == id { selectedSpaceId = nil } }

    func selectCategory(_ category: String?) { selectedCategory = category }
    func selectTag(_ tag: String?) { selectedTag = tag }

    func updateQuery(_ query: String) {
        searchQuery = query
        if searchMode == .semantic && !query.isBlankQuery {
            // Debounce: coalesce rapid typing into one search.
            semanticSearchTask?.cancel()
            semanticSearchTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await Task.sleep(for: .milliseconds(Self.debounceMs))
                } catch {
                    return // cancelled during debounce — drop this search
                }
                await self.runSemanticSearch(query)
            }
        }
    }

    func setMode(_ mode: SearchMode) {
        searchMode = mode
        if mode == .keyword {
            semanticSearchTask?.cancel()
            semanticResults = []
        } else if !searchQuery.isBlankQuery {
            semanticSearchTask?.cancel()
            let q = searchQuery
            semanticSearchTask = Task { [weak self] in
                await self?.runSemanticSearch(q)
            }
        }
    }

    func clearAll() {
        searchQuery = ""; selectedCategory = nil; selectedTag = nil
        semanticResults = []; searchMode = .keyword
        quickFilter = .all; selectedSpaceId = nil
        libraryFilter = .all
    }

    // MARK: - Semantic search run

    /// Embeds the query, scans every stored vector, and maps the top-k ids back to live bookmarks.
    /// Port of `runSemanticSearch`. The Kotlin `try/finally` (always reset loading) + early `return`s
    /// map to a `defer { isSemanticLoading = false }`; cancellation is rethrown (never swallowed).
    private func runSemanticSearch(_ query: String) async {
        guard let uid = currentUserId() else { return }
        isSemanticLoading = true
        defer { isSemanticLoading = false }
        do {
            try Task.checkCancellation()
            guard let queryEmbedding = await embeddingService.embedQuery(query) else { return }
            try Task.checkCancellation()
            let stored = await repository.getBookmarksWithEmbeddings(userId: uid)
            let allEmbeddings: [(String, [Float])] = stored.map { (id, bytes) in
                (id, VectorSearch.dataToFloatArray(bytes))
            }
            if allEmbeddings.isEmpty { return }

            let topIds = Set(VectorSearch.topK(query: queryEmbedding, candidates: allEmbeddings, k: 20))
            // Kotlin `associateBy { it.id }` keeps the LAST value on key collision (ids are unique
            // here, so this is academic — preserved for fidelity).
            let bookmarkMap = Dictionary(rawBookmarks().map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            semanticResults = topIds.compactMap { bookmarkMap[$0] }
        } catch is CancellationError {
            // Cooperative cancellation: drop silently, mirroring Kotlin `if (e is CancellationException) throw e`.
        } catch {
            Self.logger.warning("Semantic search failed for query \"\(query, privacy: .public)\": \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Cancels any in-flight search job. Call from `BookmarkViewModel`'s teardown. Port of `close()`.
    func close() {
        semanticSearchTask?.cancel()
    }
}

// MARK: - Feed search/filter enums (owned here; the VM reads them)
//
// DESIGN assigns `SearchMode`/`QuickFilter` to the BookmarkViewModel module surface, but the feed
// search controller is their natural owner (the Kotlin `SearchMode`/`QuickFilter` are consumed here).
// They are defined once here so `BookmarkViewModel.swift` must NOT redefine them.

/// Feed search strategy. Raw values mirror the Kotlin enum `.name`s (lowercased for Swift idiom is
/// avoided — these are not persistence keys, but the case names match the Kotlin ones).
enum SearchMode: String, CaseIterable, Sendable, Hashable {
    case keyword = "KEYWORD"
    case semantic = "SEMANTIC"
}

/// Insights stat-tile drill-down filter applied on the bookmark feed.
enum LibraryFilter: String, Sendable, Hashable {
    case all = "ALL"
    case hasOCR = "HAS_OCR"
    case hasSource = "HAS_SOURCE"
    case deepAnalyzed = "DEEP_ANALYZED"
}

/// One-tap library filters surfaced as pills above the feed. Port of the Kotlin `QuickFilter`.
enum QuickFilter: String, CaseIterable, Sendable, Hashable {
    case all = "ALL"
    case unread = "UNREAD"
    case favorites = "FAVORITES"
    case saved = "SAVED"
    case papers = "PAPERS"
    case code = "CODE"
}

// MARK: - Blank-string helper

private extension String {
    /// Mirrors Kotlin `String.isNotBlank()` negation (`isBlank()`): whitespace-only counts as blank.
    /// Named distinctly to avoid colliding with `isBlank`/`isBlankPrompt` defined in other modules.
    var isBlankQuery: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
