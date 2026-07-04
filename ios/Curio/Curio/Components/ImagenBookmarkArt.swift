//
//  ImagenBookmarkArt.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/ImagenBookmarkArt.kt (ImagenBookmarkArt).
//
//  A 3-state bookmark cover:
//   1. A real Grok-generated image (`isGenerated && imageUrl` non-blank) — takes precedence;
//      rendered via `AsyncImage` with a "GROK IMAGINE" badge.
//   2. The generate call-to-action (`!isGenerated`) — a tappable sparkle + copy.
//   3. A procedural per-category graphic (`isGenerated`, no url) — a radial gradient background
//      plus category-specific shapes drawn in a `Canvas`, an "IMAGEN ACTIVE" badge, and a
//      centered category title.
//
//  CONVENTIONS §10 (determinism / faithful output): the per-category color map, every shape's
//  offset/radius/strokeWidth, and every alpha are carried VERBATIM. The Canvas math uses the
//  same `w`/`h` and `Offset(w*…, h*…)` fractions as the Compose `Canvas` draw scope. The
//  radial background uses `radius = w` (in points) centered at `(w/2, h/2)` exactly.
//

import SwiftUI

/// 3-state procedural / generated bookmark cover. See file header for the state machine.
///
/// `onGenerateClick` is invoked only in the CTA state (state 2). `imageUrl` supplies the real
/// Grok cover for state 1. The caller sizes this via a `.frame(height:)` like the Android
/// `Modifier.height(...)`.
struct ImagenBookmarkArt: View {
    let category: String?
    let isGenerated: Bool
    let onGenerateClick: () -> Void
    var imageUrl: String? = nil

    @Environment(\.curioColors) private var colors

    var body: some View {
        ZStack {
            // Base: faint surfaceVariant fill + hairline border + clip.
            content
        }
        .frame(maxWidth: .infinity)
        .background(colors.surfaceVariant.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(colors.onSurface.opacity(0.08), lineWidth: 1)
        }
        .accessibilityIdentifier("imagen_art_box")
    }

    @ViewBuilder
    private var content: some View {
        if isGenerated, let imageUrl, !imageUrl.isBlank {
            generatedImage(url: imageUrl)
        } else if !isGenerated {
            generateCTA
        } else {
            proceduralArt
        }
    }

    // MARK: - State 1: real Grok image

    @ViewBuilder
    private func generatedImage(url: String) -> some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    colors.surfaceVariant.opacity(0.15)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .accessibilityIdentifier("imagen_generated_image")
            .accessibilityLabel("Grok-generated cover for \(category ?? "bookmark")")

