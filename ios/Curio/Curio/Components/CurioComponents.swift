//
//  CurioComponents.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/CurioComponents.kt
//         (CategoryPill, TagChip, CurioActionChip, DetailPanel, MarkdownDetailPanel, StatTile,
//          CurioFallbackCover, FeedIconAction, QuickFilterPill, TypingDots).
//
//  Reusable feed/detail widgets: chips, pills, panels, tiles, the no-image fallback cover,
//  the spinning circular feed-icon action, the quick-filter pill with count badge, and the
//  3-dot typing indicator.
//
//  CONVENTIONS §8/§9 (Components):
//   - uniform press feedback via the shared `.curioPressBounce` ButtonStyle (replaces ripple);
//   - non-hit-testing `.bounceScale(active:)` for selection/active states;
//   - centralized source-type → color/glyph (here via `sourceGlyph(_:)`, mirroring the Android
//     `when (sourceType)` blocks that recur across the card + cover);
//   - per-mode alphas/hex carried verbatim from the Compose modifiers;
//   - heavy typography (`.black`/`.heavy`) + explicit `.textCase(.uppercase)` + tracking;
//   - `category` (the AI taxonomy bucket) is shown ONLY on the fallback cover as a `#hashtag`,
//     exactly as Android did — it never surfaces as a first-class label elsewhere.
//
//  Format/lookup helpers consumed here (`CurioFormat.getCategoryColor`, `.sourceDisplayName`)
//  live in the Screens module per DESIGN §10; this widget layer treats them as the documented
//  static API surface (DESIGN "Notes for implementers").
//

import SwiftUI

// MARK: - CategoryPill

/// A pill showing the AI category with its deterministic color. Used in the bulk-category
/// dialog preview row; the color comes from the stable Java-hashCode palette (CONVENTIONS §10).
struct CategoryPill: View {
    let category: String

    var body: some View {
        let color = CurioFormat.getCategoryColor(category)
        Text(category.uppercased())
            .font(.system(size: 10, weight: .black))
            .tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.16), in: Capsule())
            .overlay { Capsule().stroke(color.opacity(0.45), lineWidth: 1) }
    }
}

// MARK: - TagChip

/// A tappable `#tag` chip with press bounce. Tapping selects the tag as a search filter.
struct TagChip: View {
    let tag: String
    let onTap: () -> Void

    @Environment(\.curioColors) private var colors

    var body: some View {
        Button(action: onTap) {
            Text("#\(tag)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(colors.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(colors.primary.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.curioPressBounce)
    }
}

// MARK: - CurioActionChip

/// A labelled, icon-led action chip; `filled` flips it to a solid accent button.
struct CurioActionChip: View {
    let label: String
    let systemImage: String
    let color: Color
    var filled: Bool = false
    let onTap: () -> Void

    @Environment(\.curioColors) private var colors

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 14, height: 14)
                    .foregroundStyle(filled ? colors.onPrimary : color)
                Text(label)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(filled ? colors.onPrimary : color)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(filled ? color : color.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.curioPressBounce)
    }
}

// MARK: - DetailPanel

/// A tinted, bordered labelled text block used in the expanded card / reader for OCR,
/// summary, abstract, and note sections.
struct DetailPanel: View {
    let label: String
    let bodyText: String
    let accent: Color
    var bold: Bool = false

    init(label: String, body: String, accent: Color, bold: Bool = false) {
        self.label = label
        self.bodyText = body
        self.accent = accent
        self.bold = bold
    }

    @Environment(\.curioColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .black))
                .tracking(0.8)
                .foregroundStyle(accent)
            Text(self.bodyText)
                .font(.system(size: 12, weight: bold ? .bold : .regular))
                .lineSpacing(19 - 12)
                .foregroundStyle(colors.onSurface.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(accent.opacity(0.20), lineWidth: 1) }
    }
}

// MARK: - MarkdownDetailPanel

