//
//  ReaderViewScreen.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/ReaderViewScreen.kt (ReaderViewScreen).
//
//  DESIGN §10 (Screens): Full-screen reader (font scale, metadata, source/deep/summary/tags/OCR
//  blocks, 600pt cap). `struct ReaderView`; `.fullScreenCover`; slide-up transition; `@State
//  fontScale` (0.85/1.0/1.25); serif body; source-type colors; date `MMM dd, yyyy - HH:mm`; openURL.
//
//  CONVENTIONS mapping:
//  - §8 "Theme": the Android `BookmarkTheme(darkTheme, dynamicColor)` wrapper is replaced by
//    `.curioTheme(darkTheme:)` (Material You / `dynamicColor` is DROPPED — the static Cosmic palette
//    is canonical), so the reader forces its own theme so the cover matches the app's resolved scheme
//    even though `.fullScreenCover` presents in a fresh environment. The source-type accent colors
//    (`Color(0xFFB71C1C)` arXiv etc.) are unpacked at this UI boundary.
//  - §8 "Layout/insets": the Android `Dialog(usePlatformDefaultWidth = false)` full-bleed reader maps
//    to `.fullScreenCover` (hosted by `BookmarkApp`). This file is the cover CONTENT; the slide-up
//    + fade entrance transition mirrors the Compose `AnimatedVisibility(slideInVertically + fadeIn)`.
//    `safeDrawingPadding()` → `.safeAreaPadding()` semantics via the cover's safe area.
//  - §4 "Sealed strings": exact user-facing strings preserved verbatim — "READER VIEW",
//    "Uncategorized", "Untitled Curio", "No Summary available. Execute AI analysis to generate a
//    cognitive outline.", "ABSTRACT", "DEEP ANALYSIS", "TAGS", "RAW TEXT TRANSCRIPTION",
//    "Mentioned in {n} bookmarks".
//  - UI INVARIANT (CONVENTIONS / Bookmark.swift): the Android reader DOES surface `category` in the
//    metadata chip (it predates the "category never in UI" rule for the feed). This faithful port
//    keeps that one display verbatim — `(bookmark.category ?? "Uncategorized").uppercased()` —
//    matching the Kotlin source byte-for-byte (the no-category-in-UI rule governs the FEED/cards).
//  - §8 "Motion" / Accessibility: the back/zoom controls are 48pt targets with `.accessibilityLabel`
//    + `.accessibilityIdentifier` carried over from the Compose `semantics { }` / `testTag(...)`.
//

import SwiftUI

/// Full-screen, distraction-free reader for a single bookmark. Direct port of `@Composable
/// ReaderViewScreen`. Presented by `BookmarkApp` via `.fullScreenCover(item:)`; `onClose` tears the
/// cover down. `darkTheme` forces the reader's own theme wrapper so the cover matches the resolved
/// app scheme.
struct ReaderView: View {
    let bookmark: Bookmark
    let tier: GlassTier
    let darkTheme: Bool
    let onClose: () -> Void

    private static let fontScaleKey = "reader_font_scale"

    /// `1.0 = Medium, 0.85 = Small, 1.25 = Large` — persisted like Android `curio_reader` prefs.
    @State private var fontScale: CGFloat = {
        let stored = UserDefaults.standard.float(forKey: fontScaleKey)
        return stored > 0 ? CGFloat(stored) : 1.0
    }()
    /// Drives the slide-up + fade entrance (Compose `AnimatedVisibility` `visible` flag).
    @State private var visible: Bool = false

    @Environment(\.openURL) private var openURL

    /// `SimpleDateFormat("MMM dd, yyyy - HH:mm", Locale.getDefault()).format(Date(createdAt))`.
    /// `createdAt` is epoch milliseconds (CONVENTIONS §6); the formatter uses the current locale and
    /// device time zone, matching `Locale.getDefault()` + the default `SimpleDateFormat` zone.
    private var formattedTime: String {
        let date = Date(timeIntervalSince1970: Double(bookmark.createdAt) / 1000.0)
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM dd, yyyy - HH:mm"
        return formatter.string(from: date)
    }

