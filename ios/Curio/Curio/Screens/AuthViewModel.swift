//
//  AuthViewModel.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/screens/auth/AuthViewModel.kt
//         (AuthViewModel — active-session state + PKCE login/redirect/logout).
//
//  DESIGN §10 (Screens): `@MainActor @Observable final class AuthViewModel`; `authState` fed by the
//  AuthRepository publisher; `onLoginClick` builds the PKCE challenge → drives the browser handoff;
//  `handleRedirect` (extract code/state/error, validate state) → `completeLogin`; `onLogout`.
//
//  CONVENTIONS mapping:
//  - §4 "@MainActor/@Observable": the Android `ViewModel` (StateFlow) becomes a
//    `@MainActor @Observable final class`; `authState` is a plain stored `var` auto-tracked by
//    Observation, kept current by a Combine subscription to `AuthRepository.authState()`. The Kotlin
//    `stateIn(WhileSubscribed(5000), initial = SignedOut)` collapses to: seed `.signedOut`, subscribe
//    eagerly for the VM lifetime (the VM is owned by the app scene, so there is always exactly one
//    "subscriber" — the WhileSubscribed window is moot, CONVENTIONS §11).
//  - §4 "Async pattern": every `viewModelScope.launch` → `Task { … }` on the main actor; the heavy
//    token exchange runs inside the actor-isolated `AuthRepositoryImpl`/`XAuthApiClient` and resolves
//    back on the main actor.
//  - §3 "Resilience contract": `completeLogin` is the ONE auth path that surfaces a typed failure to
//    the UI (it `throws`); the redirect handler maps every failure mode to the typed `AuthError`
//    cases and reports them through the `Result` callback, exactly mirroring the Android
//    `onResult(Result.failure(Exception(...)))` shape.
//  - §8 / DESIGN "ASWebAuthenticationSession": on Android the authorize URL opened in a Custom Tab and
//    the redirect re-entered via an Activity intent the VM parsed with `Uri.getQueryParameter`. On iOS
//    the whole browser round-trip is owned by `ASWebAuthenticationSession` (wrapped in
//    `WebAuthSession`): `onLoginClick` builds the challenge, launches the session, and on the callback
//    `URL` it runs the SAME redirect-handling logic the Android `handleRedirect` did (extract
//    `code`/`state`/`error`, validate the CSRF `state` against the stored challenge, then exchange).
//    CSRF validation therefore stays in the presentation layer (Auth cross-cutting requirement).
//
//  The Android `AuthViewModel.Factory` (manual `ViewModelProvider.Factory`) has no iOS analogue — the
//  VM is built by `AppEnvironment.makeAuthViewModel()` (CONVENTIONS §2 DI), so it is intentionally
//  dropped.
//

import Foundation
import Combine
import Observation
import os
#if canImport(UIKit)
import UIKit
#endif

/// Handles active session states and PKCE code-exchange redirects. Direct port of
/// `class AuthViewModel(loginUseCase, authRepository) : ViewModel()`.
@MainActor
@Observable
final class AuthViewModel {

    // MARK: - Injected dependencies (CONVENTIONS §2 constructor injection)

    @ObservationIgnored private let loginUseCase: LoginUseCase
    @ObservationIgnored private let authRepository: AuthRepository

    /// The browser-handoff driver (`ASWebAuthenticationSession` wrapper). Replaces the Android
    /// Custom-Tabs launch + intent-redirect plumbing. Owned by the VM so the session stays strongly
    /// retained for the duration of the round-trip.
    @ObservationIgnored private let webAuthSession: any WebAuthenticating

    /// The OAuth callback URL scheme registered for `ASWebAuthenticationSession`
    /// (the scheme component of `CurioConfig.xRedirectURI`, e.g. `curio-oauth`).
    @ObservationIgnored private let callbackScheme: String

    @ObservationIgnored private static let logger = Logger(subsystem: "com.curio.app", category: "AuthVM")

    // MARK: - PKCE challenge (kept to redeem the code)