            Text("GROK IMAGINE")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(argb: 0xFF111111).opacity(0.7),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(10)
        }
    }

    // MARK: - State 2: generate CTA

    private var generateCTA: some View {
        Button(action: onGenerateClick) {
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(colors.primary)
                Text("GENERATE IMAGEN VISUAL REPRESENTATION")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(colors.primary)
                    .multilineTextAlignment(.center)
                Text("Distinguish categories or content types elegantly")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(colors.onSurface.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .padding(16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - State 3: procedural per-category art

    private var proceduralArt: some View {
        // `category?.trim()?.lowercase() ?: "tech"` — note "tech" hits the `else` shape branch.
        let cleanCategory = (category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? "tech"
        let grad = Self.gradColors(for: cleanCategory)

        return ZStack(alignment: .topTrailing) {
            Canvas { ctx, size in
                Self.draw(category: cleanCategory, grad: grad, ctx: &ctx, size: size)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // "IMAGEN ACTIVE" badge, top-end.
            Text("IMAGEN ACTIVE")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white)
                .accessibilityIdentifier("imagen_active_badge")
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(grad[0].opacity(0.85),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(10)

            // Centered category title.
            VStack(spacing: 0) {
                Text((category ?? "CURATED CONTENT").uppercased())
                    .font(.system(size: 18, weight: .black))
                    .tracking(2.0)
                    .foregroundStyle(.white)
                Text("REPRESENTATIVE GENERATIVE GRAPHIC")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    // MARK: - Category color map (verbatim)

    /// Custom category colors. Mirrors the Compose `when (cleanCategory)` map exactly; the
    /// fallback (`else`) is the blue-grey / grey pair used by "tech" and all unknown values.
    static func gradColors(for cleanCategory: String) -> [Color] {
        switch cleanCategory {
        case "development":
            return [Color(argb: 0xFF2196F3), Color(argb: 0xFF00BCD4)]
        case "design":
            return [Color(argb: 0xFF9C27B0), Color(argb: 0xFFE91E63)]
        case "crypto", "blockchain":
            return [Color(argb: 0xFFFF9800), Color(argb: 0xFFFFC107)]
        case "business", "marketing":
            return [Color(argb: 0xFF4CAF50), Color(argb: 0xFF009688)]
        case "life", "personal":
            return [Color(argb: 0xFFE91E63), Color(argb: 0xFFFF5722)]
        default:
            return [Color(argb: 0xFF607D8B), Color(argb: 0xFF9E9E9E)]
        }
    }

    // MARK: - Canvas drawing (verbatim offsets/radii/alphas)

    /// Draws the radial background gradient then the category-themed shapes. Every numeric
    /// constant (radius in px, offset fraction, stroke width, alpha) matches the Compose
    /// `DrawScope` calls one-for-one.
    static func draw(category cleanCategory: String, grad: [Color], ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height

        // Radial background gradient: center→edge, radius = w.
        let bgRect = Path(CGRect(origin: .zero, size: size))
        ctx.fill(
            bgRect,
            with: .radialGradient(
                Gradient(colors: [grad[0].opacity(0.45), grad[1].opacity(0.1)]),
                center: CGPoint(x: w / 2, y: h / 2),
                startRadius: 0,
                endRadius: w
            )
        )

        switch cleanCategory {
        case "development":
            let linesCount = 8
            for i in 0...linesCount {
                let x = (w / CGFloat(linesCount)) * CGFloat(i)
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: h))
                ctx.stroke(path, with: .color(grad[0].opacity(0.15)), lineWidth: 1)
            }
            fillCircle(&ctx, color: grad[1].opacity(0.35), radius: 35, center: CGPoint(x: w * 0.4, y: h * 0.5))
            fillCircle(&ctx, color: grad[0].opacity(0.25), radius: 20, center: CGPoint(x: w * 0.6, y: h * 0.35))

        case "design":
            fillCircle(&ctx, color: grad[0].opacity(0.35), radius: 45, center: CGPoint(x: w * 0.35, y: h * 0.6))
            fillCircle(&ctx, color: grad[1].opacity(0.35), radius: 35, center: CGPoint(x: w * 0.6, y: h * 0.45))

        case "crypto", "blockchain":
            fillCircle(&ctx, color: grad[0].opacity(0.1), radius: 55, center: CGPoint(x: w / 2, y: h / 2))
            fillCircle(&ctx, color: grad[1].opacity(0.2), radius: 35, center: CGPoint(x: w / 2, y: h / 2))
            fillCircle(&ctx, color: grad[0].opacity(0.4), radius: 18, center: CGPoint(x: w / 2, y: h / 2))

        case "business", "marketing":
            strokeLine(&ctx, color: grad[0].opacity(0.4), width: 6,
                       from: CGPoint(x: w * 0.2, y: h * 0.8), to: CGPoint(x: w * 0.4, y: h * 0.6))
            strokeLine(&ctx, color: grad[0].opacity(0.4), width: 6,
                       from: CGPoint(x: w * 0.4, y: h * 0.6), to: CGPoint(x: w * 0.6, y: h * 0.65))
            strokeLine(&ctx, color: grad[1].opacity(0.5), width: 8,
                       from: CGPoint(x: w * 0.6, y: h * 0.65), to: CGPoint(x: w * 0.8, y: h * 0.3))

        default:
            fillCircle(&ctx, color: grad[0].opacity(0.15), radius: 50, center: CGPoint(x: w / 2, y: h / 2))
            fillCircle(&ctx, color: grad[1].opacity(0.35), radius: 15, center: CGPoint(x: w * 0.35, y: h * 0.4))
            fillCircle(&ctx, color: grad[0].opacity(0.35), radius: 15, center: CGPoint(x: w * 0.65, y: h * 0.6))
        }
    }

    /// Fills a circle of `radius` (points) centered at `center` — Compose `drawCircle`.
    private static func fillCircle(_ ctx: inout GraphicsContext, color: Color, radius: CGFloat, center: CGPoint) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.fill(Path(ellipseIn: rect), with: .color(color))
    }

    /// Strokes a line — Compose `drawLine` (butt cap, like Compose's default `StrokeCap.Butt`).
    private static func strokeLine(_ ctx: inout GraphicsContext, color: Color, width: CGFloat, from: CGPoint, to: CGPoint) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .butt))
    }
}
