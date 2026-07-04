import Foundation
import SwiftData

/// Background-serialized SwiftData store for the `spaces` table. Direct port of `SpaceDao`
/// (`data/local/SpaceDao.kt`).
///
/// `@ModelActor` (off-main, serialized) mirrors Room's IO-dispatcher DAO. Returns domain `Space`
/// values (never `@Model`s). `Space.count` is a derived/transient field and is returned as `0` here —
/// the repository layer injects membership counts via a separate bookmark query (matching the Android
/// split where `SpaceDao` returns plain entities).
///
/// Deleting a Space has **NO cascade** (CONVENTIONS §6): `deleteSpace` only removes the `spaces` row;
/// the caller (repository) manually nulls bookmark membership via `BookmarkStore.clearSpace` in the
/// same op.
@ModelActor
actor SpaceStore {

    /// Ordering: pinned float to the top, then manual `sortIndex` ascending, newest `createdAt` as the
    /// final tiebreak — `ORDER BY isPinned DESC, sortIndex ASC, createdAt DESC`.
    ///
    /// Applied in-memory because `SortDescriptor` cannot sort on a `Bool` key path (`Bool` is not
    /// `Comparable`); `sortIndex`/`createdAt` are integers and would sort fine in the DB, but doing the
    /// whole comparison here keeps the three-key order exact and stable.
    private static func sortRows(_ rows: [SpaceModel]) -> [SpaceModel] {
        rows.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }   // pinned first (DESC)
            if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
            return a.createdAt > b.createdAt
        }
    }

    /// `SELECT * FROM spaces WHERE userId = ? ORDER BY isPinned DESC, sortIndex ASC, createdAt DESC`.
    /// Reactive analogue (`getSpaces`) — the repository re-queries on change to feed its publisher.
    func getSpaces(userId: String) -> [Space] {
        var descriptor = FetchDescriptor<SpaceModel>(
            predicate: #Predicate { $0.userId == userId }
        )
        descriptor.includePendingChanges = true
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return Self.sortRows(rows).map { $0.toDomain() }
    }

    /// Direct (one-shot) variant — same query/ordering as `getSpaces`.
    func getSpacesDirect(userId: String) -> [Space] {
        let descriptor = FetchDescriptor<SpaceModel>(
            predicate: #Predicate { $0.userId == userId }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return Self.sortRows(rows).map { $0.toDomain() }
    }

    /// `@Insert(onConflict = REPLACE)` — upsert by unique `id` (whole-row REPLACE), one `save()`.
    func upsertSpace(_ space: Space) {
        if let existing = firstModel(id: space.id) {
            existing.apply(space)
        } else {
            modelContext.insert(SpaceModel.from(space))
        }
        try? modelContext.save()
    }

    /// `DELETE FROM spaces WHERE id = ?`. NO cascade — membership cleanup is the caller's job.
    func deleteSpace(id: String) {
        guard let row = firstModel(id: id) else { return }
        modelContext.delete(row)
        try? modelContext.save()
    }

    /// `SELECT * FROM spaces WHERE id = ?`.
    func getSpaceById(id: String) -> Space? {
        firstModel(id: id)?.toDomain()
    }

    /// `UPDATE spaces SET isPinned = ? WHERE id = ?`.
    func setPinned(id: String, pinned: Bool) {
        guard let row = firstModel(id: id) else { return }
        row.isPinned = pinned
        try? modelContext.save()
    }

    /// `UPDATE spaces SET sortIndex = ? WHERE id = ?`.
    func setSortIndex(id: String, sortIndex: Int) {
        guard let row = firstModel(id: id) else { return }
        row.sortIndex = sortIndex
        try? modelContext.save()
    }

    // MARK: - Private

    private func firstModel(id: String) -> SpaceModel? {
        var descriptor = FetchDescriptor<SpaceModel>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}