    var body: some View {
        ReaderColors { colors in
            ZStack {
                colors.background
                    .ignoresSafeArea()

                if visible {
                    content(colors: colors)
                        .transition(
                            .move(edge: .bottom).combined(with: .opacity)
                        )
                }
            }
            .background(colors.background)
        }
        // Force the reader's own resolved scheme so the cover (presented in a fresh environment)
        // matches the app (Compose `BookmarkTheme(darkTheme, dynamicColor)`).
        .curioTheme(darkTheme: darkTheme)
        .onAppear {
            // `LaunchedEffect(Unit) { visible = true }` — slide the reader up on first composition.
            withAnimation(.easeOut(duration: 0.36)) { visible = true }
        }
        .onChange(of: fontScale) { _, scale in
            UserDefaults.standard.set(Float(scale), forKey: Self.fontScaleKey)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(colors: CurioColorScheme) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerBar(colors: colors)

                // Main distraction-free scroll column constrained for tablet reading comfort.
                VStack(alignment: .leading, spacing: 16) {
                    metadataRow(colors: colors)
                    titleBlock(colors: colors)
                    urlBlock(colors: colors)

                    Spacer().frame(height: 8)

                    sourceBlock(colors: colors)
                    deepAnalysisBlock(colors: colors)
                    summaryBlock(colors: colors)
                    tagsBlock(colors: colors)
                    ocrBlock(colors: colors)

                    Spacer().frame(height: 80)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: - Header bar (back + READER VIEW + font sizing)

    @ViewBuilder
    private func headerBar(colors: CurioColorScheme) -> some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18))
                    .foregroundStyle(colors.onSurface)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Go back to bookmarks")
            }
            .buttonStyle(.curioPressBounce)
            .accessibilityIdentifier("reader_back_button")

            Spacer()

