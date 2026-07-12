//
//  CurioLogo.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/components/CurioLogo.kt
//         (CurioLogoMark, the private `curioMarkPath` geometry).
//
//  CONVENTIONS §8 (Theme/Liquid-Glass) + DESIGN: the brand mark is the SAME 108x108
//  geometry as the launcher icon (res/drawable/ic_launcher_foreground.xml) so the in-app
//  logo and the home-screen icon are pixel-identical in shape. The spark is a genuine
//  even-odd hole (`.evenOdd` fill), so whatever sits behind the mark shows through it.
//
//  Compose `Canvas { drawPath(curioMarkPath(size, paddingFraction)) }` becomes a
//  `Shape` (`CurioMarkShape`) so the path math is reused verbatim and the even-odd
//  spark cutout is preserved (`Path(eoFill: true)` → SwiftUI fills with `.evenOdd`).
//  Theme-aware tint defaults to `onSurface` (read via `\.curioColors`),
//  mirroring the Material `MaterialTheme.colorScheme` defaults in Kotlin.
//

import SwiftUI

// MARK: - CurioMarkShape

/// The bookmark + spark brand path, authored in the bookmark's 108-viewport bounding box
/// (x:37..71, y:30..80) so it lines up 1:1 with the vector drawable. Scaled to fit the
/// supplied `rect` (aspect-preserved, centered) with `paddingFraction` breathing room on the
/// limiting axis. The spark is a four-point star knocked out of the ribbon via even-odd fill.
///
/// Verbatim port of the private `curioMarkPath(size:paddingFraction:)` in CurioLogo.kt; the
/// Compose `quadraticTo(cx, cy, x, y)` maps to `path.addQuadCurve(to:control:)`.
struct CurioMarkShape: Shape {
    /// Breathing-room margin on the limiting axis, as a fraction of that axis. Compose default
    /// for the bare mark is `0.04`.
    var paddingFraction: CGFloat = 0.04

    func path(in rect: CGRect) -> Path {
        let originX: CGFloat = 37
        let originY: CGFloat = 30
        let markW: CGFloat = 34 // 71 - 37
        let markH: CGFloat = 50 // 80 - 30

        let scale = min(
            rect.width * (1 - 2 * paddingFraction) / markW,
            rect.height * (1 - 2 * paddingFraction) / markH
        )
        let offsetX = (rect.width - markW * scale) / 2
        let offsetY = (rect.height - markH * scale) / 2

        // Account for the rect origin (SwiftUI shapes may be offset from 0,0).
        func x(_ v: CGFloat) -> CGFloat { rect.minX + offsetX + (v - originX) * scale }
        func y(_ v: CGFloat) -> CGFloat { rect.minY + offsetY + (v - originY) * scale }

        var path = Path()

        // Bookmark ribbon with rounded top corners and a V-notch tail.
        path.move(to: CGPoint(x: x(46), y: y(30)))
        path.addLine(to: CGPoint(x: x(62), y: y(30)))
        path.addQuadCurve(to: CGPoint(x: x(71), y: y(39)), control: CGPoint(x: x(71), y: y(30)))
        path.addLine(to: CGPoint(x: x(71), y: y(80)))
        path.addLine(to: CGPoint(x: x(54), y: y(66)))
        path.addLine(to: CGPoint(x: x(37), y: y(80)))
        path.addLine(to: CGPoint(x: x(37), y: y(39)))
        path.addQuadCurve(to: CGPoint(x: x(46), y: y(30)), control: CGPoint(x: x(37), y: y(30)))
        path.closeSubpath()

        // Four-point AI spark — knocked out of the ribbon via even-odd fill. Verbatim port of
        // the four Compose `quadraticTo(cx, cy, x, y)` calls (control then end point).
        path.move(to: CGPoint(x: x(54), y: y(35)))
        path.addQuadCurve(to: CGPoint(x: x(67), y: y(48)), control: CGPoint(x: x(56.40), y: y(45.60)))
        path.addQuadCurve(to: CGPoint(x: x(54), y: y(61)), control: CGPoint(x: x(56.40), y: y(50.40)))
        path.addQuadCurve(to: CGPoint(x: x(41), y: y(48)), control: CGPoint(x: x(51.60), y: y(50.40)))
        path.addQuadCurve(to: CGPoint(x: x(54), y: y(35)), control: CGPoint(x: x(51.60), y: y(45.60)))
        path.closeSubpath()

        return path
    }
}

// MARK: - CurioLogoMark

/// Curio brand mark: a bookmark ribbon with an AI "spark" knocked out of it.
///
/// Drawn with the same 108x108 geometry as the launcher icon, so the in-app logo and the
/// home-screen icon are pixel-identical in shape. The spark is a genuine even-odd hole, so
/// whatever sits behind the mark shows through it. `tint` defaults to the Cosmic `onSurface`
/// (mirrors Compose `MaterialTheme.colorScheme.onSurface`), flipping white-on-dark /
/// dark-on-light automatically.
struct CurioLogoMark: View {
    var tint: Color? = nil
    var paddingFraction: CGFloat = 0.04

    @Environment(\.curioColors) private var colors

    var body: some View {
        CurioMarkShape(paddingFraction: paddingFraction)
            .fill(tint ?? colors.onSurface, style: FillStyle(eoFill: true))
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Bare mark — dark") {
    CurioLogoMark()
        .frame(width: 72, height: 72)
        .padding()
        .background(Color(argb: 0xFF141218))
        .environment(\.curioColors, .dark)
}

#Preview("Bare mark — light") {
    CurioLogoMark()
        .frame(width: 72, height: 72)
        .padding()
        .background(Color(argb: 0xFFFEF7FF))
        .environment(\.curioColors, .light)
}
