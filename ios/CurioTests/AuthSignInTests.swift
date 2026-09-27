import Combine
import Foundation
import Testing
@testable import Curio

private final class FakeAuthRepository: AuthRepository, @unchecked Sendable {
    let subject = CurrentValueSubject<AuthState, Never>(.signedOut)
    var challenge = AuthChallenge(
        authorizationUrl: "https://twitter.com/i/oauth2/authorize?x=1",
        codeVerifier: "verifier",
        state: "state-1"
    )
    var completed = 0
    var completeError: Error?

    func authState() -> AnyPublisher<AuthState, Never> { subject.eraseToAnyPublisher() }
    func beginLogin() async throws -> AuthChallenge { challenge }
    func completeLogin(code: String, codeVerifier: String) async throws {
        completed += 1
        if let completeError { throw completeError }
        subject.send(.signedIn(userId: "user", username: "ada", name: "Ada"))
    }
    func currentUserId() async -> String? { nil }
    func logout() async { subject.send(.signedOut) }
}

@MainActor
private final class ScriptedWebAuth: WebAuthenticating {
    var result: Result<URL, Error> = .failure(AuthError.cancelled)
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try result.get()
    }
}

@MainActor
private final class BlockingWebAuth: WebAuthenticating {
    private var started: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<URL, Error>?
    private var didStart = false

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        didStart = true
        started?.resume()
        started = nil
        return try await withCheckedThrowingContinuation { pending = $0 }
    }

    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { started = $0 }
    }

    func succeed(_ url: URL) {
        pending?.resume(returning: url)
        pending = nil
    }
}

@MainActor
@Suite("Curio sign-in")
struct AuthSignInTests {

    private func viewModel(
        repo: FakeAuthRepository = FakeAuthRepository(),
        web: any WebAuthenticating
    ) -> AuthViewModel {
        AuthViewModel(
            loginUseCase: LoginUseCase(authRepository: repo),
            authRepository: repo,
            webAuthSession: web,
            callbackScheme: "curio-oauth"
        )
    }

    @Test("a browser failure is shown on the login screen")
    func browserFailureIsVisible() async {
        let web = ScriptedWebAuth()
        web.result = .failure(AuthError.presentationFailed)
        let vm = viewModel(web: web)
        await vm.performLogin()
        #expect(vm.loginError == AuthError.presentationFailed.errorDescription)
    }

    @Test("a state mismatch does not exchange the code")
    func stateMismatch() async {
        let repo = FakeAuthRepository()
        let web = ScriptedWebAuth()
        web.result = .success(URL(string: "curio-oauth://callback?code=abc&state=nope")!)
        let vm = viewModel(repo: repo, web: web)
        await vm.performLogin()
        #expect(repo.completed == 0)
        #expect(vm.loginError == AuthError.stateMismatch.errorDescription)
    }

    @Test("a code in the fragment still completes sign-in")
    func fragmentCode() async {
        let repo = FakeAuthRepository()
        let web = ScriptedWebAuth()
        web.result = .success(URL(string: "curio-oauth://callback#code=abc&state=state-1")!)
        let vm = viewModel(repo: repo, web: web)
        await vm.performLogin()
        #expect(repo.completed == 1)
        #expect(vm.loginError == nil)
    }

    @Test("the provider error is shown when the redirect has no code")
    func providerError() async {
        let web = ScriptedWebAuth()
        web.result = .success(URL(string: "curio-oauth://callback?error=access_denied")!)
        let vm = viewModel(web: web)
        await vm.performLogin()
        #expect(vm.loginError == "access_denied")
    }

    @Test("a failed token exchange is shown and does not stay signed in")
    func exchangeFailure() async {
        let repo = FakeAuthRepository()
        repo.completeError = TokenStoreError.keychain(-34018)
        let web = ScriptedWebAuth()
        web.result = .success(URL(string: "curio-oauth://callback?code=abc&state=state-1")!)
        let vm = viewModel(repo: repo, web: web)
        await vm.performLogin()
        #expect(vm.loginError?.contains("Keychain") == true)
        #expect(vm.authState == .signedOut)
    }

