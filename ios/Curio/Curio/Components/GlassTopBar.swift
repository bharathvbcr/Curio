//
//  GlassTopBar.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/components/GlassTopBar.kt (GlassTopBar).
//
//  CONVENTIONS §8 (Theme/Liquid-Glass): top bar finished in liquid-glass styling, responsive
//  to the standard `GlassTier`. The tint (`surface@0.55`) and hairline border (`onSurface@0.08`)
//  are carried verbatim from the Compose source. Compose `.statusBarsPadding()` → SwiftUI
//  safe-area top inset (applied by callers via `.safeAreaInset`); the bar itself pads the
//  status-bar inset only when used standalone — here we expose the same 64pt content box and
//  let `GlassScaffold`'s `.safeAreaInset(edge: .top)` host it (CONVENTIONS §8 Layout/insets).
//
//  The title uses the `titleLarge` role overridden to fontSize 20 / Bold / onSurface, matching
//  `MaterialTheme.typography.titleLarge.copy(fontWeight = Bold, fontSize = 20.sp, color = onSurface)`.
//

import SwiftUI

/// Top bar finished in liquid glass styling, responsive to standard `GlassTier`s.
///
/// Generic over the leading (navigation) and trailing (actions) content so call sites can pass
/// `EmptyView` when absent (mirrors the Kotlin nullable `@Composable` slots).
struct GlassTopBar<NavigationIcon: View, Actions: View>: View {
    let title: String
    let tier: GlassTier
    @ViewBuilder var navigationIcon: () -> NavigationIcon
    @ViewBuilder var actions: () -> Actions

    @Environment(\.curioColors) private var colors

    /// `MaterialTheme.colorScheme.surface.copy(alpha = 0.55f)`.
    private var tintColor: Color { colors.surface.opacity(0.55) }
    /// `MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)`.
    private var borderColor: Color { colors.onSurface.opacity(0.08) }

    var body: some View {
        HStack(spacing: 0) {
            navigationIcon()
            Text(title)
                // titleLarge @ 20pt Bold, onSurface — matches the Compose `.copy(...)`.
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(colors.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            actions()
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .glassSurface(tier: tier, tint: tintColor, borderColor: borderColor)
        // Compose wrapped the glass box in `.padding(horizontal = 16.dp, vertical = 8.dp)`
        // (outside the surface). `.statusBarsPadding()` is provided by the hosting safe-area
        // inset; standalone use should add `.padding(.top, safeAreaTop)` at the call site.
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Convenience initializers

extension GlassTopBar where NavigationIcon == EmptyView, Actions == EmptyView {
    /// Title-only top bar (both slots empty), mirroring the Kotlin defaults `navigationIcon = null`,
    /// `actions = null`.
    init(title: String, tier: GlassTier) {
        self.init(title: title, tier: tier, navigationIcon: { EmptyView() }, actions: { EmptyView() })
    }
}

extension GlassTopBar where NavigationIcon == EmptyView {
    /// Top bar with trailing actions but no leading navigation icon.
    init(title: String, tier: GlassTier, @ViewBuilder actions: @escaping () -> Actions) {
        self.init(title: title, tier: tier, navigationIcon: { EmptyView() }, actions: actions)
    }
}

extension GlassTopBar where Actions == EmptyView {
    /// Top bar with a leading navigation icon but no trailing actions.
    init(title: String, tier: GlassTier, @ViewBuilder navigationIcon: @escaping () -> NavigationIcon) {
        self.init(title: title, tier: tier, navigationIcon: navigationIcon, actions: { EmptyView() })
    }
}

// MARK: - Preview

#Preview("Glass top bar") {
    ZStack(alignment: .top) {
        Color(argb: 0xFF08080C).ignoresSafeArea()
        GlassTopBar(title: "Curio", tier: .full)
    }
    .environment(\.curioColors, .dark)
}