/// Detail panel whose body is rendered as markdown (headings, bullets, **bold**). Used for
/// the deep-analysis section; an optional leading icon precedes the label.
struct MarkdownDetailPanel: View {
    let label: String
    let bodyText: String
    let accent: Color
    var systemImage: String? = nil

    init(label: String, body: String, accent: Color, systemImage: String? = nil) {
        self.label = label
        self.bodyText = body
        self.accent = accent
        self.systemImage = systemImage
    }

    @Environment(\.curioColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 13, height: 13)
                        .foregroundStyle(accent)
                }
                Text(label)
                    .font(.system(size: 11, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(accent)
            }
            MarkdownText(
                markdown: self.bodyText,
                style: CurioFont.bodySmallLineHeight19,
                color: colors.onSurface.opacity(0.92),
                accent: accent
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(accent.opacity(0.20), lineWidth: 1) }
    }
}

// MARK: - StatTile

/// A glass stat card: a tinted icon chip over a big value over an ALL-CAPS label.
/// Used in the feed header strip and insights dashboard.
struct StatTile: View {
    let label: String
    let value: String
    let systemImage: String
    let color: Color
    let tier: GlassTier
    var onClick: (() -> Void)? = nil

    @Environment(\.curioColors) private var colors

    var body: some View {
        Group {
            if let onClick {
                Button(action: onClick) { tileContent }
                    .buttonStyle(.curioPressBounce)
            } else {
                tileContent
            }
        }
    }

    private var tileContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(value)
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(colors.onSurface)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(colors.onSurface.opacity(0.55))
        }
        .padding(14)
        .glassSurface(tier: tier, shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Elegant gradient cover shown when a bookmark has no real or generated image. Keeps the feed
/// visually consistent — every card has a media anchor instead of collapsing into a bare text
/// block. Carries an oversized translucent source glyph watermark + source label + (optional)
/// category hashtag.
struct CurioFallbackCover: View {
    let bookmark: Bookmark
    let srcColor: Color
    let accent: Color
    let isExpanded: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [srcColor.opacity(0.9), accent.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Oversized translucent watermark glyph, center-end.
            HStack {
                Spacer()
                Image(systemName: sourceGlyph(bookmark.sourceType))
                    .font(.system(size: isExpanded ? 92 : 64, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.22))
                    .padding(.trailing, 6)
            }

            // Source name + category hashtag, bottom-start.
            VStack(alignment: .leading, spacing: 2) {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(CurioFormat.sourceDisplayName(bookmark).uppercased())
                            .font(.system(size: 12, weight: .black))
                            .tracking(1.0)
                            .foregroundStyle(.white)
                        if let category = bookmark.category, !category.isBlank {
                            Text("#\(category.lowercased().replacingOccurrences(of: " ", with: "_"))")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.85))
                        }
                    }
                    Spacer()
                }
                .padding(14)
            }
        }
        .frame(height: isExpanded ? 104 : 70)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1) }
    }
}

// MARK: - FeedIconAction

/// Compact circular glass icon button used in the feed control strip. `active` tints it
/// primary; `spinning` rotates the glyph continuously (sync in progress).
struct FeedIconAction: View {
    let systemImage: String
    let accessibilityLabel: String
    var active: Bool = false
    var spinning: Bool = false
    let onTap: () -> Void

