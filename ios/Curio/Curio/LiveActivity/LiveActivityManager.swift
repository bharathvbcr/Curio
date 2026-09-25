import Foundation
import Observation
import os
#if os(iOS)
@preconcurrency import ActivityKit
#endif

/// Drives Curio's single unified Live Activity. Every background source (the BGTask coordinator's
/// sweep/index runs, the ViewModel's sync path, the digest controller) pushes coarse events here —
/// `taskStarted`/`taskProgress`/`taskFinished`/`digestReady`/`syncError` — and this manager reduces
/// them into one `CurioActivityAttributes.ContentState` and starts / updates / ends the ONE
/// `Activity`. This is the iOS twin of Android's `CurioActivityController`.
///
/// `@MainActor` so mutation is serialized (off-actor callers `await` in, so start/end never race).
/// `Activity.request` is synchronous, so a new activity is created inline on the main actor — two
/// interleaved reconciles can't double-start it. `update`/`end` are async and fire-and-forget.
#if os(iOS)
@MainActor
@Observable
final class LiveActivityManager {

    @ObservationIgnored private var activity: Activity<CurioActivityAttributes>?
    @ObservationIgnored private var content = CurioActivityAttributes.ContentState()
    @ObservationIgnored private var errorClearTask: Task<Void, Never>?

    @ObservationIgnored private static let logger =
        Logger(subsystem: "com.curio.app", category: "LiveActivity")
    @ObservationIgnored private static let errorLingerSeconds: UInt64 = 6

    init() {}

    // MARK: - Event API (mirrors CurioActivityController)

    func taskStarted(_ task: CurioActivityTask) { mutate { $0.taskStarted(task) } }

    func taskProgress(_ task: CurioActivityTask, done: Int, total: Int) {
        mutate { $0.taskProgress(task, done: done, total: total) }
    }

    func taskFinished(_ task: CurioActivityTask) { mutate { $0.taskFinished(task) } }

    func digestReady(itemCount: Int) { mutate { $0.withDigestReady(itemCount: itemCount) } }

    /// Surfaces a transient error, then auto-clears it after `errorLingerSeconds` so a one-off
    /// failure doesn't camp permanently on the Lock Screen. Any running tasks resume the headline.
    func syncError(_ message: String) {
        mutate { $0.withError(message) }
        errorClearTask?.cancel()
        errorClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.errorLingerSeconds))
            guard let self, !Task.isCancelled else { return }
            if case .error = self.content.attention { self.clearAttention() }
        }
    }

    /// Clears any pending attention (digest-ready / error). Call when the user opens the app.
    func clearAttention() { mutate { $0.clearedAttention() } }

    /// Ends the activity on app teardown.
    func close() {
        errorClearTask?.cancel()
        content = CurioActivityAttributes.ContentState()
        endActivity()
    }

    // MARK: - Reconcile

    private func mutate(_ transform: (CurioActivityAttributes.ContentState) -> CurioActivityAttributes.ContentState) {
        content = transform(content)
        reconcile()
    }

    private func reconcile() {
        if content.isEmpty {
            endActivity()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let current = activity {
            let state = content
            Task { await current.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            do {
                activity = try Activity.request(
                    attributes: CurioActivityAttributes(),
                    content: ActivityContent(state: content, staleDate: nil),
                    pushType: nil
                )
            } catch {
                Self.logger.error("Live Activity start failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func endActivity() {
        guard let current = activity else { return }
        activity = nil
        Task { await current.end(nil, dismissalPolicy: .immediate) }
    }
}
#else
/// No-op stand-in where ActivityKit is absent (native macOS). Call sites stay source-compatible.
@MainActor
@Observable
final class LiveActivityManager {
    func taskStarted(_ task: CurioActivityTask) {}
    func taskProgress(_ task: CurioActivityTask, done: Int, total: Int) {}
    func taskFinished(_ task: CurioActivityTask) {}
    func digestReady(itemCount: Int) {}
    func syncError(_ message: String) {}
    func clearAttention() {}
    func close() {}
}
#endif

/// One construction site for `LiveActivityManager`. The type is declared twice (ActivityKit
/// and the macOS no-op), so callers go through this name rather than picking a declaration.
@MainActor
enum LiveActivityManagers {
    static func make() -> LiveActivityManager { LiveActivityManager() }
}
