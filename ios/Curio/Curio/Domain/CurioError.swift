import Foundation

/// Root sealed error for Curio (CONVENTIONS §3 "Error model — sealed enums"). New file; there is no
/// single Android equivalent — the Android app used per-layer exceptions and sealed UI states. This
/// consolidates the cross-domain glue while per-domain enums (`AuthError`, `APIError`, `SyncError`,
/// `NanoUnavailable`, …) live in their own modules.
enum CurioError: Error {
    /// No signed-in user — a guarded operation was attempted without a session.
    case notSignedIn
    /// A decoding failure wrapping the underlying error.
    case decoding(Error)
    /// Catch-all wrapping an optional underlying cause.
    case unknown(Error?)
}

/// X rate-limit signal. Ports the Android `RateLimitException` concept (referenced by the Repository
/// and surfaced to the UI as a countdown — CONVENTIONS §3, §4).
///
/// `resetTimeSeconds` is the **seconds remaining** until the window resets, kept as `Int64` (not
/// `Int`) to avoid overflow. The Repository derives it from the `x-rate-limit-reset` header: an
/// absolute-epoch value (`> 1_000_000`) becomes the remaining delta, a small value is taken as
/// already-relative, with a `900`-second fallback (see the Repository's rate-limit header parsing).
struct RateLimitError: Error, Equatable {
    let resetTimeSeconds: Int64

    init(resetTimeSeconds: Int64) {
        self.resetTimeSeconds = resetTimeSeconds
    }
}

extension RateLimitError: LocalizedError {
    var errorDescription: String? {
        "Rate limited. Resets at \(resetTimeSeconds)s."
    }
}
