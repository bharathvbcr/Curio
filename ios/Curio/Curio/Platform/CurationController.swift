import Foundation
import Observation

/// Per-bookmark mutation actions (personal curation toggles, notes, deletion, category and Space
/// assignment). Ported 1:1 from `ui/CurationController.kt`.
///
/// These are thin repository delegations with no own UI state besides a one-shot error channel, so the
/// VM facades them and the UI is unchanged.
///
/// CONVENTIONS §4 / §11: `@MainActor @Observable final class`; `scope.launch` → `Task`;
/// `MutableSharedFlow<String>(extraBufferCapacity = 1)` (one-shot errors) → an `AsyncStream<String>`
/// with `.bufferingNewest(1)` (matches `tryEmit` + the single extra buffer slot).
///
/// NOTE on the error path: in the ported Swift `BookmarkRepository`, every mutation here
/// (`setFavorite`/`setSavedForLater`/`updateNotes`/`assignToSpace`/`deleteBookmarks`/
/// `updateCategoryForIds`) is a **non-throwing** `async` call — the resilient repository swallows its
/// own failures (CONVENTIONS §3 "Resilience contract"), so the Kotlin `try { … } catch { tryEmit(…) }`
/// has no throwing call to wrap. The `curationError` channel is retained for API/UI parity (and the
/// `surfaceError(_:)` hook is used if a future throwing repository variant is injected), but with the
/// current contract no error is emitted (matching the actual runtime behaviour — the repo never throws
/// these). The ubiquitous Kotlin `if (e is CancellationException) throw e` collapses to cooperative
/// `Task` cancellation, which is honoured automatically.
@MainActor
@Observable
final class CurationController {

    // MARK: - Injected dependencies

    @ObservationIgnored private let repository: BookmarkRepository

    // MARK: - One-shot error channel (SharedFlow → AsyncStream)

    /// One-shot error stream the UI consumes (e.g. a transient toast) and that auto-drops when no one
    /// is listening — mirrors `MutableSharedFlow(extraBufferCapacity = 1)` + `tryEmit`.
    @ObservationIgnored let curationError: AsyncStream<String>
    @ObservationIgnored private let errorContinuation: AsyncStream<String>.Continuation

    init(repository: BookmarkRepository) {
        self.repository = repository
        var continuation: AsyncStream<String>.Continuation!
        // `.bufferingNewest(1)` reproduces `extraBufferCapacity = 1`: the latest pending error is kept
        // and `tryEmit`-style yields never suspend / fail.
        self.curationError = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation = $0 }
        self.errorContinuation = continuation
    }

    deinit {
        errorContinuation.finish()
    }

    func toggleFavorite(_ bookmark: Bookmark) {
        Task { [weak self] in
            guard let self else { return }
            await self.repository.setFavorite(id: bookmark.id, isFavorite: !bookmark.isFavorite)
        }
    }

    func toggleSavedForLater(_ bookmark: Bookmark) {
        Task { [weak self] in
            guard let self else { return }
            await self.repository.setSavedForLater(id: bookmark.id, isSavedForLater: !bookmark.isSavedForLater)
        }
    }

    /// Saves (or clears, when blank) the user's personal note on an entry. Port of `updateNotes`.
    func updateNotes(bookmarkId: String, notes: String?) {
        Task { [weak self] in
            guard let self else { return }
            await self.repository.updateNotes(id: bookmarkId, notes: notes)
        }
    }

    func assignToSpace(ids: [String], spaceId: String?) {
        if ids.isEmpty { return }
        Task { [weak self] in
            guard let self else { return }
            await self.repository.assignToSpace(ids: ids, spaceId: spaceId)
        }
    }

    func delete(ids: [String]) {
        Task { [weak self] in
            guard let self else { return }
            await self.repository.deleteBookmarks(ids: ids)
        }
    }

    func updateCategory(ids: [String], category: String) {
        Task { [weak self] in
            guard let self else { return }
            await self.repository.updateCategoryForIds(ids: ids, category: category)
        }
    }

    /// Yields a failure message onto the one-shot channel, mirroring the Kotlin
    /// `_curationError.tryEmit("Failed to update bookmark: ${e.message}")`. Exposed for parity / future
    /// throwing-repository variants; unused under the current non-throwing repository contract.
    func surfaceError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
        errorContinuation.yield("Failed to update bookmark: \(message)")
    }
}
