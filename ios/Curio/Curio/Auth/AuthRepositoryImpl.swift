import Foundation
import Combine
import os

/// Drives the X OAuth2 PKCE login flow and owns the `AuthState` session stream. Ports
/// `data/repo/AuthRepositoryImpl.kt`.
///
/// **State stream (CONVENTIONS §11):** Kotlin's `MutableStateFlow<AuthState>(SignedOut)` becomes a
/// `CurrentValueSubject<AuthState, Never>` seeded with `.signedOut`, exposed read-only via
/// `authState()` — it carries the current value and re-emits on every transition.
///
/// **Boot restore (off main):** Android restored the session in a `CoroutineScope(Dispatchers.IO)`
/// block because reading the encrypted token store is disk I/O + a Keystore decrypt that must not
/// stall the launch UI thread. Here a detached `Task` (the `TokenStore` actor already runs off the
/// main actor) reads `hasTokens()` + identity and publishes `.signedIn` / `.signedOut`, swallowing
/// any failure as `.signedOut` (matching the Kotlin `catch → SignedOut`).
///
/// **`beginLogin` URL construction is byte-faithful:** the authorize URL is built by the *same raw
/// string concatenation* as Android — host `twitter.com`, only the scope's spaces percent-encoded
/// (`%20`), `client_id` / `redirect_uri` / `state` / `code_challenge` interpolated verbatim. We do
/// NOT route this through `URLComponents` (which would re-encode the redirect URI and change the
/// bytes X validated). Scope string includes `offline.access` (Auth cross-cutting).
///
/// **`completeLogin` is the ONE auth path that throws** (CONVENTIONS §3): it collapses Kotlin
/// `Result<Unit>` to `async throws`. On failure it resets to `.signedOut` and rethrows, wrapping the
/// cause in `AuthError.exchangeFailed` so the UI gets a typed, localizable error.
///
/// `final class` (not `actor`) — its only mutable state is the thread-safe `CurrentValueSubject`;
/// `Sendable` because it crosses actor boundaries (it conforms to `AuthRepository: Sendable`).
final class AuthRepositoryImpl: AuthRepository, @unchecked Sendable {

    private static let logger = Logger(subsystem: "com.curio.app", category: "AuthRepo")

    /// X OAuth2 scope. Includes `offline.access` so a refresh token is issued (Auth cross-cutting).
    private static let scope = "tweet.read users.read bookmark.read offline.access"

    private let api: XAuthApi
    private let tokenStore: TokenStore
    private let webAuth: WebAuthSession?

    /// Backing session subject (initial `.signedOut`). `CurrentValueSubject` is thread-safe for
    /// `value` reads and `send`, so it is the actor-free analogue of `MutableStateFlow`.
    private let authStateSubject = CurrentValueSubject<AuthState, Never>(.signedOut)

    /// Retains the boot-restore task so it can be cancelled on teardown (avoids a publish after
    /// deinit).
    private var bootTask: Task<Void, Never>?

    /// - Parameters:
    ///   - api: the X OAuth token/identity client.
    ///   - tokenStore: the Keychain-backed secure store.
    ///   - webAuth: present for completeness/DI; the browser handoff itself is driven by the
    ///     presentation layer (`AuthViewModel` + `WebAuthSession`), mirroring how Android launched
    ///     the Custom Tab from the UI. Unused by the repository's own flow.
    init(api: XAuthApi, tokenStore: TokenStore, webAuth: WebAuthSession? = nil) {
        self.api = api
        self.tokenStore = tokenStore
        self.webAuth = webAuth
        startBootRestore()
    }

    deinit {
        bootTask?.cancel()
    }

    // MARK: - Boot restore

    /// Restores the session off the main actor at construction (Kotlin `init { scope.launch { … } }`
    /// on `Dispatchers.IO`).
    private func startBootRestore() {
        let tokenStore = self.tokenStore
        let subject = self.authStateSubject
        bootTask = Task.detached(priority: .utility) {
            let hasToken = await tokenStore.hasTokens()
            let userId = await tokenStore.getUserId()
            if hasToken, let userId {
                let username = await tokenStore.getUsername()
                let name = await tokenStore.getName()
                subject.send(.signedIn(userId: userId, username: username, name: name))
            } else {
                subject.send(.signedOut)
            }
        }
    }

    // MARK: - AuthRepository

    func authState() -> AnyPublisher<AuthState, Never> {
        authStateSubject.eraseToAnyPublisher()
    }

    /// Builds a fresh PKCE challenge + authorize URL. `async throws` mirrors the protocol (it can
    /// fail while resolving config / generating PKCE), though the body itself does not throw.
    func beginLogin() async throws -> AuthChallenge {
        let verifier = PKCE.makeCodeVerifier()
        let challenge = PKCE.codeChallengeS256(for: verifier)
        let state = UUID().uuidString

        let clientId = CurioConfig.clientID
        let redirectUri = CurioConfig.xRedirectURI
        let encodedScope = Self.scope.replacingOccurrences(of: " ", with: "%20")

        // Byte-faithful raw concatenation (matches Kotlin string-template build). Do NOT re-encode.
        let authUrl = "https://twitter.com/i/oauth2/authorize"
            + "?response_type=code"
            + "&client_id=\(clientId)"
            + "&redirect_uri=\(redirectUri)"
            + "&scope=\(encodedScope)"
            + "&state=\(state)"
            + "&code_challenge=\(challenge)"
            + "&code_challenge_method=S256"

        return AuthChallenge(
            authorizationUrl: authUrl,
            codeVerifier: verifier,
            state: state
        )
    }

    /// Exchanges the auth `code` (with the original `codeVerifier`) for tokens, fetches the user
    /// identity, persists everything, and publishes `.signedIn`. Throws `AuthError.exchangeFailed`
    /// on any failure (resetting to `.signedOut` first), collapsing Kotlin `Result<Unit>`.
    func completeLogin(code: String, codeVerifier: String) async throws {
        authStateSubject.send(.signingIn)
        let clientId = CurioConfig.clientID
        let redirectUri = CurioConfig.xRedirectURI

        do {
            let response = try await api.exchangeToken(
                grantType: "authorization_code",
                clientId: clientId,
                redirectUri: redirectUri,
                code: code,
                codeVerifier: codeVerifier
            )

            // Query profile to obtain the numeric user id and X handle.
            let userResponse = try await api.getUserMe(authorization: "Bearer \(response.accessToken)")
            let userId = userResponse.data.id
            let username = userResponse.data.username
            let name = userResponse.data.name

            await tokenStore.saveTokens(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                userId: userId,
                username: username,
                name: name
            )

            authStateSubject.send(.signedIn(userId: userId, username: username, name: name))
        } catch is CancellationError {
            // Cooperative cancellation must propagate, not collapse into a login error
            // (CONVENTIONS §4 "Never swallow CancellationError").
            authStateSubject.send(.signedOut)
            throw CancellationError()
        } catch {
            Self.logger.error("Token exchange failed")
            authStateSubject.send(.signedOut)
            throw AuthError.exchangeFailed(error)
        }
    }

    /// Resolves the currently active user's numeric ID. Plain `async` (no throws).
    func currentUserId() async -> String? {
        await tokenStore.getUserId()
    }

    /// Purges credentials and publishes `.signedOut`. Plain `async` (no throws).
    func logout() async {
        await tokenStore.clear()
        authStateSubject.send(.signedOut)
    }
}
