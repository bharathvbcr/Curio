//
//  LoginScreen.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/screens/auth/LoginScreen.kt
//         (LoginScreen — liquid-glass login landing).
//
//  DESIGN §10 (Screens): `struct LoginView`; `state is .signingIn` disables the connect button (and
//  swaps in the spinner + "SECURE EXCHANGES..." label); login is driven via
//  `ASWebAuthenticationSession` through `AuthViewModel`; exact labels carried verbatim.
//
//  CONVENTIONS mapping:
//  - §4 "exact user-facing strings": every label ("CURIO", "AI RESEARCH BOOKMARK ENGINE", the privacy
//    paragraph, "CONNECT WITH X", "SECURE EXCHANGES...", "ENCRYPTED · READ-ONLY · YOUR DATA", …) is
//    carried byte-for-byte from the Compose source.
//  - §8 "Glass": the hero badge, the connection card, and the connect button use `glassSurface(...)`
//    with the EXACT tints/borders from the Compose source (primary@0.2 / @0.3 hero; primary@0.15 vs
//    onSurface@0.05 button tint gated on `isSigningIn`; primary@0.25 button border). The button uses
//    the `RoundedCornerShape(16.dp)` shape.
//  - §8 "Theme tokens": colours come from `@Environment(\.curioColors)` (the Cosmic Slate scheme),
//    NOT SwiftUI semantic system colors — `background`, `inverseOnSurface`, `primary`, `onSurface`.
//  - §8 "Typography": display/label roles applied via `.curioText(_:)` with the Compose overrides
//    (52pt Black display title with -4 tracking; the ExtraBold/Black label roles) carried explicitly.
//  - §8 "Motion": the connect button is a `Button` with the app-wide `.curioPressBounce` style
//    (replacing the Compose `clickable`), disabled while signing in.
//  - §13 "Accessibility": `.accessibilityIdentifier("connect_x_button")` mirrors the Compose
//    `testTag("connect_x_button")`.
//
//  Renamed `LoginScreen` → `LoginView` per DESIGN §10 (the `…View` suffix for SwiftUI screens) and to
//  match the `BookmarkApp` call site (`LoginView(state:tier:onLoginClick:)`).
//

import SwiftUI

/// High-fidelity, liquid-glass login landing supporting OAuth 2.0 with PKCE. Direct port of the
/// `@Composable fun LoginScreen(state, tier, onLoginClick, modifier)`.
struct LoginView: View {

    /// Current authentication state — drives the connect button's spinner/disabled state.
    let state: AuthState
    /// The resolved glass tier threaded from `BookmarkApp` (override → Reduce Transparency → native).
    let tier: GlassTier
    /// Kicks off the PKCE login (`AuthViewModel.onLoginClick`).
    let onLoginClick: () -> Void
    /// Optional inline error from the auth flow (replaces Toast-only feedback on Android).
    var errorMessage: String? = nil
    /// Tap-to-dismiss on the error banner.
    var onDismissError: () -> Void = {}

    @Environment(\.curioColors) private var colors

    /// `state is AuthState.SigningIn` — disables the button and shows the exchange spinner.
    private var isSigningIn: Bool {
        if case .signingIn = state { return true }
        return false
    }