            Text("READER VIEW")
                .font(.system(size: 14, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(colors.primary)

            Spacer()

            // Font-sizing adjusters (A- / A / A+), each a 48pt button.
            HStack(spacing: 4) {
                fontButton(
                    label: "A-",
                    size: 14, weight: .bold,
                    accessibility: "Decrease font size",
                    identifier: "reader_zoom_out",
                    colors: colors,
                    selected: abs(fontScale - 0.85) < 0.01
                ) { fontScale = 0.85 }

                fontButton(
                    label: "A",
                    size: 16, weight: .medium,
                    accessibility: "Reset font size",
                    identifier: "reader_zoom_reset",
                    colors: colors,
                    selected: abs(fontScale - 1.0) < 0.01
                ) { fontScale = 1.0 }

                fontButton(
                    label: "A+",
                    size: 22, weight: .heavy,
                    accessibility: "Increase font size",
                    identifier: "reader_zoom_in",
                    colors: colors,
                    selected: abs(fontScale - 1.25) < 0.01
                ) { fontScale = 1.25 }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func fontButton(
        label: String, size: CGFloat, weight: Font.Weight,
        accessibility: String, identifier: String,
        colors: CurioColorScheme,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(selected ? colors.primary : colors.onSurface)
                .padding(8)
                .frame(minWidth: 48, minHeight: 48)
                .background(
                    selected ? colors.primary.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .contentShape(Rectangle())
                .accessibilityLabel(accessibility)
        }
        .buttonStyle(.curioPressBounce)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Metadata row (category chip · date)

    @ViewBuilder
    private func metadataRow(colors: CurioColorScheme) -> some View {
        HStack(spacing: 8) {
            // Faithful to the Android reader: the AI category IS shown here in the reader metadata
            // chip (the "no category in UI" rule governs the feed cards).
            Text((bookmark.category ?? "Uncategorized").uppercased())
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(colors.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(colors.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text("•")
                .font(.system(size: 14))
                .foregroundStyle(colors.onSurface.opacity(0.4))

            Text(formattedTime)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(colors.onSurface.opacity(0.5))
        }
    }

    // MARK: - Title

    @ViewBuilder
    private func titleBlock(colors: CurioColorScheme) -> some View {
        // `bookmark.title?.ifBlank { "Untitled Curio" } ?: "Untitled Curio"`.
        let title: String = {
            if let t = bookmark.title, !t.isBlank { return t }
            return "Untitled Curio"
        }()
        Text(title)
            .font(.system(size: 32, weight: .black))
            .lineSpacing(38 - 32)
            .foregroundStyle(colors.onSurface)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("reader_title")
    }

    // MARK: - URL / domain link

    @ViewBuilder
    private func urlBlock(colors: CurioColorScheme) -> some View {
        // `bookmark.url?.ifBlank { null }?.let { … }`.
        if let raw = bookmark.url, !raw.isBlank {
            Text(raw)
                .font(.system(size: 12, weight: .regular))
                .underline()
                .foregroundStyle(colors.secondary)
                .onTapGesture {
                    // try { startActivity(ACTION_VIEW, url) } catch { /* ignored */ }
                    if let url = URL(string: raw) {
                        openURL(url)
                    }
                }
        }
    }

    // MARK: - Source paper / repo metadata (Phase 8)

    @ViewBuilder
    private func sourceBlock(colors: CurioColorScheme) -> some View {
        if let sourceType = bookmark.sourceType {
            // Source-type accent — unpacked at the UI boundary.
            let srcColor: Color = {
                switch sourceType {
                case .ARXIV: return Color(argb: 0xFFB71C1C)
                case .GITHUB: return Color(argb: 0xFF1B5E20)
                case .HUGGING_FACE: return Color(argb: 0xFFF57F17)
                default: return colors.secondary
                }
            }()

            VStack(alignment: .leading, spacing: 8) {
                if let sourceTitle = bookmark.sourceTitle, !sourceTitle.isBlank {
                    Text(sourceTitle)
                        .font(.system(size: 18 * fontScale, weight: .bold))
                        .lineSpacing(28 - 18)
                        .foregroundStyle(srcColor)
                }
                if let sourceAuthors = bookmark.sourceAuthors, !sourceAuthors.isBlank {
                    Text(sourceAuthors)
                        .font(.system(size: 12, weight: .regular))
                        .italic()
                        .foregroundStyle(colors.onSurface.opacity(0.65))
                }
                if bookmark.referenceCount > 1 {
                    Text("Mentioned in \(bookmark.referenceCount) bookmarks")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(srcColor.opacity(0.7))
                }
                if let sourceAbstract = bookmark.sourceAbstract, !sourceAbstract.isBlank {
                    Divider().overlay(srcColor.opacity(0.15))
                    Text("ABSTRACT")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.0)
                        .foregroundStyle(srcColor)
                    Text(sourceAbstract)
                        .font(.system(size: 14 * fontScale, weight: .regular, design: .serif))
                        .lineSpacing((22 - 14) * fontScale)
                        .foregroundStyle(colors.onSurface.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer().frame(height: 8)
        }
    }

    // MARK: - Deep analysis (Phase 9)

    @ViewBuilder
    private func deepAnalysisBlock(colors: CurioColorScheme) -> some View {
        if bookmark.isDeepAnalyzed, let deep = bookmark.deepSummary, !deep.isBlank {
            Divider().overlay(colors.tertiary.opacity(0.2))
            Spacer().frame(height: 8)
            Text("DEEP ANALYSIS")
                .font(.system(size: 11, weight: .black))
                .tracking(1.0)
                .foregroundStyle(colors.tertiary)
            Text(deep)
                .font(.system(size: 14 * fontScale, weight: .regular))
                .lineSpacing((22 - 14) * fontScale)
                .foregroundStyle(colors.onSurface.opacity(0.85))
            Spacer().frame(height: 8)
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private func summaryBlock(colors: CurioColorScheme) -> some View {
        // `bookmark.summary ?: "No Summary available. …"`.
        let summary = bookmark.summary ?? "No Summary available. Execute AI analysis to generate a cognitive outline."
        Text(summary)
            .font(.system(size: 16 * fontScale, weight: .regular, design: .serif))
            .lineSpacing((26 - 16) * fontScale)
            .foregroundStyle(colors.onSurface.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("reader_summary_content")
    }

    // MARK: - Tags

    @ViewBuilder
    private func tagsBlock(colors: CurioColorScheme) -> some View {
        if !bookmark.tags.isEmpty {
            Spacer().frame(height: 16)
            Text("TAGS")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(colors.onSurface.opacity(0.4))
            FlowLayout(spacing: 8) {
                ForEach(bookmark.tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(colors.onSurface.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(colors.onSurface.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - OCR raw text (distraction-free)

    @ViewBuilder
    private func ocrBlock(colors: CurioColorScheme) -> some View {
        if let ocr = bookmark.ocrText, !ocr.isBlank {
            Spacer().frame(height: 24)
            Divider().overlay(colors.onSurface.opacity(0.1))
            Spacer().frame(height: 16)

            Text("RAW TEXT TRANSCRIPTION")
                .font(.system(size: 11, weight: .black))
                .tracking(1.0)
                .foregroundStyle(colors.primary)

            Text(ocr)
                .font(.system(size: 14 * fontScale, weight: .regular))
                .lineSpacing((22 - 14) * fontScale)
                .foregroundStyle(colors.onSurface.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("reader_raw_text")
        }
    }
}

// MARK: - ReaderColors

/// Reads the active `CurioColorScheme` (resolved by the reader's own `.curioTheme(darkTheme:)`
/// wrapper) and hands it to a builder — used so the body can pass `colors` into the block helpers
/// without each one independently reading the environment. Equivalent to inlining
/// `@Environment(\.curioColors)`.
private struct ReaderColors<Content: View>: View {
    @Environment(\.curioColors) private var colors
    @ViewBuilder let content: (CurioColorScheme) -> Content
    var body: some View { content(colors) }
}

// Note: the wrapping tag layout reuses the shared `FlowLayout` (Compose `FlowRow` analogue)
// declared in `Components/CurioPostCard.swift`.
