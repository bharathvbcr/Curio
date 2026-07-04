//
//  GlassScaffold.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/components/GlassScaffold.kt (GlassScaffold).
//
//  CONVENTIONS §8 (Theme/Liquid-Glass + Layout/insets) + DESIGN tech-mapping (Compose
//  GlassScaffold + Haze blur → iOS 26 Liquid Glass): the app shell. On iOS 26 the native
//  `.glassEffect` inside the bars samples the backdrop automatically, so the SINGLE hoisted
//  `HazeState` + `hazeSource`/`hazeEffect` plumbing is DROPPED entirely — content scrolls
//  under the glass bars and the native glass frosts whatever sits behind it. On the `.solid`
//  tier (Reduce Transparency / low-RAM analogue) the bars fall back to the opaque
//  `glassSurface` tint with no blur, exactly like the Android `blurEnabled = tier != Solid`
//  short-circuit.
//
//  The tier is resolved ONCE here via `resolveGlassTier(reduceTransparency:)` (the Theme
//  helper that replaces `rememberGlassTier()`), then handed to every slot — matching the
//  Kotlin `val tier = rememberGlassTier()` hoist. Bars host via `.safeAreaInset` so content
//  gets the correct top/bottom insets (the Compose `Scaffold` innerPadding analogue); the FAB
//  overlays bottom-trailing. `contentWindowInsets = WindowInsets.navigationBars` is honored by
//  relying on SwiftUI's native safe-area handling.
//

import SwiftUI

/// Standard app shell with responsive liquid-glass bar integrations.
///
/// Generic over the top bar, bottom bar, FAB, and content builders — each receives the resolved
/// `GlassTier` (mirroring the Kotlin `@Composable (GlassTier) -> Unit` slots). The content
/// builder also receives the safe-area-style edge insets contributed by the bars so it can pad
/// scrollable content (the Compose `PaddingValues` analogue); with `.safeAreaInset` SwiftUI
/// already insets the content automatically, so most callers can ignore the passed insets.
struct GlassScaffold<TopBar: View, BottomBar: View, FAB: View, Content: View>: View {
    @ViewBuilder var topBar: (GlassTier) -> TopBar
    @ViewBuilder var bottomBar: (GlassTier) -> BottomBar
    @ViewBuilder var floatingActionButton: (GlassTier) -> FAB
    @ViewBuilder var content: (EdgeInsets, GlassTier) -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        @ViewBuilder topBar: @escaping (GlassTier) -> TopBar = { (_: GlassTier) in EmptyView() },
        @ViewBuilder bottomBar: @escaping (GlassTier) -> BottomBar = { (_: GlassTier) in EmptyView() },
        @ViewBuilder floatingActionButton: @escaping (GlassTier) -> FAB = { (_: GlassTier) in EmptyView() },
        @ViewBuilder content: @escaping (EdgeInsets, GlassTier) -> Content
    ) {
        self.topBar = topBar
        self.bottomBar = bottomBar
        self.floatingActionButton = floatingActionButton
        self.content = content
    }

    var body: some View {
        // Resolve the tier ONCE (replaces `rememberGlassTier()`): Reduce Transparency forces
        // `.solid` (opaque, no blur), else native iOS 26 glass.
        let tier = resolveGlassTier(reduceTransparency: reduceTransparency)

        contentLayer(tier: tier)
            // Content scrolls UNDER the top bar; the native glass samples it (Haze dropped).
            .safeAreaInset(edge: .top, spacing: 0) {
                topBar(tier)
            }
            // Content scrolls UNDER the bottom bar.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar(tier)
            }
    }

    /// The content area with the FAB overlaid bottom-trailing (the Compose `floatingActionButton`
    /// slot). Combine adjacent glass shapes — the bars + FAB — in a `GlassEffectContainer` on
    /// iOS 26 so their specular highlights merge correctly (CONVENTIONS §8).
    @ViewBuilder
    private func contentLayer(tier: GlassTier) -> some View {
        if #available(iOS 26, *) {
            GlassEffectContainer {
                contentWithFab(tier: tier)
            }
        } else {
            contentWithFab(tier: tier)
        }
    }

    @ViewBuilder
    private func contentWithFab(tier: GlassTier) -> some View {
        content(EdgeInsets(), tier)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                floatingActionButton(tier)
                    .padding(16)
            }
    }
}

// MARK: - Preview

#Preview("Glass scaffold") {
    GlassScaffold(
        topBar: { tier in GlassTopBar(title: "Curio", tier: tier) },
        bottomBar: { tier in
            GlassBottomBar(
                items: [
                    GlassNavigationItem(selectedIcon: "house.fill", unselectedIcon: "house", label: "Home", route: "home"),
                    GlassNavigationItem(selectedIcon: "square.grid.2x2.fill", unselectedIcon: "square.grid.2x2", label: "Spaces", route: "spaces")
                ],
                currentRoute: "home",
                tier: tier,
                onNavigate: { _ in }
            )
        },
        floatingActionButton: { tier in LiquidGlassFab(onClick: {}, tier: tier) },
        content: { _, _ in
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(0..<20, id: \.self) { i in
                        Text("Row \(i)")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
            }
        }
    )
    .environment(\.curioColors, .dark)
}
