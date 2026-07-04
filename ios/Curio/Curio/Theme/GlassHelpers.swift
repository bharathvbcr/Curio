//
//  GlassHelpers.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/theme/GlassHelpers.kt
//         (GlassTier, GlassTokens, rememberGlassTier, Modifier.glassSurface, curioAccentBrush).
//
//  CONVENTIONS §8 (Glass): `GlassTier { full, blur, solid }`. Full/Blur use native iOS 26
//  `.glassEffect(_:in:)` (samples the backdrop automatically, keeps children crisp — the Haze
//  machinery is dropped). Solid (and Reduce Transparency) uses an opaque manual recipe
//  (translucent fill, no specular/blur). The `glassSurface(...)` ViewModifier carries the
//  EXACT per-mode alphas/hex (tint, specular, top light line, hairline border) VERBATIM.
//  Every native-glass API is behind `#available(iOS 26, *)` with a `.ultraThinMaterial`
//  fallback. Honor `accessibilityReduceTransparency` (→ Solid/opaque).
//
//  The manual recipe below replicates the Android layering bottom→top:
//    1. translucent tint fill (the "frost") — a vertical gradient tint → tint·0.65α
//    2. a diagonal specular sheen (top-left bright → transparent)
//    3. a crisp 1px top-edge light line
//    4. a hairline border
//

import SwiftUI

// MARK: - GlassTier

/// Performance / accessibility tiers for dynamic glass rendering.
/// - `full`:  refraction gradients & specular highlight (native iOS 26 glass).
/// - `blur`:  frosted haze with standard rendering (native iOS 26 glass).
/// - `solid`: high-performance simple-opacity card with border highlights (manual recipe;
///            also the Reduce-Transparency fallback).
///
/// Lowercased cases (Swift convention); the Android enum was `Full/Blur/Solid`.
enum GlassTier: Sendable {
    case full
    case blur
    case solid
}

// MARK: - GlassTokens

/// Shape tokens shared by glass surfaces. Mirrors the Compose `RoundedCornerShape` dp values.
enum GlassTokens {
    /// Container corner radius (Compose `RoundedCornerShape(24.dp)`).
    static let containerCornerRadius: CGFloat = 24
    /// Card corner radius (Compose `RoundedCornerShape(22.dp)`).
    static let cardCornerRadius: CGFloat = 22

    /// Container shape (rounded rectangle, continuous corners for the Liquid-Glass look).
    static var containerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: containerCornerRadius, style: .continuous)
    }
    /// Card shape.
    static var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
    }
}

// MARK: - Tier resolution

/// Picks the safest glass rendering tier.
///
/// Android `rememberGlassTier` keyed off low-RAM + SDK level. On iOS, the load-bearing
/// gate is accessibility: **Reduce Transparency forces `.solid`** (opaque, no specular/blur).
/// Otherwise native iOS 26 glass is available → `.full`; pre-26 devices degrade to `.blur`
/// (which falls back to `.ultraThinMaterial` in the modifier). An explicit `override` always
/// wins, exactly like the Android signature.
@MainActor
func resolveGlassTier(override: GlassTier? = nil, reduceTransparency: Bool) -> GlassTier {
    if let override { return override }
    if reduceTransparency { return .solid }
    if #available(iOS 26, *) {
        return .full
    } else {
        return .blur
    }
}

// MARK: - glassSurface modifier

private struct GlassSurfaceModifier<S: Shape>: ViewModifier {
    let tier: GlassTier
    let shape: S
    let tint: Color?
    let borderColor: Color?
    let edgeSheenColor: Color?
    let highlight: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isDark: Bool { colorScheme == .dark }

    /// Per-tier base opacity for the frost tint — verbatim from `glassSurface`.
    private var opacity: Double {
        switch tier {
        case .full:  return isDark ? 0.34 : 0.20
        case .blur:  return isDark ? 0.26 : 0.14
        case .solid: return isDark ? 0.42 : 0.26
        }
    }

