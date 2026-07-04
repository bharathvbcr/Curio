import Foundation
import os

/// Charging-gated, on-device-ONLY embedding backfill.
///
/// Direct port of `class EmbeddingIndexWorker : CoroutineWorker` from
/// `background/EmbeddingIndexWorker.kt`. The WorkManager `CoroutineWorker` becomes a plain `actor`
/// (CONVENTIONS §5) driven by `BackgroundTaskCoordinator`'s BGTask handler; `doWork()` becomes
/// `run(isStopped:)`.
///
/// It embeds any analyzed bookmarks that still lack a vector, using the **local** EmbeddingGemma
/// provider. It never touches the cloud embedder: per Curio's privacy model (CONVENTIONS §9), the
/// `onDeviceEmbeddingProvider` is injected as a distinct on-device-only provider so the backfill can
/// never fall back to cloud. If the model hasn't been downloaded, this is a no-op.
///
/// Foreground on-demand embedding is unchanged — this only *backfills* in bulk while charging.
///
/// Fidelity notes:
/// - The Kotlin `Result` (`success`/`retry`/`failure`) is preserved as `IndexResult` so the BGTask
///   handler can map a `.failure` to `setTaskCompleted(success: false)`. There is no OS "retry" on
///   iOS — a `.retry` simply means "more batches remain"; the next charging window's self-resubmitted
///   BGTask picks them up.
/// - `MAX_PER_RUN = 200` caps each run so a huge library is chunked across charging sessions rather
///   than hogging one (perf-14 batching preserved: all `(id, bytes)` pairs accumulate, then flush in a
///   single transactional `updateEmbeddings`).
/// - `isStopped` (Android `isStopped`) is supplied by the caller as a cancellation probe so the loop
///   stops promptly when the BGTask expires.
actor EmbeddingIndexer {

    /// Mirrors the Android WorkManager `Result` outcomes used by this worker.
    enum IndexResult: Sendable, Equatable {
        case success
        case retry
        case failure
    }

    private let onDeviceEmbeddingProvider: OnDeviceEmbeddingProvider
    private let bookmarkRepository: BookmarkRepository
    private let tokenStore: TokenStore

    private static let logger = Logger(subsystem: "com.curio.app", category: "EmbeddingIndexWorker")

    /// Cap per run so a huge library is chunked across charging sessions rather than hogging one.
    /// Mirrors Android `MAX_PER_RUN = 200`.
    private static let maxPerRun = 200

    init(
        onDeviceEmbeddingProvider: OnDeviceEmbeddingProvider,
        bookmarkRepository: BookmarkRepository,
        tokenStore: TokenStore
    ) {
        self.onDeviceEmbeddingProvider = onDeviceEmbeddingProvider
        self.bookmarkRepository = bookmarkRepository
        self.tokenStore = tokenStore
    }

    /// One backfill pass. Direct port of `doWork()`.
    ///
    /// - Parameter isStopped: cancellation probe (Android `isStopped`); checked at the head of each
    ///   embed iteration so the loop breaks promptly when the BGTask expires.
    @discardableResult
    func run(
        isStopped: @Sendable () -> Bool = { false },
        onProgress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> IndexResult {
        // On-device only. If EmbeddingGemma isn't present, there's nothing to do in the background.
        if !onDeviceEmbeddingProvider.isOnDevice() {
            Self.logger.debug("EmbeddingGemma not downloaded — skipping background indexing")
            return .success
        }

        // The Kotlin body is wrapped in a try/catch mapping CancellationException → rethrow,
        // IOException → retry, and any other Throwable → failure. Swift's data-layer methods are
        // resilient (they return nil/empty rather than throwing), so the only thrown error reachable
        // here is `CancellationError`, which we surface as `.retry` (the work will resume next window)
        // — never swallowed (CONVENTIONS §5).
        do {
            guard let userId = await tokenStore.getUserId() else {
                Self.logger.debug("No signed-in user — skipping background indexing")
                return .success
            }

            let pending = await bookmarkRepository.getUnembeddedAnalyzed(userId: userId)
            if pending.isEmpty {
                Self.logger.debug("No unembedded bookmarks — index up to date")
                return .success
            }

            // Accumulate all (id, bytes) pairs, then flush in a single transaction (perf-14). This
            // amortises persistence-flush overhead from O(N) to O(1).
            let batch = Array(pending.prefix(Self.maxPerRun))
            let total = batch.count
            var updates: [(String, Data)] = []
            for (index, bookmark) in batch.enumerated() {
                if isStopped() { break }
                try Task.checkCancellation()
                onProgress(index, total)
                guard let vector = await onDeviceEmbeddingProvider.embedDocument(bookmark) else {
                    continue
                }
                updates.append((bookmark.id, VectorSearch.floatArrayToData(vector)))
            }

            if !updates.isEmpty {
                await bookmarkRepository.updateEmbeddings(updates: updates)
                _ = await bookmarkRepository.organizeByEmbedding(userId: userId)
            }
            let done = updates.count
            Self.logger.debug("On-device indexed \(done, privacy: .public) of \(pending.count, privacy: .public) pending bookmarks")

            // More than one batch left → ask to run again next charging window (still on-device only).
            return pending.count > Self.maxPerRun ? .retry : .success
        } catch is CancellationError {
            // Android rethrows CancellationException so WorkManager re-queues; on iOS the work simply
            // resumes in the next self-resubmitted charging window.
            Self.logger.debug("Background indexing cancelled — will resume next window")
            return .retry
        } catch {
            // Model load failure or unrecoverable — don't loop forever.
            Self.logger.error("Unrecoverable error, giving up: \(error.localizedDescription, privacy: .public)")
            return .failure
        }
    }
}
