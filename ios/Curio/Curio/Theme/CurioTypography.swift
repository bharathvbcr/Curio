//
//  CurioTypography.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/theme/Type.kt (the bold Material3 `Typography`).
//
//  CONVENTIONS §8 (Typography): `CurioFont` role factories return `(Font, tracking, lineSpacing)`;
//  apply `.font()` + `.tracking()` + `.lineSpacing()` together via a `.curioText(_:)` modifier.
//  Heavy weights (Black/ExtraBold) and ALL-CAPS + wide tracking are intentional — apply
//  `.textCase(.uppercase)` + `.tracking()` explicitly. Sizes/weights/tracking are exact.
//
//  Mapping notes (Compose → SwiftUI):
//   - Compose `fontSize` (sp)        → point size (system font, default family == SF).
//   - Compose `letterSpacing` (sp)   → `.tracking()` in points (1 sp ≈ 1 pt at the role size).
//   - Compose `lineHeight` (sp)      → carried as `lineHeight`; `lineSpacing` (the EXTRA gap
//                                       SwiftUI adds between lines) is derived as
//                                       `lineHeight - fontSize`, floored at 0, so multi-line
//                                       text reproduces Compose's line box height.
//   - Compose `FontWeight.Black`     → `.black`, `ExtraBold` → `.heavy`, `Bold` → `.bold`,
//                                       `Medium` → `.medium`, `Normal` → `.regular`.
//     (SwiftUI has no distinct "ExtraBold"; `.heavy` is the closest standard weight below
//      `.black`, preserving the Black > ExtraBold > Bold ordering Compose intends.)
//

import SwiftUI

/// A fully-specified Curio text style mirroring one Material3 `TextStyle` role.
/// Carries the exact size / weight / tracking / line metrics ported from `Type.kt`.
struct CurioTextStyle: Equatable, Sendable {
    /// Point size (Compose `fontSize.sp`).
    let size: CGFloat
    /// Standard system weight mapped from the Compose `FontWeight`.
    let weight: Font.Weight
    /// Letter spacing in points (Compose `letterSpacing.sp`). May be negative (tight display).
    let tracking: CGFloat
    /// Target line-box height in points (Compose `lineHeight.sp`).
    let lineHeight: CGFloat

    /// The resolved SwiftUI font for this role (system family, matching `FontFamily.Default`).
    var font: Font { .system(size: size, weight: weight) }

    /// Extra inter-line spacing SwiftUI must add to reproduce Compose's `lineHeight`
    /// (SwiftUI `.lineSpacing` is additive on top of the natural line height; we approximate
    /// the line box as `lineHeight - size`, never negative).
    var lineSpacing: CGFloat { max(0, lineHeight - size) }
}

// MARK: - CurioFont role registry

/// Bold type scale optimized for the X-inspired Curio look. One static role per Material3
/// `Typography` slot, with the exact values from `Type.kt`.
enum CurioFont {

    // Display — FontWeight.Black, tight negative tracking.
    static let displayLarge  = CurioTextStyle(size: 57, weight: .black, tracking: -1.5, lineHeight: 64)
    static let displayMedium = CurioTextStyle(size: 45, weight: .black, tracking: -1.0, lineHeight: 52)
    static let displaySmall  = CurioTextStyle(size: 36, weight: .black, tracking: -1.0, lineHeight: 44)

    // Headline — Black (large) then ExtraBold (medium/small).
    static let headlineLarge  = CurioTextStyle(size: 32, weight: .black, tracking: -1.0, lineHeight: 40)
    static let headlineMedium = CurioTextStyle(size: 28, weight: .heavy, tracking: -0.5, lineHeight: 36)
    static let headlineSmall  = CurioTextStyle(size: 24, weight: .heavy, tracking: -0.5, lineHeight: 32)

    // Title — Black (large/medium) then Bold (small).
    static let titleLarge  = CurioTextStyle(size: 22, weight: .black, tracking: -0.5, lineHeight: 28)
    static let titleMedium = CurioTextStyle(size: 18, weight: .black, tracking: -0.2, lineHeight: 24)
    static let titleSmall  = CurioTextStyle(size: 14, weight: .bold,  tracking:  0.0, lineHeight: 20)

    // Body — Normal (large), Medium (medium); positive tracking.
    static let bodyLarge  = CurioTextStyle(size: 16, weight: .regular, tracking: 0.5,  lineHeight: 24)
    static let bodyMedium = CurioTextStyle(size: 14, weight: .medium,  tracking: 0.25, lineHeight: 20)

    // Label — Bold (large), ExtraBold (small); small caps style with wide tracking.
    static let labelLarge = CurioTextStyle(size: 14, weight: .bold,  tracking: 0.1, lineHeight: 20)
    static let labelSmall = CurioTextStyle(size: 11, weight: .heavy, tracking: 1.0, lineHeight: 16)
}

// MARK: - .curioText(_:) modifier

private struct CurioTextModifier: ViewModifier {
    let style: CurioTextStyle

    func body(content: Content) -> some View {
        content
            .font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
    }
}

extension View {
    /// Applies a Curio type role's font, tracking, and line spacing together.
    /// For ALL-CAPS label roles, pair with `.textCase(.uppercase)` at the call site
    /// (the role tracking — e.g. `labelSmall`'s `1.0` — is already tuned for caps).
    func curioText(_ style: CurioTextStyle) -> some View {
        modifier(CurioTextModifier(style: style))
    }
}