    /// Resolved tint fill. Android: dark → `Color(0xFF1D1B20).copy(alpha = opacity)`,
    /// light → `Color.White.copy(alpha = opacity)`.
    private var resolvedTint: Color {
        if let tint { return tint }
        return isDark
            ? Color(argb: 0xFF1D1B20).opacity(opacity)
            : Color.white.opacity(opacity)
    }

    /// The default tint's effective alpha (the tier `opacity`), used to derive the frost
    /// gradient's lower stop (×0.65). For a custom `tint` the lower stop is computed by
    /// scaling the supplied color's opacity directly (see `manualFill`).
    private var tintAlpha: Double { opacity }

    /// Resolved hairline border. Android: dark → white@0.14, light → black@0.07.
    private var resolvedBorder: Color {
        if let borderColor { return borderColor }
        return isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.07)
    }

    /// Resolved top-edge light line. Android: dark → white@0.18, light → white@0.5.
    private var resolvedSheen: Color {
        if let edgeSheenColor { return edgeSheenColor }
        return isDark ? Color.white.opacity(0.18) : Color.white.opacity(0.5)
    }

    /// Diagonal specular top color. Scales with tier so Solid stays cheap (transparent).
    /// Android: highlight && tier != Solid → dark white@0.10 / light white@0.38, else transparent.
    private var specularTop: Color {
        if highlight && tier != .solid {
            return isDark ? Color.white.opacity(0.10) : Color.white.opacity(0.38)
        }
        return .clear
    }

    func body(content: Content) -> some View {
        // Native iOS 26 glass for Full/Blur when transparency is allowed; else the manual
        // recipe (also the Reduce-Transparency / Solid path).
        if tier != .solid, !reduceTransparency, #available(iOS 26, *) {
            // Native Liquid Glass. `Glass.tint(_:)` takes an optional `Color?`, so passing a
            // `nil` tint yields plain `.regular` (the native effect samples the backdrop itself
            // — no manual frost needed); a non-nil tint colors the glass.
            let glass: Glass = Glass.regular.tint(tint)
            content
                .glassEffect(glass, in: shape)
        } else if tier != .solid, !reduceTransparency {
            // Pre-iOS-26 fallback: a real material backdrop + the manual sheen/border.
            content
                .background(.ultraThinMaterial, in: shape)
                .modifier(ManualGlassDecorations(
                    shape: shape,
                    resolvedSheen: resolvedSheen,
                    resolvedBorder: resolvedBorder,
                    specularTop: specularTop
                ))
        } else {
            // Solid / Reduce-Transparency: opaque manual recipe, no blur, no specular.
            content
                .background(manualFill, in: shape)
                .modifier(ManualGlassDecorations(
                    shape: shape,
                    resolvedSheen: resolvedSheen,
                    resolvedBorder: resolvedBorder,
                    // Specular is already forced transparent for Solid via `specularTop`.
                    specularTop: specularTop
                ))
        }
    }

    /// The bottom frost layer — a vertical gradient from the tint to tint·0.65 alpha,
    /// matching `Brush.verticalGradient(listOf(resolvedTint, resolvedTint.copy(alpha = α*0.65)))`.
    private var manualFill: LinearGradient {
        let top = resolvedTint
        let bottom: Color = (tint == nil)
            ? (isDark ? Color(argb: 0xFF1D1B20).opacity(tintAlpha * 0.65)
                      : Color.white.opacity(tintAlpha * 0.65))
            : top.opacity(0.65)
        return LinearGradient(
            colors: [top, bottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Shared specular sheen + top light line + hairline border, drawn over whatever base
/// (native glass fallback or solid fill) sits beneath. Replicates the Android linear-gradient
/// specular, the `drawBehind` top line (1.5× a 1pt stroke), and the 1pt clipped border.
private struct ManualGlassDecorations<S: Shape>: ViewModifier {
    let shape: S
    let resolvedSheen: Color
    let resolvedBorder: Color
    let specularTop: Color

    func body(content: Content) -> some View {
        content
            .overlay {
                // 2. Diagonal specular: top-left bright → transparent → transparent.
                //    Android used start = Offset.Zero, end = Offset(420f, 520f) in px; the
                //    direction (top-leading → ~bottom-trailing, slightly steeper than 45°)
                //    is preserved via unit points.
                LinearGradient(
                    stops: [
                        .init(color: specularTop, location: 0.0),
                        .init(color: .clear, location: 0.5),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: UnitPoint(x: 420.0 / 520.0, y: 1.0)
                )
                .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                // 3. Crisp top-edge light line: a 1.5pt-tall sheen line across the top edge
                //    (Android drew a horizontal line at y=0 with strokeWidth = 1pt × 1.5).
                resolvedSheen
                    .frame(height: 1.5)
                    .allowsHitTesting(false)
            }
            .clipShape(shape)
            .overlay {
                // 4. Hairline border (1pt), clipped to the shape. `.stroke` (not
                //    `strokeBorder`) so this works for any `Shape`, not only insettable ones;
                //    the outer `.clipShape` trims the half of the stroke that bleeds outside.
                shape.stroke(resolvedBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    /// Custom glass surface modifier. Full/Blur render native iOS 26 Liquid Glass (keeping
    /// children crisp); Solid (and Reduce Transparency) render the opaque manual recipe with
    /// the exact per-mode tint / specular / sheen / border alphas ported from `Modifier.glassSurface`.
    ///
    /// - Parameters mirror the Android signature one-for-one; `nil` color params resolve to the
    ///   documented per-mode defaults.
    func glassSurface<S: Shape>(
        tier: GlassTier,
        shape: S,
        tint: Color? = nil,
        borderColor: Color? = nil,
        edgeSheenColor: Color? = nil,
        highlight: Bool = true
    ) -> some View {
        modifier(GlassSurfaceModifier(
            tier: tier,
            shape: shape,
            tint: tint,
            borderColor: borderColor,
            edgeSheenColor: edgeSheenColor,
            highlight: highlight
        ))
    }

    /// Convenience overload defaulting to the container shape (Compose default was
    /// `GlassTokens.containerShape`).
    func glassSurface(
        tier: GlassTier,
        tint: Color? = nil,
        borderColor: Color? = nil,
        edgeSheenColor: Color? = nil,
        highlight: Bool = true
    ) -> some View {
        glassSurface(
            tier: tier,
            shape: GlassTokens.containerShape,
            tint: tint,
            borderColor: borderColor,
            edgeSheenColor: edgeSheenColor,
            highlight: highlight
        )
    }
}

// MARK: - Accent brush

/// A vivid, theme-driven accent gradient. Pairs the primary with the tertiary for the bold
/// X-style highlight moments (FAB, send button, hero numbers, active chips).
///
/// Ports `curioAccentBrush(primary, tertiary)`:
///   `Brush.linearGradient(listOf(primary, lerpToward(primary, tertiary, 0.6f)), Offset.Zero, Offset(360,360))`
/// where `lerpToward` interpolates RGB at t=0.6 and forces alpha = 1.
func curioAccentBrush(primary: Color, tertiary: Color) -> LinearGradient {
    LinearGradient(
        colors: [primary, lerpToward(primary, tertiary, 0.6)],
        startPoint: .topLeading,        // Offset.Zero
        endPoint: .bottomTrailing       // Offset(360, 360) — a clean 45° diagonal
    )
}

/// Linearly interpolates two colors' RGB channels at `t`, forcing alpha to 1 — verbatim port
/// of the private `lerpToward(a, b, t)` in GlassHelpers.kt.
private func lerpToward(_ a: Color, _ b: Color, _ t: Double) -> Color {
    let ca = a.resolvedRGBA
    let cb = b.resolvedRGBA
    return Color(
        .sRGB,
        red: ca.red + (cb.red - ca.red) * t,
        green: ca.green + (cb.green - ca.green) * t,
        blue: ca.blue + (cb.blue - ca.blue) * t,
        opacity: 1.0
    )
}

// MARK: - Color RGBA resolution

private extension Color {
    /// Resolves this color's sRGB components for interpolation. Uses the platform
    /// `UIColor` bridge so dynamic/asset colors resolve to concrete channels.
    var resolvedRGBA: (red: Double, green: Double, blue: Double, alpha: Double) {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
        #else
        return (0, 0, 0, 1)
        #endif
    }
}
