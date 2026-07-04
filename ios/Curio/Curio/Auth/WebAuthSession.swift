import Foundation
import UIKit
import AuthenticationServices

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
@MainActor
final class WebAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {

    /// Strong reference to the in-flight session (released when the continuation resumes).
    private var session: ASWebAuthenticationSession?

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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(callbackScheme)
            ) { [weak self] callbackURL, error in
                // Release the strong session reference exactly once.
                self?.session = nil
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error {
                    if let asError = error as? ASWebAuthenticationSessionError,
                       asError.code == .canceledLogin {
                        continuation.resume(throwing: AuthError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                } else {
                    // No URL and no error should not occur; treat as cancellation defensively.
                    continuation.resume(throwing: AuthError.cancelled)
                }
            }

            session.presentationContextProvider = self
            // Ephemeral so the X login is not pre-filled from a prior Safari session (mirrors the
            // fresh-Custom-Tab behaviour and avoids surprising account reuse).
            session.prefersEphemeralWebBrowserSession = true

            self.session = session
            if !session.start() {
                self.session = nil
                continuation.resume(throwing: AuthError.cancelled)
            }
        }
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { anchorProvider() }
    }

    // MARK: - Default anchor

    /// Resolves the current key window from the active foreground scene, or a placeholder anchor.
    static func defaultAnchor() -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
        if let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first {
            return keyWindow
        }
        return ASPresentationAnchor()
    }
}
