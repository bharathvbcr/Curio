//
//  LiquidGlassFab.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/components/LiquidGlassFab.kt (LiquidGlassFab).
//
//  CONVENTIONS §8 (Theme/Liquid-Glass + Motion): a 64pt circular liquid-glass FAB with an
//  iOS-style bouncy press response (`pressBounce(pressedScale = 0.86f)` →
//  `.curioPressBounce(pressedScale: 0.86)`) and a soft accent-tinted frosted body. The glass
//  recipe is carried verbatim: `tint = primary@0.24`, `borderColor = primary@0.4`,
//  `edgeSheenColor = white@0.55`, on a `CircleShape`. Default icon is the Sync glyph
//  (`Icons.Default.Sync` → SF Symbol `arrow.triangle.2.circlepath`) tinted `primary`, with the
//  Compose `contentDescription = "Sync"` carried to `.accessibilityLabel`.
//

import SwiftUI

/// Liquid-glass Floating Action Button with an iOS-style bouncy press response and a soft
/// accent-tinted frosted body.
///
/// Generic over the icon content so call sites can supply any glyph (mirrors the Kotlin
/// `icon: @Composable () -> Unit` slot, defaulting to the Sync symbol).
struct LiquidGlassFab<Icon: View>: View {
    let onClick: () -> Void
    let tier: GlassTier
    @ViewBuilder var icon: () -> Icon

    @Environment(\.curioColors) private var colors

    var body: some View {
        Button(action: onClick) {
            icon()
                .frame(width: 64, height: 64)
                .glassSurface(
                    tier: tier,
                    shape: Circle(),
                    tint: colors.primary.opacity(0.24),
                    borderColor: colors.primary.opacity(0.4),
                    edgeSheenColor: Color.white.opacity(0.55)
                )
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.curioPressBounce(pressedScale: 0.86))
    }
}

// MARK: - Default-icon convenience

extension LiquidGlassFab where Icon == DefaultSyncIcon {
    /// FAB with the default Sync icon (`Icons.Default.Sync` → `arrow.triangle.2.circlepath`),
    /// tinted `primary`, labeled "Sync" — mirroring the Kotlin default `icon` slot.
    init(onClick: @escaping () -> Void, tier: GlassTier) {
        self.init(onClick: onClick, tier: tier, icon: { DefaultSyncIcon() })
    }
}

/// The default FAB glyph: the Sync symbol tinted `primary` with the "Sync" accessibility label.
struct DefaultSyncIcon: View {
    @Environment(\.curioColors) private var colors

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .foregroundStyle(colors.primary)
            .accessibilityLabel("Sync")
    }
}

// MARK: - Preview

#Preview("Liquid glass FAB") {
    ZStack {
        Color(argb: 0xFF08080C).ignoresSafeArea()
        LiquidGlassFab(onClick: {}, tier: .full)
    }
    .environment(\.curioColors, .dark)
}
