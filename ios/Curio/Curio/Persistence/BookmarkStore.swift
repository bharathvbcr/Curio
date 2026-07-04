import Foundation
import SwiftData

/// Projection row for `getIdsAndEmbeddings` — the `(id, embedding)` pair fetched for vector search.
/// Direct port of `data class IdEmbeddingRow` (`data/local/BookmarkDao.kt`). `Sendable` so it can
/// cross the store actor boundary.
struct IdEmbeddingRow: Sendable {
    let id: String
    let embedding: Data?

    init(id: String, embedding: Data?) {
        self.id = id
        self.embedding = embedding
    }
}

/// Background-serialized SwiftData store for the `bookmarks` table. Direct port of `BookmarkDao`
/// (`data/local/BookmarkDao.kt`).
///
/// `@ModelActor` gives an actor with its own `ModelContext` running off the main actor — the iOS
/// analogue of Room's IO-dispatcher DAO (CONVENTIONS §5). Every method returns/accepts domain value
/// types or scalars (never a `@Model`, which is not `Sendable`); the `ModelMappers` convert at the
/// boundary.
///
/// Fidelity invariants preserved (CONVENTIONS §6, DESIGN §Persistence):
/// - **Upsert** = fetch-by-unique-`id` then overwrite, else insert (`OnConflictStrategy.REPLACE`).
/// - **ASCII case-insensitive search** across `text/title/summary/ocrText` OR'd — `range(of:options:
///   .caseInsensitive)`, NOT `localizedStandardContains` (Room `LIKE … COLLATE NOCASE` is ASCII).
/// - **`'' vs nil` sentinels** kept distinct (`summary == nil || summary == ""`,
///   `spaceId == nil || spaceId == ""`).
/// - **Atomic batches**: `swapCreatedAt` and bulk embedding writes do all mutations then exactly
///   **one** `save()` (TOCTOU + O(1) WAL flush).
/// - **userId scoping** vs deliberate **device-wide** sweeps (`observeAll`, `getAllBookmarksDirect`,
///   `clearAllEmbeddings`).
@ModelActor
actor BookmarkStore {

    // MARK: - Reads (ordered, userId-scoped)

    /// `SELECT * FROM bookmarks WHERE userId = ? ORDER BY createdAt DESC`.
    func getBookmarks(userId: String) -> [Bookmark] {
        var descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        return fetchDomain(descriptor)
    }

    /// `SELECT * FROM bookmarks ORDER BY createdAt DESC` — **all users** (device-wide sweep).
    func observeAll() -> [Bookmark] {
        var descriptor = FetchDescriptor<BookmarkModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        return fetchDomain(descriptor)
    }

    /// Case-insensitive (ASCII) full-text-ish search across `text/ocrText/summary/title`, OR'd,
    /// newest first. Mirrors the Room `LIKE '%'||:query||'%' COLLATE NOCASE` query.
    ///
    /// SwiftData's `#Predicate` `localizedStandardContains`/`contains` cannot express Room's exact
    /// ASCII `COLLATE NOCASE` semantics, so we fetch userId-scoped + ordered, then filter in-memory
    /// with `range(of:options:.caseInsensitive)` (non-localized). A blank query returns every
    /// bookmark for the user (Room would `LIKE '%%'`, which matches all non-null and the impl treats
    /// blank as "all").
    func search(userId: String, query: String) -> [Bookmark] {
        var descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        if query.isEmpty {
            return rows.map { $0.toDomain() }
        }
        let matched = rows.filter { row in
            matchesCaseInsensitive(row.text, query)
                || matchesCaseInsensitive(row.ocrText, query)
                || matchesCaseInsensitive(row.summary, query)
                || matchesCaseInsensitive(row.title, query)
        }
        return matched.map { $0.toDomain() }
    }

    /// `SELECT * FROM bookmarks WHERE userId = ? AND category = ? ORDER BY createdAt DESC`.
    func byCategory(userId: String, category: String) -> [Bookmark] {
        var descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { $0.userId == userId && $0.category == category },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.includePendingChanges = true
        return fetchDomain(descriptor)
    }

    /// Distinct non-null categories for a user, sorted ascending. Mirrors
    /// `SELECT DISTINCT category … WHERE category IS NOT NULL ORDER BY category`.
    func categories(userId: String) -> [String] {
        var descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { $0.userId == userId && $0.category != nil }
        )
        descriptor.includePendingChanges = true
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        let set = Set(rows.compactMap { $0.category })
        return set.sorted()
    }

    /// Bookmarks not yet enriched (no AI analysis OR no summary). Mirrors
    /// `WHERE userId = ? AND (isAnalyzed = 0 OR summary IS NULL OR summary = '')`.
    /// Preserves the `'' vs nil` distinction exactly.
    func unenriched(userId: String) -> [Bookmark] {
        let descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate {
                $0.userId == userId && (!$0.isAnalyzed || $0.summary == nil || $0.summary == "")
            }
        )
        return fetchDomain(descriptor)
    }

    /// `SELECT * FROM bookmarks WHERE id = ?` (single, any user).
    func getBookmarkById(id: String) -> Bookmark? {
        firstModel(id: id)?.toDomain()
    }

    /// `SELECT * … WHERE sourceId = ? AND userId = ? LIMIT 1`.
    func getBookmarkBySourceId(sourceId: String, userId: String) -> Bookmark? {
        var descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { $0.sourceId == sourceId && $0.userId == userId }
        )
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.toDomain()
    }

    /// `SELECT * … WHERE userId = ? AND sourceId IS NOT NULL`.
    func getBookmarksWithSourceId(userId: String) -> [Bookmark] {
        let descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { $0.userId == userId && $0.sourceId != nil }
        )
        return fetchDomain(descriptor)
    }

    /// All bookmarks on the device, across users — device-wide background sweep only.
    func getAllBookmarksDirect() -> [Bookmark] {
        let descriptor = FetchDescriptor<BookmarkModel>()
        return fetchDomain(descriptor)
    }

    /// One user's bookmarks, newest first (filter pushed into the fetch).
    func getBookmarksByUserDirect(userId: String) -> [Bookmark] {
        let descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return fetchDomain(descriptor)
    }

    /// `SELECT * FROM bookmarks WHERE id IN (:ids)`.
    func getBookmarksByIds(ids: [String]) -> [Bookmark] {
        guard !ids.isEmpty else { return [] }
        let idSet = Set(ids)
        let descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { idSet.contains($0.id) }
        )
        return fetchDomain(descriptor)
    }

    /// Unfiled bookmarks (`spaceId IS NULL OR spaceId = ''`) — `'' vs nil` preserved.
    func getUnfiledBookmarks(userId: String) -> [Bookmark] {
        let descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate {
                $0.userId == userId && ($0.spaceId == nil || $0.spaceId == "")
            }
        )
        return fetchDomain(descriptor)
    }

    /// Unfiled bookmarks plus those in AI category Spaces — eligible for Smart-Space rule filing.
    func getRuleFilingCandidates(userId: String) -> [Bookmark] {
        getBookmarksByUserDirect(userId: userId)
            .filter { CategorySpaces.bookmarkEligibleForRuleFiling($0.spaceId) }
    }

    // MARK: - Writes (upsert / clear)

    /// `@Insert(onConflict = REPLACE)` of a batch. Upsert per id (whole-row REPLACE), one `save()`.
    func insertBookmarks(_ bookmarks: [Bookmark]) {
        for b in bookmarks {
            if let existing = firstModel(id: b.id) {
                existing.apply(b)
            } else {
                modelContext.insert(BookmarkModel.from(b))
            }
        }
        try? modelContext.save()
    }

    /// `DELETE FROM bookmarks WHERE userId = ?`.
    func clearBookmarks(userId: String) {
        let descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { $0.userId == userId }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        for row in rows { modelContext.delete(row) }
        try? modelContext.save()
    }

    /// `DELETE FROM bookmarks WHERE id IN (:ids)`.
    func deleteBookmarks(ids: [String]) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        let descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { idSet.contains($0.id) }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        for row in rows { modelContext.delete(row) }
        try? modelContext.save()
    }

    // MARK: - Targeted column updates

    /// `UPDATE … SET summary, tags, category, isAnalyzed, entities WHERE id = ?`.
    /// `tags` here is the CSV string exactly as Room stores it (callers pass the joined CSV).
    func updateAnalysis(
        id: String,
        summary: String?,
        tags: String?,
        category: String?,
        isAnalyzed: Bool,
        entities: String?
    ) {
        guard let row = firstModel(id: id) else { return }
        row.summary = summary
        row.tags = tags
        row.category = category
        row.isAnalyzed = isAnalyzed
        row.entities = entities
        try? modelContext.save()
    }

    /// `UPDATE … SET ocrText, isOcrScheduled WHERE id = ?`.
    func updateOcr(id: String, ocrText: String?, isOcrScheduled: Bool) {
        guard let row = firstModel(id: id) else { return }
        row.ocrText = ocrText
        row.isOcrScheduled = isOcrScheduled
        try? modelContext.save()
    }

    /// `UPDATE … SET category WHERE id IN (:ids)`.
    func updateCategoryForIds(ids: [String], category: String) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        let descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { idSet.contains($0.id) }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        for row in rows { row.category = category }
        try? modelContext.save()
    }

    /// `UPDATE … SET spaceId WHERE id IN (:ids)` — files (or unfiles, when `spaceId == nil`).
    func updateSpaceForIds(ids: [String], spaceId: String?) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        let descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { idSet.contains($0.id) }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        for row in rows { row.spaceId = spaceId }
        try? modelContext.save()
    }

    /// `UPDATE … SET spaceId = NULL WHERE spaceId = ?` — clears membership when a Space is deleted
    /// (manual cascade; there is no FK cascade — CONVENTIONS §6).
    func clearSpace(spaceId: String) {
        let descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { $0.spaceId == spaceId }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        for row in rows { row.spaceId = nil }
        try? modelContext.save()
    }

    /// `UPDATE … SET createdAt WHERE id = ?`.
    func updateCreatedAt(id: String, createdAt: Int64) {
        guard let row = firstModel(id: id) else { return }
        row.createdAt = createdAt
        try? modelContext.save()
    }

    /// Atomically swaps two bookmarks' `createdAt` timestamps inside one transaction (both mutations
    /// then exactly **one** `save()`) so a concurrent reader never observes the intermediate state
    /// where both share a timestamp — the Room `@Transaction` TOCTOU guarantee (CONVENTIONS §5).
    func swapCreatedAt(id1: String, ts1: Int64, id2: String, ts2: Int64) {
        let row1 = firstModel(id: id1)
        let row2 = firstModel(id: id2)
        row1?.createdAt = ts2
        row2?.createdAt = ts1
        try? modelContext.save()
    }

    /// `UPDATE … SET sourceType, sourceId, sourceTitle, sourceAuthors, sourceAbstract, sourceExtra,
    /// referenceCount WHERE id = ?`.
    func updateSourceInfo(
        id: String,
        sourceType: String?,
        sourceId: String?,
        sourceTitle: String?,
        sourceAuthors: String?,
        sourceAbstract: String?,
        sourceExtra: String?,
        referenceCount: Int
    ) {
        guard let row = firstModel(id: id) else { return }
        row.sourceType = sourceType
        row.sourceId = sourceId
        row.sourceTitle = sourceTitle
        row.sourceAuthors = sourceAuthors
        row.sourceAbstract = sourceAbstract
        row.sourceExtra = sourceExtra
        row.referenceCount = referenceCount
        try? modelContext.save()
    }

    /// `UPDATE … SET referenceCount = referenceCount + 1 WHERE sourceId = ? AND userId = ?`.
    /// Fetch-and-increment then save (atomic-increment analogue). Affects every row with that
    /// `sourceId` for the user (Room updates all matching rows).
    func incrementReferenceCount(sourceId: String, userId: String) {
        let descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { $0.sourceId == sourceId && $0.userId == userId }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        for row in rows { row.referenceCount += 1 }
        try? modelContext.save()
    }

    // MARK: - Embeddings

    /// `UPDATE … SET embedding WHERE id = ?`.
    func updateEmbedding(id: String, embedding: Data?) {
        guard let row = firstModel(id: id) else { return }
        row.embedding = embedding
        try? modelContext.save()
    }

    /// Bulk-write embeddings inside a single transaction (perf-14): all mutations then exactly **one**
    /// `save()`. Mirrors `updateEmbeddings(updates: List<Pair<String, ByteArray>>)`.
    func updateEmbeddings(updates: [(String, Data)]) {
        guard !updates.isEmpty else { return }
        for (id, vec) in updates {
            firstModel(id: id)?.embedding = vec
        }
        try? modelContext.save()
    }

    /// Parallel-list batch variant (build-16 / Task 4) — same O(1) WAL-flush guarantee. Mirrors
    /// `batchUpdateEmbeddings(ids, embeddings)` (zips the two lists). Extra elements in the longer
    /// list are ignored (Kotlin `zip` truncates to the shorter).
    func batchUpdateEmbeddings(ids: [String], embeddings: [Data]) {
        guard !ids.isEmpty, !embeddings.isEmpty else { return }
        for (id, emb) in zip(ids, embeddings) {
            firstModel(id: id)?.embedding = emb
        }
        try? modelContext.save()
    }

    /// `SELECT id, embedding … WHERE userId = ? AND embedding IS NOT NULL`. Projection fetch to avoid
    /// loading whole rows — `propertiesToFetch: [\.id, \.embedding]`.
    func getIdsAndEmbeddings(userId: String) -> [IdEmbeddingRow] {
        var descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { $0.userId == userId && $0.embedding != nil }
        )
        descriptor.propertiesToFetch = [\.id, \.embedding]
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.map { IdEmbeddingRow(id: $0.id, embedding: $0.embedding) }
    }

    /// id + Space membership + embedding for every embedded bookmark — input to `SemanticOrganizer`.
    func getSpaceEmbeddings(userId: String) -> [(id: String, spaceId: String?, embedding: Data)] {
        var descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { $0.userId == userId && $0.embedding != nil }
        )
        descriptor.propertiesToFetch = [\.id, \.spaceId, \.embedding]
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.compactMap { row in
            guard let emb = row.embedding, emb.count >= 4 else { return nil }
            let sid = row.spaceId?.isEmpty == true ? nil : row.spaceId
            return (id: row.id, spaceId: sid, embedding: emb)
        }
    }

    /// Every bookmark lacking an embedding — work list for "Embed All" (uncapped, newest first).
    func getAllUnembedded(userId: String) -> [Bookmark] {
        var descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { $0.embedding == nil && $0.userId == userId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return fetchDomain(descriptor)
    }

    /// Analyzed bookmarks still lacking an embedding — the charging-time backfill work list,
    /// capped at 200. Mirrors `WHERE isAnalyzed = 1 AND embedding IS NULL AND userId = ? LIMIT 200`.
    func getUnembedded(userId: String) -> [Bookmark] {
        var descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate {
                $0.isAnalyzed && $0.embedding == nil && $0.userId == userId
            }
        )
        descriptor.fetchLimit = 200
        return fetchDomain(descriptor)
    }

    /// `UPDATE bookmarks SET embedding = NULL` — **device-wide** (all users), used when switching
    /// embedding model / vector dimensions.
    func clearAllEmbeddings() {
        let descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { $0.embedding != nil }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        for row in rows { row.embedding = nil }
        try? modelContext.save()
    }

    // MARK: - Deep analysis / curation

    /// `UPDATE … SET isDeepAnalyzed, deepSummary WHERE id = ?`.
    func updateDeepSummary(id: String, deepSummary: String?, isDeepAnalyzed: Bool) {
        guard let row = firstModel(id: id) else { return }
        row.deepSummary = deepSummary
        row.isDeepAnalyzed = isDeepAnalyzed
        try? modelContext.save()
    }

    /// `UPDATE … SET isFavorite WHERE id = ?`.
    func updateFavorite(id: String, isFavorite: Bool) {
        guard let row = firstModel(id: id) else { return }
        row.isFavorite = isFavorite
        try? modelContext.save()
    }

    /// `UPDATE … SET isSavedForLater WHERE id = ?`.
    func updateSavedForLater(id: String, isSavedForLater: Bool) {
        guard let row = firstModel(id: id) else { return }
        row.isSavedForLater = isSavedForLater
        try? modelContext.save()
    }

    /// `UPDATE … SET notes WHERE id = ?` (local-only; nil/blank clears at the repository boundary).
    func updateNotes(id: String, notes: String?) {
        guard let row = firstModel(id: id) else { return }
        row.notes = notes
        try? modelContext.save()
    }

    // MARK: - Private helpers

    /// Fetches the single model with the given unique `id` (nil when absent).
    private func firstModel(id: String) -> BookmarkModel? {
        var descriptor = FetchDescriptor<BookmarkModel>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// Runs a fetch and maps every row to a domain `Bookmark` (the `Sendable` value crossing the
    /// actor boundary).
    private func fetchDomain(_ descriptor: FetchDescriptor<BookmarkModel>) -> [Bookmark] {
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.map { $0.toDomain() }
    }

    /// ASCII-style, non-localized case-insensitive substring test (Room `LIKE … COLLATE NOCASE`).
    /// Uses `range(of:options:.caseInsensitive)`, NOT `localizedStandardContains`.
    private func matchesCaseInsensitive(_ haystack: String?, _ needle: String) -> Bool {
        guard let haystack else { return false }
        return haystack.range(of: needle, options: .caseInsensitive) != nil
    }
}
