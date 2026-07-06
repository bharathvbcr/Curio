//
//  BookmarkApp.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/BookmarkApp.kt
//         (BookmarkApp, DrawerNavRow, XAccountCard).
//
//  DESIGN §10 (Screens): root container — auth gate, theme, drawer, routed screens, manual-add
//  sheet, reader cover, setUserId. `struct BookmarkApp`; `@State` flags; `if case .signedIn` →
//  shell else `LoginView`; `DrawerNavRow`, `XAccountCard`; `.task(id: userId){ setUserId }`; FAB on
//  bookmarks; bottom bar hidden on keyboard; reader via `.fullScreenCover(item:)`.
//
//  CONVENTIONS mapping:
//  - §4 "@MainActor/@Observable": both view models are injected `@Bindable`/`@Observable` and read
//    directly; the Kotlin `collectAsStateWithLifecycle()` collapses to plain property reads.
//  - §8 "Theme": the System/Light/Dark setting resolves a `darkTheme: Bool?` handed to
//    `.curioTheme(darkTheme:)`. Material You / `dynamicColor` is DROPPED (the static Cosmic palette
//    is canonical), so the Android `useDynamicColor` toggle is removed — Settings keeps the same
//    control wired to a no-op-on-color theming surface (handled in `SettingsView`).
//  - §8 "Glass": the glass tier is resolved ONCE via `resolveGlassTier(override:reduceTransparency:)`
//    (replacing `rememberGlassTier(override)`) and threaded into every screen/bar/FAB, matching the
//    Kotlin `val resolvedTier = rememberGlassTier(glassTierOverride)` hoist.
//  - §4 "Async pattern": `setUserId` runs in `.task(id:)` when the signed-in user id changes,
//    mirroring the Android `LaunchedEffect(signedInState.userId) { setUserId(...) }`.
//  - The Android `ModalNavigationDrawer` becomes a custom side-drawer overlay so the EXACT drawer
//    content (brand header, "WORKSPACE" label, four nav rows, divider, X account
//    card) and its user-facing strings are preserved verbatim (CONVENTIONS §4).
//  - The bookmarks feed embeds its own merged search header, so the shared `GlassTopBar` is skipped
//    on the Bookmarks route exactly like the Kotlin `if (currentRoute != Bookmarks)` guard.
//
//  This file references the sibling Screens types ported alongside it (`AuthViewModel`, `LoginView`,
//  `BookmarkFeedView`, `CurioSpacesView`, `CurioInsightsView`, `CurioChatView`, `SettingsView`,
//  `ReaderView`) by their DESIGN §10-declared names/signatures.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Main application container that coordinates theme options, navigation, and high-fidelity glass
/// scaffold layouts. Direct port of the `@Composable fun BookmarkApp(authViewModel, bookmarkViewModel)`.
struct BookmarkApp: View {
    /// OAuth-PKCE controller (auth state + login/redirect/logout). Injected, owned upstream by the
    /// app scene; `@Bindable` so the auth state drives the gate reactively.
    @Bindable var authViewModel: AuthViewModel
    /// Central library view model. Injected, owned upstream; `@Bindable` for the same reason.
    @Bindable var bookmarkViewModel: BookmarkViewModel

    // MARK: - Local navigation / UI flags (Compose `remember { mutableStateOf(...) }`)

    /// The selected top-level destination. Port of `var currentRoute by remember { … Bookmarks }`.
    @State private var currentRoute: CurioDestination = .bookmarks
    /// Manual `GlassTier` override from Settings (`nil` = auto). Port of `glassTierOverride`.
    @State private var glassTierOverride: GlassTier? = nil
    /// Whether the manual "add bookmark" dialog is showing. Port of `showInputForm`.
    @State private var showInputForm: Bool = false
    /// The bookmark opened in the full-screen reader, or `nil` when closed. Port of
    /// `activeReaderBookmark`. Drives `.fullScreenCover(item:)`.
    @State private var activeReaderBookmark: Bookmark? = nil
    /// Whether the workspace side drawer is open. Replaces the Compose `DrawerState`.
    @State private var isDrawerOpen: Bool = false
    /// Global transient feedback (ports Android `CurioNotifier` + `SnackbarHost`).
    @State private var globalToast: String?

    // MARK: - Environment

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// System color scheme — the `isSystemInDarkTheme()` analogue for the SYSTEM theme setting.
    @Environment(\.colorScheme) private var systemColorScheme

