import Foundation

/// Core authentication states for Curio. Ports `sealed interface AuthState` from
/// `domain/model/Models.kt`.
///
/// Kotlin's `object SignedOut` / `object SigningIn` become caseless states; `data class SignedIn`
/// becomes a case with associated values. `username`/`name` default to `nil`, mirroring the Kotlin
/// constructor defaults. `Equatable` lets `@Observable`/Combine pipelines de-dupe emissions.
enum AuthState: Equatable, Sendable {
    case signedOut
    case signingIn
    case signedIn(userId: String, username: String? = nil, name: String? = nil)
}

/// Representation of OAuth PKCE authorization details. Ports `data class AuthChallenge`.
///
/// `authorizationUrl` is the fully-built X authorize URL, `codeVerifier` is the PKCE verifier kept
/// to redeem the auth code, and `state` is the CSRF token validated on redirect.
struct AuthChallenge: Sendable, Equatable {
    let authorizationUrl: String
    let codeVerifier: String
    let state: String

    init(authorizationUrl: String, codeVerifier: String, state: String) {
        self.authorizationUrl = authorizationUrl
        self.codeVerifier = codeVerifier
        self.state = state
    }
}

// Note (carried over from Models.kt): typed error handling lives in the layers that surface it —
// `RateLimitError` (see CurioError.swift, used by the Repository) and the sealed UI states
// (SyncUiState/AnalysisUiState/DigestUiState, defined in the Platform layer). No `AppError`
// hierarchy is defined here, matching the Android decision to avoid dead, drifting code.