    @Environment(\.curioColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0

    private var tint: Color {
        active ? colors.primary : colors.onSurface.opacity(0.7)
    }

    var body: some View {
        Button(action: onTap) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .rotationEffect(.degrees(spinning ? angle : 0))
                .frame(width: 38, height: 38)
                .background(
                    (active ? colors.primary.opacity(0.16) : colors.onSurface.opacity(0.06)),
                    in: Circle()
                )
        }
        .buttonStyle(.curioPressBounce(pressedScale: 0.85))
        .accessibilityLabel(accessibilityLabel)
        .onChange(of: spinning) { _, isSpinning in
            if isSpinning && !reduceMotion {
                angle = 0
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            } else {
                withAnimation(.linear(duration: 0)) { angle = 0 }
            }
        }
        .onAppear {
            if spinning && !reduceMotion {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
        }
    }
}

// MARK: - QuickFilterPill

/// Quick-filter pill (All / Favorites / Read later) with an optional count badge. Active
/// state tints + outlines the pill and bounces it via the non-hit-testing `.bounceScale`.
struct QuickFilterPill: View {
    let label: String
    let systemImage: String
    let count: Int?
    let active: Bool
    let color: Color
    let onTap: () -> Void

    @Environment(\.curioColors) private var colors

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(active ? color : colors.onSurface.opacity(0.6))
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(active ? color : colors.onSurface.opacity(0.75))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(active ? Color.white : colors.onSurface.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(active ? color : colors.onSurface.opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                (active ? color.opacity(0.18) : colors.onSurface.opacity(0.05)),
                in: Capsule()
            )
            .overlay { Capsule().stroke(active ? color.opacity(0.55) : Color.clear, lineWidth: 1) }
        }
        .buttonStyle(.curioPressBounce(pressedScale: 0.93))
        .bounceScale(active: active)
    }
}

// MARK: - TypingDots

/// Three staggered, pulsing dots — the chat "assistant is typing" indicator. Each dot scales
/// 0.5→1.0 on a 600ms reversing cycle, staggered by 150ms, with alpha tracking the scale.
struct TypingDots: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Dot(color: color, index: i, animate: animate, reduceMotion: reduceMotion)
            }
        }
        .onAppear { animate = true }
    }

    private struct Dot: View {
        let color: Color
        let index: Int
        let animate: Bool
        let reduceMotion: Bool

        var body: some View {
            // Static endpoint scale when Reduce Motion is on (no infinite animation).
            let scale: CGFloat = reduceMotion ? 0.75 : (animate ? 1.0 : 0.5)
            Circle()
                .fill(color.opacity(0.4 + Double(scale) * 0.5))
                .frame(width: 7, height: 7)
                .scaleEffect(scale)
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                    value: animate
                )
        }
    }
}

// MARK: - Source glyph centralizer
//
// Centralizes the source-type → SF Symbol mapping that recurs across the card avatar/cover
// (CONVENTIONS §8: centralize source-type→glyph to avoid drift). Substitutions vs the Android
// Material icons:
//   GITHUB        : Icons.Filled.Hub                 → "point.3.connected.trianglepath.dotted"
//   ARXIV         : Icons.AutoMirrored.Filled.MenuBook → "book"
//   HUGGING_FACE  : Icons.Filled.AutoAwesome         → "sparkles"
//   else / nil    : Icons.Filled.Bookmarks           → "bookmark.fill"

/// Maps a `SourceType` (or nil) to the SF Symbol glyph used for its avatar/cover watermark.
func sourceGlyph(_ sourceType: SourceType?) -> String {
    switch sourceType {
    case .GITHUB: return "point.3.connected.trianglepath.dotted"
    case .ARXIV: return "book"
    case .HUGGING_FACE: return "sparkles"
    default: return "bookmark.fill"
    }
}

// MARK: - bodySmall (lineHeight 19) helper role

extension CurioFont {
    /// `MaterialTheme.typography.bodySmall.copy(lineHeight = 19.sp)` — the markdown panel body
    /// role (bodySmall is 12pt; line height bumped to 19 to match the Compose copy).
    static let bodySmallLineHeight19 = CurioTextStyle(size: 12, weight: .regular, tracking: 0.4, lineHeight: 19)
}

// MARK: - String.isBlank parity (Kotlin)

extension String {
    /// Kotlin `String.isBlank()`: empty or whitespace-only. (Mirrors `isNullOrBlank` checks
    /// once the optional has been unwrapped at the call site.)
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