    // MARK: - Derived theme + tier

    /// Resolves the effective dark/light override from the in-app Theme setting, mirroring the
    /// Kotlin `when (themeSetting) { SYSTEM -> sysDark; LIGHT -> false; DARK -> true }`. Returns
    /// `nil` for SYSTEM so `.curioTheme(darkTheme: nil)` follows the system scheme.
    private var darkThemeOverride: Bool? {
        switch bookmarkViewModel.themeSetting {
        case .system: return nil
        case .light: return false
        case .dark: return true
        }
    }

    /// The effective dark flag (used by the Reader cover which forces its own theme wrapper).
    private var isDark: Bool {
        switch bookmarkViewModel.themeSetting {
        case .system: return systemColorScheme == .dark
        case .light: return false
        case .dark: return true
        }
    }

    /// The resolved glass tier (override → Reduce Transparency → native). Resolved ONCE and threaded
    /// everywhere, replacing `rememberGlassTier(glassTierOverride)`.
    private var resolvedTier: GlassTier {
        resolveGlassTier(override: glassTierOverride, reduceTransparency: reduceTransparency)
    }

    // MARK: - Body (auth gate)

    var body: some View {
        ZStack {
            if case let .signedIn(userId, username, name) = authViewModel.authState {
                signedInShell(userId: userId, username: username, name: name)
                    // Set the user context once the signed-in user id is known (and again if it
                    // changes). Port of `LaunchedEffect(signedInState.userId) { setUserId(...) }`.
                    .task(id: userId) {
                        bookmarkViewModel.setUserId(userId)
                    }
            } else {
                // Not signed in → the login landing, themed the same way.
                LoginView(
                    state: authViewModel.authState,
                    tier: resolvedTier,
                    onLoginClick: {
                        authViewModel.clearLoginError()
                        authViewModel.onLoginClick { result in
                            switch result {
                            case .success:
                                authViewModel.reportLoginSuccess()
                            case .failure(let error):
                                authViewModel.reportLoginFailure(
                                    "Login connection failed: \(error.localizedDescription)"
                                )
                            }
                        }
                    },
                    errorMessage: authViewModel.loginError,
                    onDismissError: { authViewModel.clearLoginError() }
                )
            }
        }
        // Theme resolution: System/Light/Dark → darkTheme override (nil follows the system).
        .curioTheme(darkTheme: darkThemeOverride)
        // The full-screen reader is hosted as a cover above the whole shell, mirroring the Kotlin
        // `activeReaderBookmark?.let { ReaderViewScreen(...) }` overlay at the BookmarkApp root.
        .fullScreenCover(item: $activeReaderBookmark) { bookmark in
            ReaderView(
                bookmark: bookmark,
                tier: resolvedTier,
                darkTheme: isDark,
                onClose: { activeReaderBookmark = nil }
            )
        }
    }

    // MARK: - Signed-in shell (scaffold + drawer)

