import Foundation
import Combine

/// Interface safeguarding X OAuth 2.0 PKCE authentication lifecycle and session credentials. Ports
/// `interface AuthRepository` from `domain/repo/AuthRepository.kt`.
///
/// Concurrency mapping (CONVENTIONS §3 / §11):
/// - Kotlin hot `Flow<AuthState>` → Combine `AnyPublisher<AuthState, Never>` (re-emits on every
///   session change; backed by a `CurrentValueSubject` in the impl).
/// - `suspend fun beginLogin(): AuthChallenge` → `async throws` (it can fail while building the
///   challenge / generating PKCE).
/// - `suspend fun completeLogin(...): Result<Unit>` → `async throws` (the one auth path that
///   surfaces a typed failure to the UI — see CONVENTIONS §"Resilience contract").
/// - plain `suspend fun currentUserId(): String?` → `async` (NO throws).
/// - plain `suspend fun logout()` → `async` (NO throws).
///
/// `Sendable` because the repository is used across actor boundaries.
protocol AuthRepository: Sendable {
    /// Observable stream representing current authentication credentials and session status.
    func authState() -> AnyPublisher<AuthState, Never>

    /// Initializes a PKCE challenge, returning details required for launching the login sheet.
    func beginLogin() async throws -> AuthChallenge

    /// Exchanges the auth code using the original code verifier from the previous flow.
    /// Throws on failure (collapses Kotlin `Result<Unit>`).
    func completeLogin(code: String, codeVerifier: String) async throws

    /// Resolves the currently active user's numeric ID (for retrieving bookmarks safely).
    func currentUserId() async -> String?

    /// Purges auth credentials silently, notifying all sessions.
    func logout() async
}
