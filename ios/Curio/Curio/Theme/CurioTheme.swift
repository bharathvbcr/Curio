//
//  CurioTheme.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/theme/Theme.kt (BookmarkTheme).
//
//  CONVENTIONS §8 (Theme tokens): root theme wrapper that resolves the Cosmic Slate scheme
//  from the active `colorScheme`, applies an optional `brandSeed` primary override, injects
//  `\.curioColors`, and sets `preferredColorScheme`. Material You / dynamicColor is dropped —
//  the static palette is canonical. Typography is applied per-view via `.curioText(_:)`
//  (no global font environment in SwiftUI), so this wrapper only owns color + scheme.
//
//  The Android `darkTheme: Boolean = isSystemInDarkTheme()` is mirrored by an optional
//  `darkTheme` override: when `nil` (the default) the system scheme is honored; when set it
//  forces dark/light (used by the in-app Theme setting: System / Light / Dark).
//

import SwiftUI

// MARK: - CurioTheme view wrapper

/// Root theme wrapper. Resolves and injects the Cosmic Slate `CurioColorScheme`, optionally
/// forces a color scheme, and applies the `brandSeed` accent override. Equivalent to
/// `BookmarkTheme(darkTheme:dynamicColor:brandSeed:content:)` minus dynamic color.
struct CurioTheme<Content: View>: View {
    /// Forced color scheme. `nil` honors the system setting (`isSystemInDarkTheme()` analogue).
    var darkTheme: Bool?
    /// Optional brand accent that overrides `primary` (and `surfaceTint`) while keeping the
    /// Cosmic background/surface — mirrors `BookmarkTheme(brandSeed:)`.
    var brandSeed: Color?
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var systemColorScheme

    init(darkTheme: Bool? = nil, brandSeed: Color? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.darkTheme = darkTheme
        self.brandSeed = brandSeed
        self.content = content
    }

    /// Whether dark mode is effective: the override if present, else the system scheme.
    private var isDark: Bool {
        darkTheme ?? (systemColorScheme == .dark)
    }

    private var colors: CurioColorScheme {
        CurioColorScheme.resolve(dark: isDark, brandSeed: brandSeed)
    }

    var body: some View {
        content()
            .environment(\.curioColors, colors)
            // Surface the canonical background under everything so edge-to-edge content
            // reads against the Cosmic canvas, matching the M3 `background` role.
            .background(colors.background.ignoresSafeArea())
            .tint(colors.primary)
            // Only force a scheme when explicitly overridden; nil → follow the system.
            .preferredColorScheme(darkTheme.map { $0 ? .dark : .light })
    }
}

// MARK: - .curioTheme(...) modifier

private struct CurioThemeModifier: ViewModifier {
    var darkTheme: Bool?
    var brandSeed: Color?

    func body(content: Content) -> some View {
        CurioTheme(darkTheme: darkTheme, brandSeed: brandSeed) {
            content
        }
    }
}

extension View {
    /// Applies the Curio theme (Cosmic Slate colors + optional forced scheme + brand seed).
    /// Mirrors `BookmarkTheme(darkTheme:brandSeed:)`; `dynamicColor` is intentionally absent.
    ///
    /// - Parameters:
    ///   - darkTheme: `nil` follows the system scheme; `true`/`false` forces dark/light
    ///     (the in-app System / Dark / Light setting maps to `nil` / `true` / `false`).
    ///   - brandSeed: optional accent overriding `primary`.
    func curioTheme(darkTheme: Bool? = nil, brandSeed: Color? = nil) -> some View {
        modifier(CurioThemeModifier(darkTheme: darkTheme, brandSeed: brandSeed))
    }
}