    @Test("a second sign-in does not start while the first browser session is open")
    func singleFlight() async {
        let repo = FakeAuthRepository()
        let web = BlockingWebAuth()
        let vm = viewModel(repo: repo, web: web)
        let first = Task { await vm.performLogin() }
        await web.waitUntilStarted()
        await vm.performLogin()
        #expect(vm.loginError == "Sign-in is already in progress.")
        web.succeed(URL(string: "curio-oauth://callback?code=abc&state=state-1")!)
        await first.value
        #expect(repo.completed == 1)
    }

    @Test("oauth callback fields accept the query and the fragment")
    func callbackFields() {
        let query = OAuthCallback.fields(in: URL(string: "curio-oauth://callback?code=a&state=s")!)
        #expect(query.code == "a")
        #expect(query.state == "s")
        let fragment = OAuthCallback.fields(in: URL(string: "curio-oauth://callback#code=frag&state=s2")!)
        #expect(fragment.code == "frag")
        #expect(fragment.state == "s2")
        let blank = OAuthCallback.fields(in: URL(string: "curio-oauth://callback?code=%20&error=nope")!)
        #expect(blank.code == nil)
        #expect(blank.error == "nope")
    }

    @Test("a boot restore does not publish after login has started")
    func bootEpoch() {
        let epoch = AuthSessionEpoch()
        let snapshot = epoch.snapshot()
        #expect(epoch.unchanged(snapshot))
        epoch.bump()
        #expect(epoch.unchanged(snapshot) == false)
    }

    @Test("a keychain failure is an error and success is not")
    func keychainStatus() throws {
        try KeychainWrite.requireSuccess(errSecSuccess)
        #expect(throws: TokenStoreError.self) {
            try KeychainWrite.requireSuccess(-34018)
        }
    }

    @Test("mac sign-in does not request an ephemeral browser session")
    func ephemeralPolicy() {
        #expect(AuthBrowserPolicy.prefersEphemeral(onMac: true) == false)
        #expect(AuthBrowserPolicy.prefersEphemeral(onMac: false))
    }

    @Test("the presentation anchor skips a hidden key window")
    func visibleAnchor() {
        struct Window: Equatable { let name: String }
        let hidden = Window(name: "hidden")
        let visible = Window(name: "desk")
        let chosen = AuthWindowChoice.visibleWindow(key: hidden, windows: [hidden, visible]) { $0.name == "desk" }
        #expect(chosen == visible)
        let none = AuthWindowChoice.visibleWindow(key: hidden, windows: [hidden]) { _ in false }
        #expect(none == nil)
    }

    @Test("only the first callback is allowed to resume")
    func onceFlag() {
        let gate = OnceFlag()
        #expect(gate.claim())
        #expect(gate.claim() == false)
    }

    @Test("placeholder oauth values are not sent to X")
    func oauthPlaceholder() {
        #expect(OAuthSecret.usable("$(CLIENT_ID)") == nil)
        #expect(OAuthSecret.usable("ROTATE_ME") == nil)
        #expect(OAuthSecret.usable("  ") == nil)
        #expect(OAuthSecret.usable("real-client") == "real-client")
        #expect(OAuthSecret.resolveClientID(local: nil, env: "from-env", baked: "baked") == "from-env")
        #expect(OAuthSecret.resolveClientID(local: "from-local", env: "from-env", baked: "baked") == "from-local")
        #expect(OAuthSecret.resolveClientID(local: "ROTATE_ME", env: nil, baked: "baked") == "baked")
    }

    @Test("the browser callback can resume from a background queue")
    func callbackResumesOffMainThread() async throws {
        let gate = CallbackResume<Int>()
        let value = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            gate.store(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                gate.resume(.success(7))
                gate.resume(.success(9))
            }
        }
        #expect(value == 7)
        let interpreted = await Task.detached {
            AuthCallback.interpret(url: URL(string: "curio-oauth://callback?code=1"), error: nil)
        }.value
        if case .success(let url) = interpreted {
            #expect(url.host == "callback")
        } else {
            Issue.record("callback interpretation failed off the main actor")
        }
    }
}
