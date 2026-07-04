import Foundation
import BackgroundTasks
import os

/// Schedules and routes Curio's background maintenance jobs.
///
/// Ports `object EmbeddingIndexScheduler` from `background/EmbeddingIndexScheduler.kt` and the
/// scheduling/lifecycle half of `BookmarkSweeperScheduler`/`BookmarkSweeperWorker` (the work itself lives in `LinkSweeper` /
/// `EmbeddingIndexer`).
///
/// Android used **WorkManager**: a `PeriodicWorkRequest` with a `setRequiresCharging` constraint for
/// the on-device embedding backfill, plus a foreground `Service` looping every 6h for the link sweep.
/// iOS has neither true periodic work nor an indefinite foreground service, so per DESIGN
/// §"WorkManager"/§"Foreground Service" and CONVENTIONS §9 ("BGTask") this maps to
/// **`BGTaskScheduler`**:
///
/// - Each job is a `BGProcessingTaskRequest`. There is no OS-managed interval, so each handler
///   **self-resubmits** (`earliestBeginDate = now + 6h`) at the end of its run. Because
///   `BGTaskScheduler` de-dupes pending requests by identifier, re-submitting the same identifier on
///   every launch leaves an already-pending request unchanged — reproducing WorkManager's
///   `ExistingPeriodicWorkPolicy.KEEP` semantics (perf-12: never reset the OS-managed timer on a
///   frequent-launch app).
/// - The embedding backfill carries `requiresExternalPower = true` (charging) — the direct analogue
///   of `setRequiresCharging(true)` — and is **gated by a persisted user preference**
///   (`index_while_charging`, default on), mirroring `EmbeddingIndexScheduler.isEnabled`.
/// - The link sweep carries `requiresNetworkConnectivity = true` (it issues HEAD requests).
/// - "Run now" (`runNow`) is an **immediate detached `Task`**, not a BGTask submission — matching the
///   Kotlin `OneTimeWorkRequest` `REPLACE` "build the index now" affordance. Still on-device only.
///
/// `expirationHandler` is always wired first and `setTaskCompleted(success:)` is called exactly once
/// per run (CONVENTIONS §9).
///
/// PRIVACY RULE (CONVENTIONS §9, load-bearing): background work is offline maintenance only — the link
/// sweep (no third-party content processing) and the **on-device-only** embedding backfill. No cloud
/// AI / cloud embedder ever runs here.
@MainActor
final class BackgroundTaskCoordinator {

    // MARK: - Task identifiers (must also appear in Info.plist `BGTaskSchedulerPermittedIdentifiers`)

    enum TaskID {
        /// Charging-gated on-device embedding backfill (Android `embedding-index-periodic`).
        static let embeddingIndex = "com.curio.app.embedding-index"
        /// 404/410 stale-link sweep (Android `BookmarkSweeperWorker`).
        static let linkSweep = "com.curio.app.link-sweep"
    }

    // MARK: - Preference storage (mirrors Android SharedPreferences "curio_embedding_prefs")

    private enum Prefs {
        /// UserDefaults key for the charging-time indexing toggle. Mirrors Android
        /// `KEY_ENABLED = "index_while_charging"`.
        static let indexWhileChargingKey = "index_while_charging"
    }

    // MARK: - Scheduling cadence

    /// Re-arm window for both jobs. Mirrors the 6h WorkManager period / sweeper loop delay.
    private nonisolated static let intervalSeconds: TimeInterval = 6 * 60 * 60

    // `nonisolated(unsafe)`: `UserDefaults` is thread-safe but not formally `Sendable`; read by the
    // off-main BGTask handlers.
    private nonisolated(unsafe) let defaults: UserDefaults
    private let indexer: EmbeddingIndexer
    private let sweeper: LinkSweeper
    /// Surfaces sweep/index runs in Curio's single unified Live Activity. Shared with the app graph.
    private let liveActivityManager: LiveActivityManager
    private nonisolated static let logger = Logger(subsystem: "com.curio.app", category: "BackgroundTasks")

    /// Tracks immediate "run now" work so it can be cancelled on teardown.
    private var runNowTask: Task<Void, Never>?

    init(
        indexer: EmbeddingIndexer,
        sweeper: LinkSweeper,
        liveActivityManager: LiveActivityManager,
        defaults: UserDefaults = .standard
    ) {
        self.indexer = indexer
        self.sweeper = sweeper
        self.liveActivityManager = liveActivityManager
        self.defaults = defaults
        // Default the charging-index preference to ON the first time, matching Android
        // `getBoolean(KEY_ENABLED, true)`.
        if defaults.object(forKey: Prefs.indexWhileChargingKey) == nil {
            defaults.set(true, forKey: Prefs.indexWhileChargingKey)
        }
    }