    /// The active PKCE challenge from the most recent `onLoginClick`. Validated against the redirect
    /// `state` (CSRF) and supplies the `codeVerifier` for the token exchange. Port of
    /// `private var activeChallenge: AuthChallenge?`.
    ///
    /// (The Android TODO sec-5 about persisting this to `SavedStateHandle` to survive process death
    /// is carried over conceptually: on iOS the same caveat applies — a cold relaunch mid-flow loses
    /// the in-memory challenge and the user re-initiates login. No persistence is added here, matching
    /// the Android behaviour exactly.)
    @ObservationIgnored private var activeChallenge: AuthChallenge?
    @ObservationIgnored private var signingInFlight = false

    // MARK: - Observable auth state (Kotlin `StateFlow<AuthState>`)

    /// Current authentication state. Seeded `.signedOut` and kept current by a Combine subscription to
    /// `AuthRepository.authState()`. Port of `val authState: StateFlow<AuthState>`.
    private(set) var authState: AuthState = .signedOut

    /// Subscription to the repository's auth-state publisher; cancelled on teardown.
    @ObservationIgnored private var authStateCancellable: AnyCancellable?

    // MARK: - Init

    init(
        loginUseCase: LoginUseCase,
        authRepository: AuthRepository,
        webAuthSession: any WebAuthenticating = WebAuthSession(),
        callbackScheme: String = CurioConfig.callbackScheme
    ) {
        self.loginUseCase = loginUseCase
        self.authRepository = authRepository
        self.webAuthSession = webAuthSession
        self.callbackScheme = callbackScheme

        // Eagerly mirror the repository's auth state for the VM lifetime (the WhileSubscribed(5000)
        // window is moot — the VM is owned by the app scene, so there is always one subscriber).
        authStateCancellable = authRepository.authState()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.authState = state }
    }

    // MARK: - Login (browser handoff)

    /// Inline login failure message surfaced in `LoginView` (replaces Toast-only feedback).
    private(set) var loginError: String? = nil

    /// One-shot success banner shown on the feed after OAuth completes.
    private(set) var loginSuccessMessage: String? = nil

    func clearLoginError() {
        loginError = nil
    }

    func reportLoginSuccess() {
        loginSuccessMessage = "Logged in successfully to X!"
    }

    func clearLoginSuccess() {
        loginSuccessMessage = nil
    }

    func reportLoginFailure(_ message: String) {
        loginError = message
    }

    /// Prepares PKCE parameters and drives the `ASWebAuthenticationSession` browser handoff, then runs
    /// the redirect-handling logic on the returned callback URL.
    ///
    /// Port of `onLoginClick(onLaunchBrowser)`: the Android VM built the challenge and handed the
    /// authorize URL to the Activity to open in a Custom Tab, with the redirect re-entering through
    /// `handleRedirect`. On iOS `ASWebAuthenticationSession` owns the whole round-trip, so this method
    /// both launches it and processes the callback — the optional `onResult` reports the final outcome
    /// (the same `Result<Unit>` the Android flow surfaced), defaulting to a no-op for the common UI
    /// call site that only watches `authState`.
    ///
    /// A second click while a browser session is open does not start another one.
    /// Every failure is written to `loginError` so the login screen can show it.
    func onLoginClick(onResult: @escaping @MainActor (Result<Void, Error>) -> Void = { _ in }) {
        Task { [weak self] in
            await self?.performLogin(onResult: onResult)
        }
    }

    func performLogin(onResult: @escaping @MainActor (Result<Void, Error>) -> Void = { _ in }) async {
        if signingInFlight {
            fail(AuthErrorMessage("Sign-in is already in progress."), onResult: onResult)
            return
        }
        signingInFlight = true
        defer { signingInFlight = false }

        loginError = nil
        let challenge: AuthChallenge
        do {
            challenge = try await loginUseCase.beginLogin()
            activeChallenge = challenge
        } catch is CancellationError {
            return
        } catch {
            Self.logger.error("Failed to construct PKCE login redirect URL")
            fail(AuthErrorMessage("Could not start sign-in. Check your connection and try again."), onResult: onResult)
            return
        }

        guard let url = URL(string: challenge.authorizationUrl) else {
            fail(AuthError.presentationFailed, onResult: onResult)
            return
        }

        let callbackURL: URL
        do {
            callbackURL = try await webAuthSession.authenticate(
                url: url,
                callbackScheme: callbackScheme
            )
        } catch is CancellationError {
            return
        } catch {
            Self.logger.error("Sign-in browser handoff failed")
            fail(error, onResult: onResult)
            return
        }

        await handleRedirect(callbackURL, onResult: onResult)
    }

    private func fail(_ error: Error, onResult: @escaping @MainActor (Result<Void, Error>) -> Void) {
        loginError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        onResult(.failure(error))
    }

    // MARK: - Redirect handling (custom-scheme callback)

    /// Processes the OAuth redirect callback URL. **Verbatim** port of the Android
    /// `handleRedirect(uri, onResult)` control flow:
    ///   1. extract `code` + `state` from the query;
    ///   2. no `code` → fail with the `error` query param (default "Authentication cancelled");
    ///   3. no active challenge, or `state` mismatch → fail with the CSRF state-mismatch message;
    ///   4. otherwise exchange the code with the stored `codeVerifier` and report the result.
    ///
    /// The typed `AuthError` cases carry the exact user-facing messages (their `errorDescription`),
    /// preserving the strings the Android `Exception(...)` messages produced.
    func handleRedirect(_ uri: URL, onResult: @escaping @MainActor (Result<Void, Error>) -> Void) async {
        let fields = OAuthCallback.fields(in: uri)
        let challenge = activeChallenge

        // Android: `if (code == null)` → fail with the `error` param (or the cancelled default).
        guard let code = fields.code else {
            let message = fields.error ?? "Authentication cancelled"
            fail(AuthErrorMessage(message), onResult: onResult)
            return
        }

        // Android: `if (challenge == null || challenge.state != stateParam)` → CSRF state mismatch.
        guard let challenge, challenge.state == fields.state else {
            fail(AuthError.stateMismatch, onResult: onResult)
            return
        }

        do {
            try await loginUseCase.completeLogin(code: code, codeVerifier: challenge.codeVerifier)
            loginError = nil
            onResult(.success(()))
        } catch is CancellationError {
            return
        } catch {
            fail(error, onResult: onResult)
        }
    }

    // MARK: - Logout

    /// Purges the session. Port of `onLogout()`.
    func onLogout() {
        Task { [weak self] in
            await self?.authRepository.logout()
        }
    }

    // MARK: - Teardown

    /// Drops the auth-state subscription. Called from the owning scene's teardown.
    func close() {
        authStateCancellable?.cancel()
    }

    // No explicit `deinit`: `AnyCancellable` cancels its subscription automatically when the view model
    // (and thus the stored cancellable) is deallocated.
}