    @ViewBuilder
    private func signedInShell(userId: String, username: String?, name: String?) -> some View {
        ZStack(alignment: .leading) {
            // Aesthetic layered radial color effect for premium background depth — the Compose
            // `Brush.verticalGradient(background → inverseOnSurface@0.5)`.
            backgroundGradient
                .ignoresSafeArea()

            scaffold(userId: userId, username: username, name: name)

            // Side drawer overlay (the `ModalNavigationDrawer` analogue): a dimming scrim + the
            // sliding 310pt sheet. Kept inside the shell so it floats above the scaffold but below
            // the reader cover.
            drawerOverlay(userId: userId, username: username, name: name)
        }
        // The manual-add dialog is presented as a slide-up sheet (CONVENTIONS §8 dialogs). Port of
        // the Compose `if (showInputForm) ManualAddBookmarkDialog(...)`.
        .sheet(isPresented: $showInputForm) {
            ManualAddBookmarkDialog(
                tier: resolvedTier,
                onAddBookmark: { text in
                    bookmarkViewModel.addManualBookmark(text) { result in
                        if case let .success(newBookmark) = result {
                            bookmarkViewModel.runAiAnalysis(newBookmark)
                        }
                    }
                },
                onRequestPreview: { text, completion in
                    bookmarkViewModel.getInstantSummaryPreview(text: text) { preview in
                        completion(preview)
                    }
                }
            )
        }
        // Track keyboard visibility so the bottom bar hides while typing (the
        // `WindowInsets.isImeVisible` analogue). UIKit notifications are the portable signal.
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        #endif
        .overlay(alignment: .bottom) {
            CurioToastOverlay(message: globalToast)
                .padding(.bottom, 96)
                .animation(CurioMotion.liquid, value: globalToast)
        }
        .onAppear {
            CurioNotifier.showMessage = { message in
                globalToast = message
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    if globalToast == message { globalToast = nil }
                }
            }
        }
        .onDisappear {
            if globalToast != nil { globalToast = nil }
            CurioNotifier.showMessage = nil
        }
    }

    /// The premium vertical background gradient (`background → inverseOnSurface@0.5`).
    private var backgroundGradient: some View {
        // Read the resolved scheme so the gradient tracks the active theme.
        ThemeColorsReader { colors in
            LinearGradient(
                colors: [colors.background, colors.inverseOnSurface.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Scaffold (top/bottom bars + FAB + routed content)

    @ViewBuilder
    private func scaffold(userId: String, username: String?, name: String?) -> some View {
        GlassScaffold(
            topBar: { _ in
                // The bookmarks feed embeds its own merged search header (menu + search), so the
                // separate title bar is skipped there to reclaim vertical space. Port of the Kotlin
                // `if (currentRoute != Bookmarks) GlassTopBar(...)`.
                if currentRoute != .bookmarks {
                    GlassTopBar(
                        title: currentRoute.title,
                        tier: resolvedTier,
                        navigationIcon: {
                            Button {
                                openDrawer()
                            } label: {
                                Image(systemName: "line.3.horizontal")
                                    .accessibilityLabel("Open side workspace menu")
                            }
                            .buttonStyle(.curioPressBounce)
                            .tint(.primary)
                        }
                    )
                }
            },
            bottomBar: { _ in
                // The bottom bar hides while the keyboard is up. SwiftUI's `.keyboardLayoutGuide`
                // is implicit; we gate on a keyboard-visibility observer to mirror the Kotlin
                // `if (!isKeyboardOpen) GlassBottomBar(...)`.
                if !isKeyboardVisible {
                    GlassBottomBar(
                        items: Self.navItems,
                        currentRoute: currentRoute.id,
                        tier: resolvedTier,
                        onNavigate: { route in
                            currentRoute = CurioDestination.fromId(route)
                        }
                    )
                }
            },
            floatingActionButton: { _ in
                if currentRoute == .bookmarks {
                    LiquidGlassFab(
                        onClick: { showInputForm = true },
                        tier: resolvedTier,
                        icon: {
                            Image(systemName: "plus")
                                .tint(.primary)
                                .accessibilityLabel("Add manual bookmark")
                                .accessibilityIdentifier("fab_add_bookmark")
                        }
                    )
                }
            },
            content: { _, _ in
                routedContent
            }
        )
    }

    /// The routed screen for the current destination. Each screen receives the shared VM + tier.
    @ViewBuilder
    private var routedContent: some View {
        switch currentRoute {
        case .bookmarks:
            BookmarkFeedView(
                viewModel: bookmarkViewModel,
                tier: resolvedTier,
                onBookmarkClick: { activeReaderBookmark = $0 },
                onOpenMenu: { openDrawer() },
                onNavigateToSettings: { currentRoute = .settings },
                loginSuccessMessage: authViewModel.loginSuccessMessage,
                onDismissLoginSuccess: { authViewModel.clearLoginSuccess() }
            )
        case .spaces:
            CurioSpacesView(
                viewModel: bookmarkViewModel,
                tier: resolvedTier,
                onOpenSpace: { space in
                    bookmarkViewModel.selectSpace(space.id)
                    currentRoute = .bookmarks
                }
            )
        case .insights:
            CurioInsightsView(
                viewModel: bookmarkViewModel,
                tier: resolvedTier,
                onNavigateToFeed: { currentRoute = .bookmarks },
                onNavigateToSettings: { currentRoute = .settings }
            )
        case .chat:
            CurioChatView(
                viewModel: bookmarkViewModel,
                tier: resolvedTier,
                onNavigateToBookmarks: { currentRoute = .bookmarks },
                onNavigateToSettings: { currentRoute = .settings }
            )
        case .settings:
            SettingsView(
                glassTierOverride: $glassTierOverride,
                resolvedTier: resolvedTier,
                onLogout: { authViewModel.onLogout() },
                viewModel: bookmarkViewModel
            )
        }
    }

    // MARK: - Drawer overlay (ModalNavigationDrawer analogue)

    @ViewBuilder
    private func drawerOverlay(userId: String, username: String?, name: String?) -> some View {
        // Dimming scrim — tap to close. Only hit-testable while open.
        Color.black
            .opacity(isDrawerOpen ? 0.4 : 0.0)
            .ignoresSafeArea()
            .allowsHitTesting(isDrawerOpen)
            .onTapGesture { closeDrawer() }
            .animation(CurioMotion.fade, value: isDrawerOpen)

        // The sliding 310pt sheet.
        DrawerContent(
            currentRoute: $currentRoute,
            tier: resolvedTier,
            userId: userId,
            username: username,
            name: name,
            onNavigate: { dest in
                currentRoute = dest
                closeDrawer()
            }
        )
        .frame(width: 310)
        .frame(maxHeight: .infinity)
        // Slide in from the leading edge.
        .offset(x: isDrawerOpen ? 0 : -340)
        .animation(CurioMotion.liquid, value: isDrawerOpen)
        // Edge drag-to-close gesture (a lightweight `DrawerState.close()` analogue).
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    if value.translation.width < -40 { closeDrawer() }
                }
        )
    }

    // MARK: - Drawer open/close

    private func openDrawer() {
        withAnimation(CurioMotion.liquid) { isDrawerOpen = true }
    }

    private func closeDrawer() {
        withAnimation(CurioMotion.liquid) { isDrawerOpen = false }
    }

    // MARK: - Keyboard visibility

    /// Tracks whether the software keyboard is showing (the `WindowInsets.isImeVisible` analogue),
    /// driving the bottom-bar hide-on-keyboard behaviour.
    @State private var isKeyboardVisible: Bool = false

    // MARK: - Bottom-nav items (Compose `navItems`)

    /// The three primary tabs shown in the glass bottom bar. Carries the exact route ids + labels
    /// from the Kotlin `navItems`; Compose `ImageVector`s map to SF Symbols (CONVENTIONS §8 icons:
    /// Bookmarks→`bookmark.fill`/`bookmark`, Workspaces→`square.grid.2x2.fill`/`square.grid.2x2`,
    /// Psychology→`brain.head.profile` for "Curio AI"). Insights + Settings are reachable from the
    /// workspace drawer only.
    private static let navItems: [GlassNavigationItem] = [
        GlassNavigationItem(
            selectedIcon: "bookmark.fill",
            unselectedIcon: "bookmark",
            label: "Bookmarks",
            route: "bookmarks"
        ),
        GlassNavigationItem(
            selectedIcon: "square.grid.2x2.fill",
            unselectedIcon: "square.grid.2x2",
            label: "Spaces",
            route: "spaces"
        ),
        GlassNavigationItem(
            selectedIcon: "brain.head.profile.fill",
            unselectedIcon: "brain.head.profile",
            label: "Curio AI",
            route: "chatbot"
        )
    ]
}

// MARK: - ThemeColorsReader

/// Tiny helper that reads the active `CurioColorScheme` from the environment and hands it to a
/// builder — used where a stored `let colors` would be awkward (e.g. building a background gradient
/// in a computed property). Equivalent to inlining `@Environment(\.curioColors)`.
private struct ThemeColorsReader<Content: View>: View {
    @Environment(\.curioColors) private var colors
    @ViewBuilder let content: (CurioColorScheme) -> Content
    var body: some View { content(colors) }
}

// MARK: - DrawerContent (the ModalDrawerSheet body)

/// The workspace side-drawer content. Direct port of the Compose `ModalDrawerSheet { Column { … } }`
/// body: brand + signed-in identity header, a divider, the "WORKSPACE" label, the four primary nav
/// rows, a flexible spacer, a divider, and the connected-X-account card. Every
/// user-facing string is carried verbatim (CONVENTIONS §4).
private struct DrawerContent: View {
    @Binding var currentRoute: CurioDestination
    let tier: GlassTier
    let userId: String
    let username: String?
    let name: String?
    let onNavigate: (CurioDestination) -> Void

    @Environment(\.curioColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Brand + signed-in identity header.
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(colors.primary.opacity(0.15))
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(colors.primary)
                        .font(.system(size: 24))
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Curio")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(colors.onSurface)
                    Text("Your research index")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(colors.onSurface.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(tier: tier, shape: RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Divider line (onSurface@0.08).
            colors.onSurface.opacity(0.08)
                .frame(height: 1)
                .frame(maxWidth: .infinity)

            Text("WORKSPACE")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(colors.primary)

            DrawerNavRow(
                icon: "bookmark.fill",
                label: "My Bookmarks",
                selected: currentRoute == .bookmarks,
                onClick: { onNavigate(.bookmarks) }
            )
            DrawerNavRow(
                icon: "square.grid.2x2.fill",
                label: "Spaces",
                selected: currentRoute == .spaces,
                onClick: { onNavigate(.spaces) }
            )
            DrawerNavRow(
                icon: "chart.bar.fill",
                label: "Insights",
                selected: currentRoute == .insights,
                onClick: { onNavigate(.insights) }
            )
            DrawerNavRow(
                icon: "brain.head.profile",
                label: "Curio AI Chat",
                selected: currentRoute == .chat,
                onClick: { onNavigate(.chat) }
            )

            Spacer(minLength: 0)

            // Divider line.
            colors.onSurface.opacity(0.08)
                .frame(height: 1)
                .frame(maxWidth: .infinity)

            // Connected X account — tap to manage the session (sign out lives in Settings).
            XAccountCard(
                name: name,
                username: username,
                userId: userId,
                tier: tier,
                onClick: { onNavigate(.settings) }
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors.background)
    }
}

// MARK: - DrawerNavRow

/// A single navigation row inside the workspace drawer. Highlights itself when `selected` and falls
/// back to a neutral tint otherwise. Pass `tint` to force an accent colour (e.g. destructive
/// actions such as Sign Out). Direct port of the private `@Composable DrawerNavRow(...)`.
private struct DrawerNavRow: View {
    let icon: String
    let label: String
    let selected: Bool
    let onClick: () -> Void
    /// Optional forced accent colour (Android `tint: Color? = null`).
    var tint: Color? = nil

    @Environment(\.curioColors) private var colors

    /// Icon/label tint: explicit `tint` wins; else primary when selected, else onSurface@0.6.
    private var contentTint: Color {
        if let tint { return tint }
        return selected ? colors.primary : colors.onSurface.opacity(0.6)
    }

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 12) {
                if selected {
                    RoundedRectangle(cornerRadius: 50, style: .continuous)
                        .fill(colors.primary)
                        .frame(width: 3, height: 26)
                    Spacer().frame(width: 0)
                }
                Image(systemName: icon)
                    .foregroundStyle(contentTint)
                Text(label)
                    .font(.system(size: 14, weight: selected ? .bold : .regular))
                    .foregroundStyle(tint ?? colors.onSurface)
                Spacer(minLength: 0)
            }
            .padding(.leading, selected ? 0 : 12)
            .padding(.trailing, 12)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (selected ? colors.primary.opacity(0.12) : Color.clear),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.curioPressBounce)
    }
}

