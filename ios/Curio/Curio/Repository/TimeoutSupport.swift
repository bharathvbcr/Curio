import Foundation

/// Bounded-call helper. Ports Kotlin `withTimeoutOrNull(ms) { … }` from
/// `data/repo/BookmarkRepositoryImpl.kt` (used to cap the Firebase pull/push at
/// `FIREBASE_TIMEOUT_MS = 15_000`).
///
/// CONVENTIONS §5 ("Bounded calls"): races the operation against a `Task.sleep` inside a
/// `withThrowingTaskGroup`. Whichever finishes first wins; the loser is cancelled. On timeout (the
/// sleep wins) it returns `nil` — **never** a hard failure — exactly like `withTimeoutOrNull`. A
/// timed-out Firebase mirror must never mask a real X error (X-authoritative precedence).
///
/// Semantics preserved from the Kotlin coroutine builder:
/// - **Result on completion:** the operation's value (which may itself be `nil` when `T` is
///   optional — e.g. `pullBookmarks` returns `[Bookmark]`, but the wrapper's own `nil` distinctly
///   signals *timeout*, matching how the caller checks `cloudBookmarks == null`).
/// - **Timeout → `nil`** and the operation's `Task` is cancelled cooperatively.
/// - **Cancellation propagation:** if the surrounding task is cancelled, the group throwing
///   `CancellationError` propagates out (the Kotlin builder is likewise cancellable). We rethrow
///   cancellation rather than swallow it (CONVENTIONS §4 "Never swallow `CancellationError`").
/// - **Operation error:** if the operation itself throws a non-cancellation error, the Kotlin
///   `withTimeoutOrNull` would propagate it. Here, because every wrapped call (the resilient
///   `FirebaseSyncManager` ops) is itself non-throwing, this path is not exercised; should a wrapped
///   op throw, the error propagates out of `withTimeout` to the caller's surrounding `try`/`catch`.
///
/// - Parameters:
///   - milliseconds: the timeout budget in milliseconds (`Int64`, mirroring the Kotlin `Long`).
///   - operation: the async work to bound. Marked `@Sendable` so it can run in a child task under
///     Swift 6 strict concurrency.
/// - Returns: the operation's value, or `nil` on timeout.
func withTimeout<T: Sendable>(
    _ milliseconds: Int64,
    _ operation: @Sendable @escaping () async throws -> T
) async throws -> T? {
    // A non-positive budget degrades to "run unbounded" the same way Kotlin's
    // withTimeoutOrNull(<=0) would immediately time out; we guard the obvious zero case by simply
    // racing — Task.sleep(0) resolves promptly, so a 0ms budget effectively yields nil. Keeping the
    // race uniform avoids a special-case branch the Android code never had (it always passed 15s).
    try await withThrowingTaskGroup(of: TimeoutRace<T>.self) { group in
        group.addTask {
            let value = try await operation()
            return .value(value)
        }
        group.addTask {
            // Nanoseconds = milliseconds * 1_000_000. `Task.sleep` throws `CancellationError` when
            // the child is cancelled (the operation finished first) — caught below as the losing
            // branch, never surfaced.
            try? await Task.sleep(nanoseconds: UInt64(max(0, milliseconds)) * 1_000_000)
            return .timeout
        }

        defer { group.cancelAll() }

        // The first child to finish decides the outcome. Because the sleep child swallows its own
        // cancellation (`try?`), the only error that can be thrown here is from `operation()` (a real
        // failure) or a propagated outer cancellation — both correctly surface to the caller.
        while let result = try await group.next() {
            switch result {
            case .value(let value):
                return value
            case .timeout:
                return nil
            }
        }
        return nil
    }
}

/// The two outcomes a `withTimeout` child task can produce: the operation's value, or the timeout
/// sentinel. Generic over `T` and `Sendable` so it can cross the task-group boundary.
private enum TimeoutRace<T: Sendable>: Sendable {
    case value(T)
    case timeout
}