    // MARK: - Registration (call once, before app finishes launching)

    /// Registers the BGTask handlers. Must be called from `application(_:didFinishLaunchingWithOptions:)`
    /// / `CurioApp.init` **before** the app finishes launching, per `BGTaskScheduler` contract.
    /// Idempotent registration is the caller's responsibility (register exactly once per identifier).
    func registerHandlers() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: TaskID.embeddingIndex,
            using: nil
        ) { [weak self] task in
            guard let self, let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: true)
                return
            }
            // The handler is `nonisolated`; it captures only `Sendable` actor deps + `UserDefaults`,
            // never hopping the non-Sendable `BGTask` across an isolation boundary.
            self.handleEmbeddingIndex(processingTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: TaskID.linkSweep,
            using: nil
        ) { [weak self] task in
            guard let self, let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: true)
                return
            }
            self.handleLinkSweep(processingTask)
        }
    }

    // MARK: - Scheduling

    /// Registers the charging-gated embedding backfill if the preference is enabled, plus the link
    /// sweep. Safe to call on every app start — `BGTaskScheduler` de-dupes pending requests by
    /// identifier, so an already-pending request is left unchanged (WorkManager `KEEP` semantics).
    /// Mirrors `EmbeddingIndexScheduler.ensureScheduled` + the sweeper's own startup scheduling.
    func ensureScheduled() {
        if isIndexWhileChargingEnabled() {
            scheduleEmbeddingIndex()
        }
        scheduleLinkSweep()
    }

    /// Whether charging-time on-device indexing is enabled. Defaults to on. Mirrors
    /// `EmbeddingIndexScheduler.isEnabled`. `nonisolated` so the BGTask handler (which runs off the
    /// main actor) can read it; backed by thread-safe `UserDefaults`.
    nonisolated func isIndexWhileChargingEnabled() -> Bool {
        // `object(forKey:)` distinguishes "unset" (→ default true) from an explicit false.
        guard defaults.object(forKey: Prefs.indexWhileChargingKey) != nil else { return true }
        return defaults.bool(forKey: Prefs.indexWhileChargingKey)
    }

    /// Enables/disables the charging-time on-device indexing job, persisting the choice so it survives
    /// relaunch. Mirrors `EmbeddingIndexScheduler.setEnabled`: persists, then schedules or cancels the
    /// periodic job.
    func setIndexWhileChargingEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Prefs.indexWhileChargingKey)
        if enabled {
            scheduleEmbeddingIndex()
        } else {
            cancelEmbeddingIndex()
        }
    }

    /// Submits the charging-gated embedding backfill. Re-submitting the same identifier while a request
    /// is already pending is a no-op (KEEP). Mirrors `EmbeddingIndexScheduler.schedulePeriodic`.
    /// `nonisolated` so the off-main BGTask handler can re-arm it.
    private nonisolated func scheduleEmbeddingIndex() {
        let request = BGProcessingTaskRequest(identifier: TaskID.embeddingIndex)
        // Direct analogue of `setRequiresCharging(true)`.
        request.requiresExternalPower = true
        // EmbeddingGemma inference is local-only; no network needed.
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.intervalSeconds)
        submit(request)
    }

    /// Submits the periodic link sweep (needs network for HEAD requests). `nonisolated` so the off-main
    /// BGTask handler can re-arm it.
    private nonisolated func scheduleLinkSweep() {
        let request = BGProcessingTaskRequest(identifier: TaskID.linkSweep)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.intervalSeconds)
        submit(request)
    }

    private nonisolated func submit(_ request: BGProcessingTaskRequest) {
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // A duplicate-pending submit (or an unavailable scheduler in the simulator) is not fatal —
            // the existing pending request stands (KEEP). Never logs secrets.
            Self.logger.debug(
                "BGTask submit skipped for \(request.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Cancels the pending charging-gated embedding backfill. Mirrors
    /// `EmbeddingIndexScheduler.cancelPeriodic`.
    private nonisolated func cancelEmbeddingIndex() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: TaskID.embeddingIndex)
    }

    // MARK: - Run now (explicit user action — immediate, no charging constraint)

    /// Fires a one-off on-device backfill immediately (no charging constraint) for an explicit user
    /// action like "build the index now" right after downloading the model. Replaces the prior pending
    /// run-now task (REPLACE). Still on-device only. Mirrors `EmbeddingIndexScheduler.runNow`.
    func runNow() {
        runNowTask?.cancel()
        let indexer = self.indexer
        let manager = self.liveActivityManager
        runNowTask = Task.detached(priority: .utility) {
            await manager.taskStarted(.index)
            // `isStopped` for the immediate path is driven purely by task cancellation.
            _ = await indexer.run(
                isStopped: { Task.isCancelled },
                onProgress: { done, total in
                    Task { @MainActor in manager.taskProgress(.index, done: done, total: total) }
                }
            )
            await manager.taskFinished(.index)
        }
    }

    // MARK: - Handlers

    /// BGTask handler for the charging-gated embedding backfill. Wires `expirationHandler` first, runs
    /// the indexer, then self-resubmits (+6h) and reports completion exactly once.
    ///
    /// `nonisolated`: the BGTask launch handler runs on a `BGTaskScheduler`-owned (non-main) queue.
    /// The non-Sendable `BGProcessingTask` is bridged into the completion `Task` via a
    /// `TaskBox` (`@unchecked Sendable`) so it never crosses an isolation boundary unsafely — the box
    /// is only ever touched from the single completion continuation.
    private nonisolated func handleEmbeddingIndex(_ task: BGProcessingTask) {
        // Re-arm the next occurrence before doing the work, mirroring WorkManager's OS-managed
        // periodic re-queue (and ensuring we re-arm even if the run is expired early).
        if isIndexWhileChargingEnabled() {
            scheduleEmbeddingIndex()
        }

        let indexer = self.indexer
        let manager = self.liveActivityManager
        let work = Task.detached(priority: .utility) { () -> EmbeddingIndexer.IndexResult in
            await manager.taskStarted(.index)
            // The worker `Result` (success/retry/failure) collapses to a Bool here: BGTask has no
            // "retry" — re-running is governed by the self-resubmitted periodic request above.
            let outcome = await indexer.run(
                isStopped: { Task.isCancelled },
                onProgress: { done, total in
                    Task { @MainActor in manager.taskProgress(.index, done: done, total: total) }
                }
            )
            await manager.taskFinished(.index)
            return outcome
        }

        // `expirationHandler` must be set first; cancel the work (CONVENTIONS §9).
        task.expirationHandler = {
            work.cancel()
        }

        let box = TaskBox(task)
        Task.detached(priority: .utility) {
            let outcome = await work.value
            box.task.setTaskCompleted(success: outcome != .failure)
        }
    }

    /// BGTask handler for the 404/410 link sweep. One bounded cycle per run (the Android service looped
    /// forever with a 6h delay; iOS re-arms via self-resubmit instead). `nonisolated` for the same
    /// reason as `handleEmbeddingIndex`.
    private nonisolated func handleLinkSweep(_ task: BGProcessingTask) {
        scheduleLinkSweep()

        let sweeper = self.sweeper
        let manager = self.liveActivityManager
        let work = Task.detached(priority: .utility) {
            await manager.taskStarted(.sweep)
            await sweeper.runOneCycle(
                isStopped: { Task.isCancelled },
                onProgress: { done, total in
                    Task { @MainActor in manager.taskProgress(.sweep, done: done, total: total) }
                }
            )
            await manager.taskFinished(.sweep)
        }

        task.expirationHandler = {
            work.cancel()
        }

        let box = TaskBox(task)
        Task.detached(priority: .utility) {
            await work.value
            // The sweep is best-effort maintenance; a partial cycle is still a successful run.
            box.task.setTaskCompleted(success: true)
        }
    }

    // MARK: - Teardown

    /// Cancels any in-flight "run now" work. Called from the app's scene teardown / `AppEnvironment`
    /// close, mirroring the Android service `onDestroy` / scope cancellation.
    func close() {
        runNowTask?.cancel()
        runNowTask = nil
    }

    deinit {
        runNowTask?.cancel()
    }
}

/// Bridges a non-`Sendable` `BGTask` into the single async completion continuation that reports it
/// complete. The boxed task is set up on the handler queue and read exactly once from the completion
/// `Task`, so the `@unchecked Sendable` is sound (there is no concurrent access to the underlying
/// system object). This mirrors WorkManager handing the `Worker`'s `Result` back on completion.
private struct TaskBox: @unchecked Sendable {
    let task: BGProcessingTask
    init(_ task: BGProcessingTask) { self.task = task }
}
