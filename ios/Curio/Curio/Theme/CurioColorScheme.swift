//
//  CurioColorScheme.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/theme/Theme.kt (DarkColorScheme / LightColorScheme)
//         app/src/main/java/com/example/ui/theme/Color.kt is intentionally ignored
//         (those Purple40/80 tokens are unused dead code from the M3 template).
//
//  CONVENTIONS §8 (Theme tokens): a custom `CurioColorScheme` struct mirrors every
//  Material3 role. `static dark` / `static light` carry the EXACT Cosmic Slate hex
//  values verbatim per mode. Injected via `@Environment(\.curioColors)` resolved from
//  `@Environment(\.colorScheme)`. No Material You / dynamic color — the static palette
//  is canonical; `brandSeed` may override `primary`. Do NOT use SwiftUI semantic system
//  colors for these roles — use literal `Color(hex:)`.
//

import SwiftUI

// MARK: - Cosmic Slate palette literals
//
// These mirror the named top-level vals in Theme.kt verbatim. Kept as a caseless
// namespace so call sites (and the brand-seed accent) can reference the canonical
// accents directly, exactly like the Kotlin `val CosmicPrimary = Color(0xFFB69CFF)`.

/// Cosmic Slate Theme Palette - Bold, X-inspired contrast with vivid accents.
enum CosmicPalette {
    static let primary = Color(argb: 0xFFB69CFF)        // electric lavender accent
    static let secondary = Color(argb: 0xFF7FD7FF)      // cyan secondary pop
    static let tertiary = Color(argb: 0xFFFF9EC4)       // warm pink tertiary
    static let backgroundDark = Color(argb: 0xFF08080C) // near-black, X-style canvas
    static let surfaceDark = Color(argb: 0xFF14131A)

    static let primaryLight = Color(argb: 0xFF6750A4)
    static let secondaryLight = Color(argb: 0xFF006A78)
    static let tertiaryLight = Color(argb: 0xFFB3105E)
    static let backgroundLight = Color(argb: 0xFFFBF8FF)
    static let surfaceLight = Color(argb: 0xFFFFFFFF)
}

// MARK: - CurioColorScheme

/// Mirrors every Material3 `ColorScheme` role used across the app. The Android theme
/// builds these via `darkColorScheme(...)` / `lightColorScheme(...)`; the roles set
/// explicitly in `Theme.kt` carry their exact hex, and the remaining roles carry the
/// M3 baseline values that Compose resolves for the un-overridden slots (`primaryContainer`,
/// `onPrimaryContainer`, `error`, `onError`, etc.) so downstream lookups never read a
/// transparent/zero color.
struct CurioColorScheme: Equatable, Sendable {
    var primary: Color
    var onPrimary: Color
    var primaryContainer: Color
    var onPrimaryContainer: Color
    var secondary: Color
    var onSecondary: Color
    var secondaryContainer: Color
    var onSecondaryContainer: Color
    var tertiary: Color
    var onTertiary: Color
    var tertiaryContainer: Color
    var onTertiaryContainer: Color
    var background: Color
    var onBackground: Color
    var surface: Color
    var onSurface: Color
    var surfaceVariant: Color
    var onSurfaceVariant: Color
    var outline: Color
    var outlineVariant: Color
    var error: Color
    var onError: Color
    var errorContainer: Color
    var onErrorContainer: Color
    var inverseSurface: Color
    var inverseOnSurface: Color
    var inversePrimary: Color
    var scrim: Color
    var surfaceTint: Color
}

extension CurioColorScheme {

    /// Dark "Cosmic Slate" scheme.
    ///
    /// Roles explicitly assigned in `Theme.kt` (`DarkColorScheme`) carry their exact hex.
    /// Roles not overridden there fall back to the M3 dark baseline values that
    /// `darkColorScheme()` would resolve — preserved so no role reads as clear.
    static let dark = CurioColorScheme(
        primary: CosmicPalette.primary,                 // 0xFFB69CFF
        onPrimary: Color(argb: 0xFF1F1147),
        primaryContainer: Color(argb: 0xFF2C2150),
        onPrimaryContainer: Color(argb: 0xFFE9DDFF),
        secondary: CosmicPalette.secondary,             // 0xFF7FD7FF
        onSecondary: Color(argb: 0xFF00344A),
        // Not overridden in Theme.kt → M3 dark baseline.
        secondaryContainer: Color(argb: 0xFF334B4F),
        onSecondaryContainer: Color(argb: 0xFFCCE8E7),
        tertiary: CosmicPalette.tertiary,               // 0xFFFF9EC4
        onTertiary: Color(argb: 0xFF5A1138),
        tertiaryContainer: Color(argb: 0xFF633B48),
        onTertiaryContainer: Color(argb: 0xFFFFD8E4),
        background: CosmicPalette.backgroundDark,        // 0xFF08080C
        onBackground: Color(argb: 0xFFF2EFF7),
        surface: CosmicPalette.surfaceDark,              // 0xFF14131A
        onSurface: Color(argb: 0xFFF2EFF7),
        surfaceVariant: Color(argb: 0xFF211F2A),
        onSurfaceVariant: Color(argb: 0xFFC9C5D4),
        outline: Color(argb: 0xFF49454F),
        // M3 dark baseline.
        outlineVariant: Color(argb: 0xFF49454F),
        error: Color(argb: 0xFFFFB4AB),
        onError: Color(argb: 0xFF690005),
        errorContainer: Color(argb: 0xFF93000A),
        onErrorContainer: Color(argb: 0xFFFFDAD6),
        inverseSurface: Color(argb: 0xFFF2EFF7),
        inverseOnSurface: Color(argb: 0xFF313033),
        inversePrimary: Color(argb: 0xFF6750A4),
        scrim: Color(argb: 0xFF000000),
        surfaceTint: CosmicPalette.primary
    )

