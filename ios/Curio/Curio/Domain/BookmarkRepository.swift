import Foundation
import Combine

/// Full bookmark + Space lifecycle contract. Ports `interface BookmarkRepository` from
/// `domain/repo/BookmarkRepository.kt`.
///
/// Concurrency / type mapping (CONVENTIONS §3, §5, §7, §11):
/// - Kotlin hot `Flow<List<Bookmark>>` / `Flow<List<Space>>` → Combine
///   `AnyPublisher<[Bookmark], Never>` / `AnyPublisher<[Space], Never>` (re-emit on every DB change).
/// - `suspend …: Result<Unit>`  → `async throws` (no return).
/// - `suspend …: Result<Bookmark>` → `async throws -> Bookmark`.
/// - plain `suspend` reads/writes (no `Result`) → `async` with **no** `throws`.
/// - Kotlin `ByteArray` → `Data`; `List<Pair<String, ByteArray>>` → `[(String, Data)]`.
/// - default parameter values are preserved (`fetchNextPage = false`, `entities = nil`,
///   `referenceCount = 1`, Space create/update defaults, etc.).
///
/// `Sendable` because the repository (an actor in the Repository module) is shared across actors.
protocol BookmarkRepository: Sendable {

    // MARK: Reads / streams

    func getBookmarksFlow(userId: String) -> AnyPublisher<[Bookmark], Never>

    func getBookmarkById(id: String) async -> Bookmark?

    /// Searches bookmarks by keyword across text, title, summary, and OCR content for `userId`.
    /// Returns all bookmarks ordered newest-first when `query` is blank.
    func searchBookmarks(userId: String, query: String) async -> [Bookmark]

    // MARK: Sync / clear

    /// 3-phase X sync. Throws `RateLimitError` on 429 (the only typed failure surfaced here —
    /// CONVENTIONS §"Resilience contract"). `fetchNextPage` continues from the stored cursor.
    func syncBookmarks(userId: String, fetchNextPage: Bool) async throws

    func clearAll(userId: String) async

    // MARK: Analysis / OCR

    func updateAnalysisAndTags(
        id: String,
        summary: String?,
        category: String?,
        tags: [String],
        entities: String?
    ) async

    func updateOcrContent(id: String, ocrText: String?, isOcrScheduled: Bool) async

    // MARK: CRUD

    /// Manually adds a bookmark (the impl assigns a `manual_` id prefix). Throws on failure
    /// (collapses Kotlin `Result<Bookmark>`).
    func addBookmark(userId: String, text: String) async throws -> Bookmark

    func deleteBookmarks(ids: [String]) async

    func updateCategoryForIds(ids: [String], category: String) async

    func updateCreatedAt(id: String, createdAt: Int64) async

    /// Atomically swaps the ordering timestamps of two bookmarks inside a single DB transaction
    /// (exactly one `save()` — TOCTOU guarantee preserved, CONVENTIONS §5).
    func swapCreatedAt(id1: String, ts1: Int64, id2: String, ts2: Int64) async

    // MARK: Phase 8 — source resolution

    func updateSourceInfo(
        id: String,
        sourceType: SourceType?,
        sourceId: String?,
        sourceTitle: String?,
        sourceAuthors: String?,
        sourceAbstract: String?,
        sourceExtra: String?,
        referenceCount: Int
    ) async

    func incrementReferenceCount(sourceId: String, userId: String) async

    func deduplicateBySource(userId: String) async

    // MARK: Phase 10 — embeddings

    func updateEmbedding(id: String, embedding: Data) async

    /// Bulk-write embeddings in a single transaction (perf-14: exactly one `save()`).
    func updateEmbeddings(updates: [(String, Data)]) async

    func getBookmarksWithEmbeddings(userId: String) async -> [(String, Data)]

    /// Analyzed bookmarks still lacking an embedding — drives the charging-time on-device backfill.
    func getUnembeddedAnalyzed(userId: String) async -> [Bookmark]

    /// Drops all stored embeddings (e.g. when switching embedding models / vector dimensions).
    /// Device-wide sweep (not userId-scoped) — CONVENTIONS §6.
    func clearAllEmbeddings() async

    // MARK: Phase 9 — deep analysis

    func updateDeepSummary(id: String, deepSummary: String) async

    // MARK: Phase 12 — personal curation

    func setFavorite(id: String, isFavorite: Bool) async

    func setSavedForLater(id: String, isSavedForLater: Bool) async

    /// Sets (or clears, when `notes` is nil/blank) the user's personal note. Local-only (never
    /// mirrored to cloud — CONVENTIONS Repository cross-cutting).
    func updateNotes(id: String, notes: String?) async

    // MARK: Spaces — user-created collections

    func getSpacesFlow(userId: String) -> AnyPublisher<[Space], Never>

    func createSpace(
        userId: String,
        name: String,
        color: Int64,
        icon: String,
        description: String,
        rules: SpaceRules,
        isPinned: Bool
    ) async -> Space