// MARK: - XAccountCard

/// Compact card showing the connected X (Twitter) account at the bottom of the drawer. Falls back
/// gracefully when only the numeric user id is known (e.g. a session restored from before the handle
/// was persisted). Tapping it opens Settings, where the session can be signed out. Direct port of
/// the private `@Composable XAccountCard(...)`.
private struct XAccountCard: View {
    let name: String?
    let username: String?
    let userId: String
    let tier: GlassTier
    let onClick: () -> Void

    @Environment(\.curioColors) private var colors

    /// `name?.takeIf { it.isNotBlank() } ?: "X Account"`.
    private var displayName: String {
        if let name = name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return "X Account"
    }

    /// `username?.takeIf { isNotBlank }?.let { "@$it" } ?: "ID $userId"`.
    private var handle: String {
        if let username = username, !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "@\(username)"
        }
        return "ID \(userId)"
    }

    /// `(name ?: username ?: "X").trim().firstOrNull()?.uppercaseChar()?.toString() ?: "X"`.
    private var initial: String {
        let source = (name ?? username ?? "X").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = source.first else { return "X" }
        return String(first).uppercased()
    }

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(colors.primary.opacity(0.15))
                    Text(initial)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(colors.primary)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 0) {
                    Text(displayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(colors.onSurface)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(handle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(colors.onSurface.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // The bold "𝕏" mark (U+1D54F MATHEMATICAL DOUBLE-STRUCK CAPITAL X), carried verbatim.
                Text("𝕏")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(colors.onSurface.opacity(0.45))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(tier: tier, shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.curioPressBounce)
    }
}