    var body: some View {
        ZStack {
            // Premium vertical gradient backdrop (`background → inverseOnSurface@0.5`).
            LinearGradient(
                colors: [colors.background, colors.inverseOnSurface.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                heroBadge
                titleBlock
                connectionCard
                trustMarkers
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            // `systemBarsPadding()` — keep content clear of the status/home indicator.
            .padding(.vertical, 0)
        }
    }

    // MARK: - Hero badge

    /// The circular glass hero tile holding the brand mark. Compose: a 100dp `CircleShape`
    /// `glassSurface` tinted primary@0.2 / bordered primary@0.3, with a 52dp `CurioLogoMark` centred.
    private var heroBadge: some View {
        ZStack {
            CurioLogoMark(tint: colors.primary)
                .frame(width: 52, height: 52)
        }
        .frame(width: 100, height: 100)
        .glassSurface(
            tier: tier,
            shape: Circle(),
            tint: colors.primary.opacity(0.2),
            borderColor: colors.primary.opacity(0.3)
        )
    }

    // MARK: - Title block

    private var titleBlock: some View {
        VStack(spacing: 8) {
            // displayLarge overridden to 52sp Black, letterSpacing -4sp.
            Text("CURIO")
                .font(.system(size: 52, weight: .black))
                .tracking(-4)
                .foregroundStyle(colors.onSurface)

            // labelSmall: primary, ExtraBold, letterSpacing 1.8sp.
            Text("AI RESEARCH BOOKMARK ENGINE")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.8)
                .foregroundStyle(colors.primary)
        }
    }

    // MARK: - Connection card

    /// The glass card holding the headline, the privacy paragraph, and the connect button.
    private var connectionCard: some View {
        VStack(spacing: 16) {
            // titleMedium, Black, centred.
            Text("Synchronize & Curate Bookmarks Securely")
                .font(.system(size: 18, weight: .black))
                .tracking(-0.2)
                .multilineTextAlignment(.center)
                .foregroundStyle(colors.onSurface)

            // bodyMedium, onSurface@0.7, centred. Carried verbatim (the on-device-OCR / cloud-AI
            // disclosure is the load-bearing privacy copy).
            Text("Curio connects securely via official OAuth 2.0 with PKCE and stores credentials encrypted on-device. Screenshot OCR runs on-device; AI summaries, tags and chat are generated by xAI's cloud (Grok) — only the saved post text is sent, and only when you sync or analyze.")
                .font(.system(size: 14, weight: .medium))
                .tracking(0.25)
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .foregroundStyle(colors.onSurface.opacity(0.7))

            if let errorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(colors.error)
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(colors.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(
                    tier: tier,
                    shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                    tint: colors.errorContainer.opacity(0.35),
                    borderColor: colors.error.opacity(0.3)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture(perform: onDismissError)
                .accessibilityIdentifier("login_error_banner")
            }

            connectButton
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassSurface(tier: tier)
    }

    /// The full-width 56pt connect button. Tint switches on `isSigningIn` (onSurface@0.05 vs
    /// primary@0.15); border primary@0.25; rounded-16 shape; disabled while signing in.
    private var connectButton: some View {
        Button(action: onLoginClick) {
            Group {
                if isSigningIn {
                    HStack(spacing: 0) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(colors.primary)
                            .frame(width: 24, height: 24)
                        Spacer().frame(width: 12)
                        Text("SECURE EXCHANGES...")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(colors.primary)
                    }
                } else {
                    HStack(spacing: 0) {
                        Image(systemName: "arrow.right.square")     // Icons.Default.Login
                            .foregroundStyle(colors.primary)
                        Spacer().frame(width: 12)
                        // labelLarge, ExtraBold, primary, letterSpacing 1sp.
                        Text("CONNECT WITH X")
                            .font(.system(size: 14, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(colors.primary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .glassSurface(
                tier: tier,
                shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                tint: isSigningIn
                    ? colors.onSurface.opacity(0.05)
                    : colors.primary.opacity(0.15),
                borderColor: colors.primary.opacity(0.25)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.curioPressBounce)
        .disabled(isSigningIn)
        .accessibilityIdentifier("connect_x_button")
    }

    // MARK: - Trust markers

    /// The bottom trust row (shield glyph + "ENCRYPTED · READ-ONLY · YOUR DATA").
    private var trustMarkers: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.fill")     // Icons.Default.Shield
                .font(.system(size: 16))
                .foregroundStyle(colors.primary.opacity(0.5))
            Text("ENCRYPTED · READ-ONLY · YOUR DATA")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(colors.onSurface.opacity(0.5))
        }
        .padding(.top, 8)
    }
}
