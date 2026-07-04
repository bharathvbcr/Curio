import Foundation

/// Per-domain auth errors (CONVENTIONS §3 "Error model — sealed enums").
///
/// There is no single Android equivalent: the Kotlin `AuthRepositoryImpl.completeLogin` collapsed
/// every failure into `Result.failure(e)` (the raw exception), and the PKCE redirect handling lived
/// in the Android Activity/Compose layer. On iOS the redirect arrives through
/// `ASWebAuthenticationSession`, so the discrete failure modes that the Android flow handled
/// implicitly (user-cancelled the browser sheet, the returned `state` did not match the CSRF token,
/// the redirect carried no `code`) are modelled here as typed cases. `exchangeFailed` wraps the
/// underlying networking/decoding error from the token-exchange call, preserving the Android
/// `Result.failure(e)` semantics — the cause is carried, not discarded.
///
/// `LocalizedError` because these surface to the UI / auth controller (CONVENTIONS §3: the
/// `completeLogin` path is the ONE auth path that propagates a typed failure to the UI).
enum AuthError: Error, LocalizedError, Sendable {
    /// The OAuth `state` returned on the redirect did not match the CSRF token we generated.
    case stateMismatch
    /// The user dismissed the `ASWebAuthenticationSession` browser sheet
    /// (`ASWebAuthenticationSessionError.canceledLogin`).
    case cancelled
    /// The redirect callback URL did not carry an authorization `code` (and no usable `error`).
    case missingCode
    /// The token exchange / identity lookup failed; carries the underlying cause.
    case exchangeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .stateMismatch:
            return "Login failed: security state mismatch. Please try again."
        case .cancelled:
            return "Login cancelled."
        case .missingCode:
            return "Login failed: no authorization code returned."
        case let .exchangeFailed(error):
            return "Login failed: \(error.localizedDescription)"
        }
    }
}
