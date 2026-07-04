import Foundation

/// Repository-layer error glue. Ports the Android `RateLimitException` concept and the implicit
/// "sync failed" fall-through in `data/repo/BookmarkRepositoryImpl.kt`.
///
/// CONVENTIONS §3 ("Error model — sealed enums"): `RateLimitError` is the ONE typed failure the
/// Repository surfaces to the UI (besides `AuthRepository.completeLogin`). It is declared in the
/// Domain module (`Domain/CurioError.swift`) so it can cross module boundaries; this file re-exports
/// it for call-site clarity and adds the repository-local `SyncError` used as the final
/// `Result.failure(...)` fall-through value when no more specific error is available.
///
/// `RateLimitError.resetTimeSeconds` is kept here as a documented re-export alias — the canonical
/// type lives in Domain (`bug-24`: epoch seconds as `Int64`, never `Int`, to avoid 2038 overflow).
typealias RepositoryRateLimitError = RateLimitError

/// Repository-local sync failures. Mirrors the Kotlin `Result.failure(...)` paths that did not carry
/// a more specific cause.
///
/// In `syncBookmarks` the Kotlin code's final `else -> Result.failure(lastError ?: Exception("Sync
/// failed"))` collapses to: rethrow `lastError` when present, else throw `SyncError.failed`. The
/// `RateLimitError` 429 path and the X-authoritative `xSyncError` rethrow are handled directly in the
/// implementation (they carry their own typed error), so this enum only covers the generic
/// fall-through.
enum SyncError: Error, LocalizedError {
    /// The generic "Sync failed" fall-through (`lastError == nil`). Mirrors the Kotlin
    /// `Exception("Sync failed")` message verbatim for parity.
    case failed

    var errorDescription: String? {
        switch self {
        case .failed:
            return "Sync failed"
        }
    }
}