// MARK: - AuthErrorMessage

/// A thin `LocalizedError` carrying a raw redirect `error` message verbatim. The Android VM surfaced
/// the provider's `error` query parameter (or the literal "Authentication cancelled") through
/// `Result.failure(Exception(message))`; this preserves that exact string for the UI without forcing
/// it into one of the fixed `AuthError` cases (which carry their own canned descriptions).
/// Reads `code`, `state`, and `error` from an OAuth redirect. X puts them in the query.
/// Some browsers rewrite the redirect into the fragment, and a blank value is treated as absent.
enum OAuthCallback {
    static func fields(in url: URL) -> (code: String?, state: String?, error: String?) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var code = item("code", in: components?.queryItems)
        var state = item("state", in: components?.queryItems)
        var error = item("error", in: components?.queryItems)
        if code == nil, let fragment = url.fragment, !fragment.isEmpty {
            let fragmentItems = URLComponents(string: "https://oauth.invalid/?\(fragment)")?.queryItems
            code = item("code", in: fragmentItems)
            if state == nil { state = item("state", in: fragmentItems) }
            if error == nil { error = item("error", in: fragmentItems) }
        }
        return (code, state, error)
    }

    private static func item(_ name: String, in items: [URLQueryItem]?) -> String? {
        guard let raw = items?.first(where: { $0.name == name })?.value else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct AuthErrorMessage: Error, LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
