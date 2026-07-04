import Foundation

/// Orchestrates login actions and session handshakes for the presentation layer. Ports
/// `class LoginUseCase` from `domain/usecase/LoginUseCase.kt`.
///
/// A stateless pass-through to `AuthRepository` (kept trivial for easy mocking — CONVENTIONS §12).
/// `Sendable` since it holds only a `Sendable` repository reference.
struct LoginUseCase: Sendable {
    private let authRepository: AuthRepository

    init(authRepository: AuthRepository) {
        self.authRepository = authRepository
    }

    /// Prepares the authentication challenge to kickstart the login sheet.
    func beginLogin() async throws -> AuthChallenge {
        try await authRepository.beginLogin()
    }

    /// Executes the official endpoint code-resolution handshake. Throws on failure (collapses the
    /// Kotlin `Result<Unit>`).
    func completeLogin(code: String, codeVerifier: String) async throws {
        try await authRepository.completeLogin(code: code, codeVerifier: codeVerifier)
    }
}