    func updateSpace(
        id: String,
        name: String,
        color: Int64,
        icon: String,
        description: String,
        rules: SpaceRules,
        isPinned: Bool
    ) async

    /// Deletes a Space. NO FK cascade — membership is manually nulled by the impl in the same op
    /// (CONVENTIONS §6 "No relationships / no cascade").
    func deleteSpace(id: String) async

    /// Pins (or unpins) a Space so it floats to the top of the list.
    func setSpacePinned(id: String, pinned: Bool) async

    /// Files (or unfiles, when `spaceId` is nil) the given bookmarks into a Space.
    func assignToSpace(ids: [String], spaceId: String?) async

    // MARK: Smart Spaces — rule-driven auto-filing

    /// Files `bookmark` into the **first** auto-file Smart Space whose rules match it, returning that
    /// Space's id (or nil when nothing matches). Eligible sources are unfiled bookmarks and those in
    /// AI category Spaces; a manual filing into a user Space is never overridden.
    func fileByRules(bookmark: Bookmark) async -> String?

    /// Files every **eligible** bookmark matching `spaceId`'s rules into it, **regardless** of the
    /// Space's auto-file toggle (the explicit "Apply rules now" / save action). Eligible = unfiled or
    /// in an AI category Space. Returns the number filed.
    func applySpaceRules(spaceId: String) async -> Int

    /// Backfill across all of `userId`'s auto-file Smart Spaces: every eligible bookmark is filed into
    /// the best-matching Space. Idempotent and cheap; safe on every login. Returns the number filed.
    func applyRulesToLibrary(userId: String) async -> Int

    /// Ensures the canonical default Space for an AI `category` exists for `userId` (creating it from
    /// `CategorySpaces` the first time) and returns its id. Returns nil when `category` is blank.
    /// Idempotent — an existing Space (including one the user has since renamed) is left untouched.
    func ensureCategorySpace(userId: String, category: String) async -> String?

    /// Backfills Space membership for already-analysed bookmarks: any item that has an AI category but
    /// no Space yet is filed into its category's default Space (created on demand). Idempotent and
    /// cheap — only unfiled, categorised items are touched. Safe on every login.
    func backfillCategorySpaces(userId: String) async

    /// Embedding-driven auto-organisation. Compares unfiled bookmark vectors against Space centroids,
    /// auto-files high-confidence matches, creates cluster Spaces, and returns medium-confidence
    /// suggestions. No-op when nothing is embedded/unfiled.
    func organizeByEmbedding(userId: String) async -> OrganizeResult

    /// Every bookmark still lacking an embedding — drives the user-initiated "Embed All" action.
    func getAllUnembedded(userId: String) async -> [Bookmark]
}

// MARK: - Default-argument bridge

/// Convenience overloads preserving the Kotlin **default parameter values**. Swift protocols cannot
/// declare default arguments on requirements, so the defaults live in a protocol extension that
/// forwards to the full-signature requirement. This keeps call sites able to omit the same arguments
/// the Kotlin callers omit (`syncBookmarks(userId:)`, `updateAnalysisAndTags(...)` without
/// `entities`, `updateSourceInfo(... )` with `referenceCount` defaulted to 1, Space create/update
/// with `description=""`, `rules=.empty`, `isPinned=false`).
extension BookmarkRepository {

    func syncBookmarks(userId: String) async throws {
        try await syncBookmarks(userId: userId, fetchNextPage: false)
    }

    func updateAnalysisAndTags(
        id: String,
        summary: String?,
        category: String?,
        tags: [String]
    ) async {
        await updateAnalysisAndTags(
            id: id, summary: summary, category: category, tags: tags, entities: nil
        )
    }

    func updateSourceInfo(
        id: String,
        sourceType: SourceType?,
        sourceId: String?,
        sourceTitle: String?,
        sourceAuthors: String?,
        sourceAbstract: String?,
        sourceExtra: String?
    ) async {
        await updateSourceInfo(
            id: id,
            sourceType: sourceType,
            sourceId: sourceId,
            sourceTitle: sourceTitle,
            sourceAuthors: sourceAuthors,
            sourceAbstract: sourceAbstract,
            sourceExtra: sourceExtra,
            referenceCount: 1
        )
    }

    /// Reduced-arg convenience for the common "just name/color/icon" Space creation, defaulting the
    /// trailing args exactly as Kotlin does (`description=""`, `rules=.empty`, `isPinned=false`).
    /// A distinct (shorter) parameter list avoids re-entering the full-signature requirement.
    func createSpace(
        userId: String,
        name: String,
        color: Int64,
        icon: String
    ) async -> Space {
        await createSpace(
            userId: userId, name: name, color: color, icon: icon,
            description: "", rules: .empty, isPinned: false
        )
    }

    /// Reduced-arg convenience for `updateSpace` mirroring the Kotlin trailing defaults.
    func updateSpace(
        id: String,
        name: String,
        color: Int64,
        icon: String
    ) async {
        await updateSpace(
            id: id, name: name, color: color, icon: icon,
            description: "", rules: .empty, isPinned: false
        )
    }
}
