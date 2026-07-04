//
//  GlassBottomBar.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/components/GlassBottomBar.kt
//         (GlassNavigationItem, GlassBottomBar).
//
//  CONVENTIONS §8 (Theme/Liquid-Glass + Motion + Accessibility): bottom nav finished in
//  liquid-glass styling, responsive to standard `GlassTier`s. Each tab is a press-bounce
//  target (`pressBounce(pressedScale = 0.88f)` → `.curioPressBounce(pressedScale: 0.88)`),
//  the selected tab scales to 1.06 (`bounceScale`), shows a `primary@0.15` pill behind it,
//  and animates its label in/out with the `liquid` spring. Tint (`surface@0.55`) and border
//  (`onSurface@0.08`) carried verbatim. Tab role + selected state are exposed to VoiceOver
//  (Compose `Role.Tab` + `selected` → `.accessibilityAddTraits([.isButton])` +
//  `.isSelected`), so screen readers announce "<label>, selected".
//
//  Compose `.navigationBarsPadding()` → the bottom safe-area inset, supplied by the hosting
//  `GlassScaffold` via `.safeAreaInset(edge: .bottom)`; the standalone preview pads manually.
//

import SwiftUI

// MARK: - GlassNavigationItem

/// Navigation item for `GlassBottomBar`. Icons are SF Symbol names (the Compose `ImageVector`
/// analogue); `label` is the visible/selected-pill text and the VoiceOver label; `route` is the
/// selection key compared against the current route.
struct GlassNavigationItem: Identifiable, Hashable, Sendable {
    /// SF Symbol name shown when this tab is selected.
    let selectedIcon: String
    /// SF Symbol name shown when this tab is not selected.
    let unselectedIcon: String
    /// Visible label (also the accessibility label / `contentDescription`).
    let label: String
    /// Selection key compared against `currentRoute`.
    let route: String

    /// Stable identity = the route (routes are unique within a bar).
    var id: String { route }

    init(selectedIcon: String, unselectedIcon: String, label: String, route: String) {
        self.selectedIcon = selectedIcon
        self.unselectedIcon = unselectedIcon
        self.label = label
        self.route = route
    }
}

// MARK: - GlassBottomBar

/// Bottom nav bar finished in liquid glass styling, responsive to standard `GlassTier`s.
struct GlassBottomBar: View {
    let items: [GlassNavigationItem]
    let currentRoute: String
    let tier: GlassTier
    let onNavigate: (String) -> Void

    @Environment(\.curioColors) private var colors

    /// `MaterialTheme.colorScheme.surface.copy(alpha = 0.55f)`.
    private var tintColor: Color { colors.surface.opacity(0.55) }
    /// `MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)`.
    private var borderColor: Color { colors.onSurface.opacity(0.08) }

    var body: some View {
        HStack(spacing: 0) {
            // Arrangement.SpaceEvenly: each tab takes an equal weight(1f) slice.
            ForEach(items) { item in
                tab(for: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 72)
        .frame(maxWidth: .infinity)
        .glassSurface(tier: tier, tint: tintColor, borderColor: borderColor)
        // Compose wrapped the glass box in `.padding(horizontal = 16.dp, vertical = 12.dp)`.
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func tab(for item: GlassNavigationItem) -> some View {
        let isSelected = currentRoute == item.route
        let icon = isSelected ? item.selectedIcon : item.unselectedIcon
        // Selected → primary; unselected → onSurface@0.5.
        let contentColor: Color = isSelected ? colors.primary : colors.onSurface.opacity(0.5)

        Button {
            onNavigate(item.route)
        } label: {
            // The animated pill: scales to 1.06 when selected, fills with primary@0.15, and
            // pads wider (16) when selected vs 8 when not — matching the Compose inner Row.
            HStack(spacing: 0) {
                Image(systemName: icon)
                    .foregroundStyle(contentColor)
                if isSelected {
                    Text(item.label)
                        // labelLarge overridden to fontSize 13 (Compose `.copy(fontSize = 13.sp)`).
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(contentColor)
                        .padding(.leading, 6)
                        // expandHorizontally + fadeIn / shrinkHorizontally + fadeOut (liquid spring).
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0, anchor: .leading).combined(with: .opacity),
                                removal: .scale(scale: 0, anchor: .leading).combined(with: .opacity)
                            )
                        )
                }
            }
            .padding(.horizontal, isSelected ? 16 : 8)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    colors.primary.opacity(0.15)
                } else {
                    Color.clear
                }
            }
            .clipShape(Capsule())
            .bounceScale(active: isSelected, activeScale: 1.06)
            .animation(CurioMotion.liquid, value: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.curioPressBounce(pressedScale: 0.88))
        // Tab role + selected state for VoiceOver ("<label>, selected").
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

// MARK: - Preview

#Preview("Glass bottom bar") {
    ZStack(alignment: .bottom) {
        Color(argb: 0xFF08080C).ignoresSafeArea()
        GlassBottomBar(
            items: [
                GlassNavigationItem(selectedIcon: "house.fill", unselectedIcon: "house", label: "Home", route: "home"),
                GlassNavigationItem(selectedIcon: "square.grid.2x2.fill", unselectedIcon: "square.grid.2x2", label: "Spaces", route: "spaces"),
                GlassNavigationItem(selectedIcon: "bubble.left.fill", unselectedIcon: "bubble.left", label: "Chat", route: "chat")
            ],
            currentRoute: "home",
            tier: .full,
            onNavigate: { _ in }
        )
    }
    .environment(\.curioColors, .dark)
}