    /// Light "Cosmic Slate" scheme.
    ///
    /// Roles explicitly assigned in `Theme.kt` (`LightColorScheme`) carry their exact hex.
    /// `onPrimary/onSecondary/onTertiary = Color.White` are explicit there; the remaining
    /// non-overridden roles fall back to the M3 light baseline.
    static let light = CurioColorScheme(
        primary: CosmicPalette.primaryLight,            // 0xFF6750A4
        onPrimary: Color(argb: 0xFFFFFFFF),             // Color.White
        // Not overridden in Theme.kt → M3 light baseline.
        primaryContainer: Color(argb: 0xFFEADDFF),
        onPrimaryContainer: Color(argb: 0xFF21005D),
        secondary: CosmicPalette.secondaryLight,        // 0xFF006A78
        onSecondary: Color(argb: 0xFFFFFFFF),           // Color.White
        secondaryContainer: Color(argb: 0xFFA6EEFF),
        onSecondaryContainer: Color(argb: 0xFF001F25),
        tertiary: CosmicPalette.tertiaryLight,          // 0xFFB3105E
        onTertiary: Color(argb: 0xFFFFFFFF),            // Color.White
        tertiaryContainer: Color(argb: 0xFFFFD9E2),
        onTertiaryContainer: Color(argb: 0xFF3E001D),
        background: CosmicPalette.backgroundLight,       // 0xFFFBF8FF
        onBackground: Color(argb: 0xFF15131C),
        surface: CosmicPalette.surfaceLight,             // 0xFFFFFFFF
        onSurface: Color(argb: 0xFF15131C),
        surfaceVariant: Color(argb: 0xFFEDE7F4),
        onSurfaceVariant: Color(argb: 0xFF49454F),
        outline: Color(argb: 0xFF7A757F),
        outlineVariant: Color(argb: 0xFFCAC4D0),
        error: Color(argb: 0xFFBA1A1A),
        onError: Color(argb: 0xFFFFFFFF),
        errorContainer: Color(argb: 0xFFFFDAD6),
        onErrorContainer: Color(argb: 0xFF410002),
        inverseSurface: Color(argb: 0xFF313033),
        inverseOnSurface: Color(argb: 0xFFF4EFF4),
        inversePrimary: Color(argb: 0xFFD0BCFF),
        scrim: Color(argb: 0xFF000000),
        surfaceTint: CosmicPalette.primaryLight
    )

    /// Resolves the canonical scheme for the active SwiftUI color scheme, then applies an
    /// optional `brandSeed` override on `primary` (and `surfaceTint`) — the iOS analogue of
    /// `BookmarkTheme(brandSeed:)`, which keeps the Cosmic background/surface and only
    /// swaps the primary accent.
    static func resolve(dark isDark: Bool, brandSeed: Color? = nil) -> CurioColorScheme {
        var scheme = isDark ? CurioColorScheme.dark : CurioColorScheme.light
        if let seed = brandSeed {
            scheme.primary = seed
            scheme.surfaceTint = seed
        }
        return scheme
    }
}

// MARK: - Color(argb:) literal helper
//
// CONVENTIONS §8 / §10 (ARGB): packed ARGB stays `Int64` through domain/persistence and
// is unpacked to `Color(.sRGB, …)` only at the SwiftUI boundary. This is that single
// boundary helper. Theme tokens are written as `0xAARRGGBB` literals exactly like the
// Kotlin `Color(0xFF…)` constructor (alpha is the top byte). Gamma matches Compose's
// sRGB color space.

extension Color {

    /// Builds a `Color` from a packed `0xAARRGGBB` value (alpha in the high byte),
    /// matching Jetpack Compose's `Color(0xAARRGGBB)` constructor byte-for-byte.
    init(argb value: UInt32) {
        let alpha = Double((value >> 24) & 0xFF) / 255.0
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Unpacks an `Int64` packed ARGB color (the domain/persistence representation of
    /// `Space.color` / `CategorySpaceMeta.color`) into a `Color`. Masks to the low 32 bits.
    init(packedARGB value: Int64) {
        self.init(argb: UInt32(truncatingIfNeeded: value))
    }
}

// MARK: - Environment injection

private struct CurioColorsKey: EnvironmentKey {
    // Default to dark to match the app's X-style canvas default before a `CurioTheme`
    // wrapper resolves the active scheme.
    static let defaultValue: CurioColorScheme = .dark
}

extension EnvironmentValues {
    /// The active Cosmic Slate color scheme, injected by `CurioTheme` and resolved from
    /// the system `colorScheme`. Read with `@Environment(\.curioColors) private var colors`.
    var curioColors: CurioColorScheme {
        get { self[CurioColorsKey.self] }
        set { self[CurioColorsKey.self] = newValue }
    }
}
