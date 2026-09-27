import Foundation
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// `ASWebAuthenticationSession` wrapper driving the X OAuth2 browser handoff. Replaces the Android
/// Chrome Custom Tabs flow (DESIGN §"Chrome Custom Tabs (OAuth) → ASWebAuthenticationSession"; Auth
/// cross-cutting: "state CSRF validation in presentation layer").
///
/// On Android the authorize URL was opened in a Custom Tab and the redirect re-entered the app via
/// an intent the Activity parsed. On iOS `ASWebAuthenticationSession` owns the whole round-trip:
/// it opens the system browser, watches for a redirect to `callbackScheme`, and hands the full
/// callback `URL` back. The caller (`AuthViewModel`) then extracts `code` / `state` / `error` and
/// validates the CSRF `state` — keeping CSRF validation in the presentation layer as the convention
/// requires.
///
/// **Cancellation:** a user dismissing the sheet yields
/// `ASWebAuthenticationSessionError.canceledLogin`, mapped to `AuthError.cancelled` so the controller
/// can quietly reset to `.signedOut`.
///
/// **Retention:** `ASWebAuthenticationSession` deallocates (and silently cancels) if not strongly
/// held; we retain `self` for the lifetime of the continuation and pin the session in a stored
/// property. `@MainActor` because `start()` and the presentation anchor must run on the main thread.
/// Browser handoff used by `AuthViewModel`. Tests substitute a fake; the app uses `WebAuthSession`.
@MainActor
protocol WebAuthenticating: AnyObject {
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

@MainActor
final class WebAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding, WebAuthenticating {

    /// How long to wait for the browser to return before cancelling the session.
    static let callbackTimeout: Duration = .seconds(180)

    /// Strong reference to the in-flight session (released when the continuation resumes).
    private var session: ASWebAuthenticationSession?
    private var timeoutTask: Task<Void, Never>?

    #if os(macOS)
    /// Kept alive when AppKit has no visible window yet, so the session is not handed an unshown anchor.
    private var fallbackAnchor: NSWindow?
    #endif

    /// Optional explicit presentation anchor; falls back to the app's key window.
    private let anchorProvider: @MainActor () -> ASPresentationAnchor

    /// - Parameter anchor: closure returning the window to present from. Defaults to the first
    ///   foreground-active window scene's key window (or a fresh `ASPresentationAnchor()` if none is
    ///   available yet).
    init(anchor: @escaping @MainActor () -> ASPresentationAnchor = WebAuthSession.defaultAnchor) {
        self.anchorProvider = anchor
        super.init()
    }

    /// Launches the system browser at `url` and suspends until the redirect to `callbackScheme`
    /// arrives, returning the full callback `URL`.
    ///
    /// - Throws: `AuthError.cancelled` if the user dismisses the sheet; otherwise the underlying
    ///   `ASWebAuthenticationSession` error.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        let scheme = callbackScheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scheme.isEmpty, url.scheme == "https" || url.scheme == "http" else {
            throw AuthError.presentationFailed
        }
        let gate = CallbackResume<URL>()
        // The session completion is invoked on Safari's XPC queue. It must not touch
        // main-actor state: entering a main-actor closure there traps the process.
        let onCallback: @Sendable (URL?, Error?) -> Void = { callbackURL, error in
            gate.resume(AuthCallback.interpret(url: callbackURL, error: error))
        }
        defer {
            timeoutTask?.cancel()
            session = nil
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            gate.store(continuation)
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(scheme), completionHandler: onCallback)

            session.presentationContextProvider = self
            // iOS uses a private sheet. On macOS the default browser often cannot complete an
            // ephemeral session, so the sign-in window never returns.
            session.prefersEphemeralWebBrowserSession = AuthBrowserPolicy.prefersEphemeral(onMac: Self.isMac)

            self.session = session
            if !session.start() {
                gate.resume(.failure(AuthError.presentationFailed))
                return
            }
            timeoutTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: Self.callbackTimeout)
                } catch {
                    return
                }
                session.cancel()
                gate.resume(.failure(AuthError.timedOut))
            }
        }
    }

    private static var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }



    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let resolve = { MainActor.assumeIsolated { self.resolveAnchor() } }
        if Thread.isMainThread {
            return resolve()
        }
        return DispatchQueue.main.sync(execute: resolve)
    }

    private func resolveAnchor() -> ASPresentationAnchor {
        let provided = anchorProvider()
        #if os(macOS)
        if provided.isVisible { return provided }
        if let window = AuthWindowChoice.visibleWindow(
            key: NSApplication.shared.keyWindow,
            windows: NSApplication.shared.windows,
            isVisible: { $0.isVisible }
        ) {
            return window
        }
        if let fallbackAnchor { return fallbackAnchor }
        let window = NSWindow(
            contentRect: NSRect(x: 240, y: 240, width: 480, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Curio"
        window.orderFrontRegardless()
        fallbackAnchor = window
        return window
        #else
        return provided
        #endif
    }

    // MARK: - Default anchor

    /// Resolves a visible window. A brand-new unshown window is not used as the anchor:
    /// on macOS that makes `ASWebAuthenticationSession` start without ever presenting.
    static func defaultAnchor() -> ASPresentationAnchor {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes
        if let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first {
            return keyWindow
        }
        return ASPresentationAnchor()
        #elseif os(macOS)
        if let window = AuthWindowChoice.visibleWindow(
            key: NSApplication.shared.keyWindow,
            windows: NSApplication.shared.windows,
            isVisible: { $0.isVisible }
        ) {
            return window
        }
        return ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

/// Turns the browser callback into a result without touching actor-isolated state.
enum AuthCallback {
    nonisolated static func interpret(url: URL?, error: Error?) -> Result<URL, Error> {
        if let url { return .success(url) }
        if let error = error as? ASWebAuthenticationSessionError {
            switch error.code {
            case .canceledLogin:
                return .failure(AuthError.cancelled)
            case .presentationContextNotProvided, .presentationContextInvalid:
                return .failure(AuthError.presentationFailed)
            default:
                return .failure(error)
            }
        }
        if let error { return .failure(error) }
        return .failure(AuthError.cancelled)
    }
}

/// Resumes a continuation at most once, from any queue.
final class CallbackResume<Success: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Success, Error>?
    private var resumed = false

    func store(_ continuation: CheckedContinuation<Success, Error>) {
        lock.lock()
        let already = resumed
        if !already { self.continuation = continuation }
        lock.unlock()
        if already { continuation.resume(throwing: AuthError.cancelled) }
    }

    func resume(_ result: Result<Success, Error>) {
        lock.lock()
        if resumed {
            lock.unlock()
            return
        }
        resumed = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

/// Claims a one-shot callback so a browser completion and a timeout cannot both resume.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

enum AuthBrowserPolicy {
    /// Ephemeral browsing is reliable in the iOS authentication sheet. macOS hands the session
    /// to the user's default browser, which may not support an ephemeral session.
    static func prefersEphemeral(onMac: Bool) -> Bool { !onMac }
}

enum AuthWindowChoice {
    static func visibleWindow<Window>(
        key: Window?,
        windows: [Window],
        isVisible: (Window) -> Bool
    ) -> Window? {
        if let key, isVisible(key) { return key }
        return windows.first(where: isVisible)
    }
}
