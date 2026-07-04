//
//  CurioPostCard.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/CurioPostCard.kt
//         (CurioPostCard, CurioCardActions, CardOptionsSheet, SheetToggleRow, SheetActionTile,
//          SheetDivider, CardAction).
//
//  The flagship feed card: header (selection ring · avatar · name/handle · time · chevron),
//  bold title, snippet, media (real image / generated art / fallback cover), tag preview,
//  footer meta (View-on-X · space/suggest-space · source · summary mark · favorite ·
//  save-for-later · ⋯), and an expandable detail section (link row, OCR, summary, deep
//  analysis, abstract, note, full tag flow, and a "CURATE, SHARE & MORE" opener). Holding the
//  card (or tapping ⋯) opens `CardOptionsSheet` — a 2-column action grid with a two-step
//  delete confirm.
//
//  CONVENTIONS §9:
//   - press feedback via a card-level scale spring (`CurioMotion.snappy`) on press;
//   - selection ring + favorite/save glyphs use the non-hit-testing `.bounceScale(active:)`;
//   - the AI `category` NEVER surfaces as a label — it only (a) tints the accent when unfiled,
//     (b) seeds the handle fallback (`@category`), and (c) drives the "suggest space" pill via
//     `CategorySpaces.forCategory`;
//   - child dialogs (notes / assign-space / new-space) close when the card collapses;
//   - the options sheet animates closed THEN runs the chosen action (`act { … }`);
//   - delete is two-step (arm an inline confirm before destroying);
//   - OCR image picked via `PhotosPicker` (→ `UIImage`), replacing the Android `GetContent()`.
//
//  Format/lookup helpers (`CurioFormat.*`, `spaceIcon`) and the `AssignToSpaceDialog` /
//  `SpaceEditorDialog` child dialogs live in the Screens module per DESIGN §10; this card
//  treats them as the documented API surface.
//

import SwiftUI
import PhotosUI

// MARK: - CurioCardActions

/// Per-card action callbacks, bound to the bookmark at the call site. Hoisting these (instead
/// of passing the whole `BookmarkViewModel`) decouples the leaf card from the ViewModel.
///
/// Direct port of the Android `CurioCardActions` data class. `onProcessOcr` takes a `UIImage`
/// (the iOS analogue of `android.graphics.Bitmap`); `onCreateSpaceAndAssign`'s `color` is an
/// `Int64` packed ARGB (Kotlin `Long`); `exportBibtex` returns an optional BibTeX string.
struct CurioCardActions {
    let onProcessOcr: (UIImage) -> Void
    let onGenerateImagen: () -> Void
    let onSelectTag: (String) -> Void
    let onSelectSpace: (String) -> Void
    let onAcceptCategory: () -> Void
    let onToggleFavorite: () -> Void
    let onToggleSavedForLater: () -> Void
    let onUpdateNotes: (String?) -> Void
    let onAssignToSpace: (String?) -> Void
    let onCreateSpaceAndAssign: (_ name: String, _ color: Int64, _ icon: String, _ description: String, _ rules: SpaceRules, _ isPinned: Bool) -> Void
    let onRunAiAnalysis: () -> Void
    let onRunDeepAnalysis: () -> Void
    let onResolveSource: () -> Void
    let exportBibtex: () -> String?
    let onDelete: () -> Void
    // ChronosFlow productivity handoff (only invoked when ChronosFlow is installed).
    var onRemindInChronosFlow: (ChronosReminderChoice) -> Void = { _ in }
    var onCaptureToChronosFlow: () -> Void = {}
    var onCreateChronosFlowTask: () -> Void = {}
}

// MARK: - CurioPostCard

/// The flagship feed card. See file header for anatomy.
struct CurioPostCard: View {
    let bookmark: Bookmark
    let actions: CurioCardActions
    let spaces: [Space]
    let isProcessing: Bool
    var isAnalysisError: Bool = false
    var analysisErrorMessage: String? = nil
    let isImagenGenerated: Bool
    let imagenUrl: String?
    let tier: GlassTier
    let isSelected: Bool
    let onToggleSelect: () -> Void
    let inSelectionMode: Bool
    var isReorderMode: Bool = false
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}
    var onBookmarkClick: () -> Void = {}
    var chronosFlowInstalled: Bool = false
    /// Embedding-derived Space suggestion for unfiled cards (medium-confidence match).
    var suggestedSpace: Space? = nil

    @Environment(\.curioColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isExpanded = false
    @State private var showOptions = false
    @State private var showSpacePicker = false
    @State private var showNewSpaceForCard = false
    @State private var showNotesEditor = false
    @State private var isPressed = false
    @State private var ocrPickerItem: PhotosPickerItem? = nil
    @State private var showOcrPicker = false

    /// The Space a bookmark is filed in drives its accent + footer pill.
    private var currentSpace: Space? {
        spaces.first { $0.id == bookmark.spaceId }
    }

    private var accent: Color {
        if let currentSpace { return Color(packedARGB: currentSpace.color) }
        if let suggestedSpace { return Color(packedARGB: suggestedSpace.color) }
        if let category = bookmark.category, !category.isBlank {
            return CurioFormat.getCategoryColor(category)
        }
        return colors.primary
    }

    private var srcColor: Color {
        switch bookmark.sourceType {
        case .ARXIV: return Color(argb: 0xFFE53935)
        case .GITHUB: return Color(argb: 0xFF66BB6A)
        case .HUGGING_FACE: return Color(argb: 0xFFFFB300)
        default: return accent
        }
    }

    /// Shareable text — analyzed entries get a structured block, else raw text.
    private var shareableText: String {
        if bookmark.isAnalyzed {
            let title = bookmark.title ?? "Curio bookmark"
            let category = bookmark.category ?? "General"
            let tags = bookmark.tags.map { "#\($0)" }.joined(separator: ", ")
            let summary = bookmark.summary ?? ""
            return "📌 \(title)\nCategory: \(category)\nTags: \(tags)\n\n\(summary)\n\n\(bookmark.text)"
        }
        return bookmark.text
    }

    /// Permalink to the original X post (nil for manual/non-tweet entries).
    private var tweetLink: String? { CurioFormat.tweetUrl(bookmark) }

    var body: some View {
        ZStack(alignment: .leading) {
            // Category accent edge — a vivid left stripe.
            cardBody
        }
        .scaleEffect(isPressed ? 0.975 : 1.0)
        .animation(CurioMotion.resolved(CurioMotion.snappy, reduceMotion: reduceMotion), value: isPressed)
        .glassSurface(
            tier: tier,
            shape: RoundedRectangle(cornerRadius: 22, style: .continuous),
            tint: cardTint,
            borderColor: isSelected ? colors.primary : nil
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            if inSelectionMode { onToggleSelect() } else { withAnimation(CurioMotion.liquid) { isExpanded.toggle() } }
        }
        .onLongPressGesture(minimumDuration: 0.4, pressing: { pressing in
            isPressed = pressing
        }, perform: {
            if inSelectionMode { onToggleSelect() } else { showOptions = true }
        })
        .accessibilityIdentifier("bookmark_card_\(bookmark.id)")
        .onChange(of: isExpanded) { _, expanded in
            // Close any open child dialogs when the card collapses.
            if !expanded {
                showNotesEditor = false
                showSpacePicker = false
                showNewSpaceForCard = false
            }
        }
        .photosPicker(isPresented: $showOcrPicker, selection: $ocrPickerItem, matching: .images)
        .onChange(of: ocrPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    actions.onProcessOcr(image)
                }
                ocrPickerItem = nil
            }
        }
        .sheet(isPresented: $showOptions) {
            CardOptionsSheet(
                bookmark: bookmark,
                actions: actions,
                isProcessing: isProcessing,
                shareableText: shareableText,
                tweetLink: tweetLink,
                chronosFlowInstalled: chronosFlowInstalled,
                tier: tier,
                onOcr: { showOcrPicker = true },
                onSelect: onToggleSelect,
                onReader: onBookmarkClick,
                onMoveToSpace: { showSpacePicker = true },
                onNotes: { showNotesEditor = true }
            )
        }
        .sheet(isPresented: $showNotesEditor) {
            NotesEditorDialog(existingNote: bookmark.notes, tier: tier) { note in
                actions.onUpdateNotes(note)
                showNotesEditor = false
            }
        }
        .sheet(isPresented: $showSpacePicker) {
            AssignToSpaceDialog(
                spaces: spaces,
                currentSpaceId: bookmark.spaceId,
                tier: tier,
                onAssign: { spaceId in
                    actions.onAssignToSpace(spaceId)
                    showSpacePicker = false
                },
                onCreateSpace: {
                    showSpacePicker = false
                    showNewSpaceForCard = true
                }
            )
        }
        .sheet(isPresented: $showNewSpaceForCard) {
            SpaceEditorDialog(
                existing: nil,
                tier: tier,
                onConfirm: { name, color, icon, description, rules, isPinned in
                    actions.onCreateSpaceAndAssign(name, color, icon, description, rules, isPinned)
                    showNewSpaceForCard = false
                }
            )
        }
    }

    private var cardTint: Color? {
        if isSelected { return colors.primary.opacity(0.16) }
        if bookmark.isAnalyzed { return colors.primaryContainer.opacity(0.10) }
        return nil
    }

    // MARK: Card body

    private var cardBody: some View {
        ZStack(alignment: .leading) {
            // Left accent stripe (vertical gradient).
            LinearGradient(
                colors: [accent.opacity(0.9), accent.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 4)
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 11) {
                header
                if isAnalysisError, let analysisErrorMessage, !analysisErrorMessage.isEmpty {
                    analysisErrorStrip(message: analysisErrorMessage)
                }
                titleBlock
                snippetBlock
                mediaBlock
                tagPreviewBlock
                footer
                if isExpanded { expandedDetails }
            }
            .padding(.init(top: 14, leading: 16, bottom: 14, trailing: 14))
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 11) {
            // Selection ring (always present for accessibility/tests).
            Button(action: onToggleSelect) {
                ZStack {
                    Circle()
                        .stroke(
                            isSelected ? colors.primary : colors.onSurface.opacity(inSelectionMode ? 0.4 : 0.18),
                            lineWidth: 1.5
                        )
                        .background(Circle().fill(isSelected ? colors.primary : .clear))
                        .frame(width: 20, height: 20)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(colors.onPrimary)
                    }
                }
            }
            .buttonStyle(.plain)
            .bounceScale(active: isSelected)
            .accessibilityIdentifier("bookmark_select_checkbox_\(bookmark.id)")

            // Author avatar — gradient disc with initial or source glyph.
            avatar

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(CurioFormat.displayAuthor(bookmark))
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(colors.onSurface)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if bookmark.isAnalyzed {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(colors.primary)
                            .accessibilityLabel("AI curated")
                    } else if isProcessing {
                        HStack(spacing: 4) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.55)
                                .tint(colors.primary)
                            Text("Curating…")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(colors.primary)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(CurioFormat.relativeTime(bookmark.createdAt))
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(colors.onSurface.opacity(0.5))
                    if isReorderMode {
                        reorderButtons
                    } else {
                        Button {
                            withAnimation(CurioMotion.liquid) { isExpanded.toggle() }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(colors.primary)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .animation(CurioMotion.liquid, value: isExpanded)
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Expand")
                        .accessibilityIdentifier("expand_button_\(bookmark.id)")
                    }
                }
                Text(handleLine)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(colors.onSurface.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [srcColor.opacity(0.95), srcColor.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
            if let initial = CurioFormat.authorInitial(bookmark) {
                Text(String(initial))
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: sourceGlyph(bookmark.sourceType))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var reorderButtons: some View {
        Group {
            Button(action: onMoveUp) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colors.primary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Move up")
            .accessibilityIdentifier("move_up_button_\(bookmark.id)")

            Button(action: onMoveDown) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colors.primary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Move down")
            .accessibilityIdentifier("move_down_button_\(bookmark.id)")
        }
    }

    /// The handle/sub-line: `@handle` → `@category_fallback` → `saved · <date>`, then an
    /// optional `· <readingTime>` suffix.
    private var handleLine: String {
        var result = ""
        // Kotlin: authorUsername?.trim()?.takeIf { it.isNotEmpty() } — the TRIMMED value is used.
        let trimmedHandle = bookmark.authorUsername?.trimmingCharacters(in: .whitespaces)
        let handle = (trimmedHandle?.isEmpty == false) ? trimmedHandle : nil
        if let handle {
            result = "@\(handle)"
        } else if let category = bookmark.category, !category.isBlank {
            result = "@\(category.lowercased().replacingOccurrences(of: " ", with: "_"))"
        } else {
            result = "saved · \(CurioFormat.formatEpoch(bookmark.createdAt))"
        }
        if let reading = CurioFormat.readingTime(bookmark.text) {
            result += "  ·  \(reading)"
        }
        return result
    }

    // MARK: Title / snippet

    @ViewBuilder
    private var titleBlock: some View {
        if let title = bookmark.title, !title.isBlank {
            Text(title)
                .font(.system(size: 18, weight: .black))
                .lineSpacing(24 - 18)
                .foregroundStyle(colors.onSurface)
                .lineLimit(isExpanded ? 6 : 2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var snippetBlock: some View {
        let snippet = CurioFormat.cleanSnippet(bookmark.text)
        if !snippet.isBlank {
            Text(snippet)
                .font(.system(size: 14, weight: .medium))
                .lineSpacing(21 - 14)
                .foregroundStyle(colors.onSurface.opacity(0.82))
                .lineLimit(isExpanded ? nil : 3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Media

    @ViewBuilder
    private var mediaBlock: some View {
        if let imageUrl = bookmark.imageUrl, !imageUrl.isBlank {
            VStack(alignment: .leading, spacing: 6) {
                AsyncImage(url: URL(string: imageUrl)) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    case .failure:
                        CurioFallbackCover(bookmark: bookmark, srcColor: srcColor, accent: accent, isExpanded: isExpanded)
                    default:
                        PostImageLoadingPlaceholder(srcColor: srcColor, reduceMotion: reduceMotion)
                    }
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(colors.onSurface.opacity(0.08), lineWidth: 1) }
                .accessibilityIdentifier("post_image_\(bookmark.id)")
                .accessibilityLabel((bookmark.imageAltText?.nonEmptyOrNil) ?? "Post image")

                if isExpanded, let alt = bookmark.imageAltText, !alt.isBlank {
                    HStack(alignment: .top, spacing: 5) {
                        Text("ALT")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(colors.primary)
                            .padding(.top, 1)
                        Text(alt)
                            .font(.system(size: 11, weight: .heavy).italic())
                            .tracking(1.0)
                            .foregroundStyle(colors.onSurface.opacity(0.55))
                            .lineLimit(3)
                            .truncationMode(.tail)
                    }
                }
            }
        } else if isImagenGenerated {
            ImagenBookmarkArt(category: bookmark.category, isGenerated: true, onGenerateClick: {}, imageUrl: imagenUrl)
                .frame(height: isExpanded ? 140 : 88)
        } else if bookmark.isAnalyzed && isExpanded {
            ImagenBookmarkArt(category: bookmark.category, isGenerated: false, onGenerateClick: { actions.onGenerateImagen() })
                .frame(height: 130)
        } else {
            CurioFallbackCover(bookmark: bookmark, srcColor: srcColor, accent: accent, isExpanded: isExpanded)
        }
    }

    // MARK: Tag preview (collapsed only)

    @ViewBuilder
    private var tagPreviewBlock: some View {
        if bookmark.isAnalyzed && !bookmark.tags.isEmpty && !isExpanded {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Array(bookmark.tags.prefix(4)), id: \.self) { tag in
                        TagChip(tag: tag) { actions.onSelectTag(tag) }
                    }
                    let overflow = bookmark.tags.count - 4
                    if overflow > 0 {
                        Button {
                            withAnimation(CurioMotion.liquid) { isExpanded = true }
                        } label: {
                            Text("+\(overflow)")
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(colors.onSurface.opacity(0.6))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(colors.onSurface.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.curioPressBounce)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Analysis error strip

    private func analysisErrorStrip(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(colors.error)
            Text(message)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(colors.error)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { actions.onRunAiAnalysis() } label: {
                Text("Retry")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(colors.error)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(colors.error.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.curioPressBounce)
            .accessibilityIdentifier("card_retry_curate_\(bookmark.id)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassSurface(tier: tier, shape: RoundedRectangle(cornerRadius: 12, style: .continuous), tint: colors.errorContainer.opacity(0.25))
    }

    // MARK: Footer

    private var footer: some View {
        HStack(alignment: .center) {
            HStack(spacing: 7) {
                if let tweetLink {
                    Button { openUrlWithFeedback(tweetLink) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(colors.primary)
                            Text("View on X")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(colors.primary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(colors.primary.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.curioPressBounce)
                    .accessibilityIdentifier("view_tweet_button_\(bookmark.id)")
                }

                if let currentSpace {
                    let spColor = Color(packedARGB: currentSpace.color)
                    Button { actions.onSelectSpace(currentSpace.id) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: spaceIcon(currentSpace.icon))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(spColor)
                            Text(currentSpace.name)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(spColor)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(spColor.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.curioPressBounce)
                } else if let suggestedSpace {
                    let sugColor = Color(packedARGB: suggestedSpace.color)
                    Button { actions.onAssignToSpace(suggestedSpace.id) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(sugColor)
                            Text(suggestedSpace.name)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(sugColor)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay { Capsule().stroke(sugColor.opacity(0.5), lineWidth: 1) }
                    }
                    .buttonStyle(.curioPressBounce)
                    .accessibilityIdentifier("suggest_semantic_\(bookmark.id)")
                } else if !bookmark.isAnalyzed && !isProcessing {
                    Button { actions.onRunAiAnalysis() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(colors.primary)
                            Text("Curate")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(colors.primary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(colors.primary.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.curioPressBounce)
                    .accessibilityIdentifier("curate_chip_\(bookmark.id)")
                } else if bookmark.isAnalyzed, let category = bookmark.category, !category.isBlank {
                    // Unfiled but categorised → AI category suggests a Space; tap to file.
                    let meta = CategorySpaces.forCategory(category)
                    let sugColor = Color(packedARGB: meta.color)
                    Button { actions.onAcceptCategory() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(sugColor)
                            Text(meta.name)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(sugColor)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay { Capsule().stroke(sugColor.opacity(0.5), lineWidth: 1) }
                    }
                    .buttonStyle(.curioPressBounce)
                    .accessibilityIdentifier("suggest_space_\(bookmark.id)")
                }

                if bookmark.sourceType != nil {
                    HStack(spacing: 4) {
                        Text(CurioFormat.sourceDisplayName(bookmark))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(srcColor)
                        if bookmark.referenceCount > 1 {
                            Text("×\(bookmark.referenceCount)")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(srcColor)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(srcColor.opacity(0.14), in: Capsule())
                }

                if let summary = bookmark.summary, !summary.isBlank {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(colors.secondary)
                        .accessibilityLabel("Has summary")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 2) {
                Button { actions.onToggleFavorite() } label: {
                    Image(systemName: bookmark.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(bookmark.isFavorite ? Color(argb: 0xFFFF5A6E) : colors.onSurface.opacity(0.55))
                        .bounceScale(active: bookmark.isFavorite)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(bookmark.isFavorite ? "Unfavorite" : "Favorite")
                .accessibilityIdentifier("favorite_button_\(bookmark.id)")

                Button { actions.onToggleSavedForLater() } label: {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(bookmark.isSavedForLater ? colors.secondary : colors.onSurface.opacity(0.4))
                        .bounceScale(active: bookmark.isSavedForLater)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(bookmark.isSavedForLater ? "Remove from read later" : "Save for later")
                .accessibilityIdentifier("readlater_button_\(bookmark.id)")

                Button { showOptions = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(colors.onSurface.opacity(0.55))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More options")
                .accessibilityIdentifier("card_more_button_\(bookmark.id)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Expanded details

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle()
                .fill(colors.onSurface.opacity(0.08))
                .frame(height: 1)
                .frame(maxWidth: .infinity)

            if let url = bookmark.url, !url.isBlank {
                Button { openUrlWithFeedback(url) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(colors.primary)
                        Text(url)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .underline()
                            .foregroundStyle(colors.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("OPEN")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(colors.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(colors.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("open_link_row_\(bookmark.id)")
            }

            // OCR status / output.
            if bookmark.isOcrScheduled {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(colors.primary)
                    Text("EXTRACTING TEXT…")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(colors.primary)
                }
            } else if let ocr = bookmark.ocrText, !ocr.isBlank {
                DetailPanel(label: "OCR EXTRACTED", body: ocr, accent: colors.primary)
            }

            if bookmark.isAnalyzed, let summary = bookmark.summary, !summary.isBlank {
                DetailPanel(label: "QUICK SUMMARY", body: summary, accent: colors.secondary, bold: true)
            }
            if bookmark.isDeepAnalyzed, let deep = bookmark.deepSummary, !deep.isBlank {
                MarkdownDetailPanel(label: "DEEP ANALYSIS", body: deep, accent: colors.tertiary, systemImage: "sparkles")
            }
            if let abstract = bookmark.sourceAbstract, !abstract.isBlank {
                DetailPanel(label: "ABSTRACT", body: abstract, accent: srcColor)
            }

            // Personal note.
            if let notes = bookmark.notes, !notes.isBlank {
                Button { showNotesEditor = true } label: {
                    DetailPanel(label: "MY NOTE", body: notes, accent: colors.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("note_panel_\(bookmark.id)")
            } else {
                Button { showNotesEditor = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(colors.tertiary)
                        Text("ADD A NOTE")
                            .font(.system(size: 11, weight: .black))
                            .tracking(0.6)
                            .foregroundStyle(colors.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colors.tertiary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("add_note_row_\(bookmark.id)")
            }

            if bookmark.isAnalyzed && !bookmark.tags.isEmpty {
                FlexTagFlow(tags: bookmark.tags) { tag in
                    actions.onSelectTag(tag)
                }
            }

            // "CURATE, SHARE & MORE" opener.
            Button { showOptions = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.primary)
                    Text("CURATE, SHARE & MORE")
                        .font(.system(size: 11, weight: .black))
                        .tracking(0.6)
                        .foregroundStyle(colors.primary)
                    Spacer(minLength: 0)
                    if isProcessing {
                        ProgressView().controlSize(.small).tint(colors.primary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(colors.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("card_actions_row_\(bookmark.id)")
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - FlexTagFlow

/// A wrapping flow of full `TagChip`s for the expanded tag section (ports the Compose
/// `FlowRow`). Uses SwiftUI's native `Layout` wrap via a flexible HStack-of-rows builder.
private struct FlexTagFlow: View {
    let tags: [String]
    let onSelect: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 7) {
            ForEach(tags, id: \.self) { tag in
                TagChip(tag: tag) { onSelect(tag) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A simple flow layout (left-to-right, wrapping) — the SwiftUI analogue of Compose `FlowRow`.
/// Shared by tag flows and chip rows. Honors the container width and wraps when the next
/// subview would overflow.
struct FlowLayout: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth - spacing)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth - spacing)
        return CGSize(width: maxWidth == .infinity ? totalWidth : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - CardOptionsSheet

/// A `CardAction` — one tappable action inside `CardOptionsSheet`.
private struct CardAction: Identifiable {
    let id = UUID()
    let label: String
    let systemImage: String
    let tint: Color
    let onClick: () -> Void
}

/// Bottom sheet opened by holding a card (or tapping ⋯). Houses every per-card action so the
/// card face stays clean. Multi-select is reachable here via "Select". The sheet animates
/// closed (`act { … }` → dismiss then run) and delete is two-step.
private struct CardOptionsSheet: View {
    let bookmark: Bookmark
    let actions: CurioCardActions
    let isProcessing: Bool
    let shareableText: String
    let tweetLink: String?
    let chronosFlowInstalled: Bool
    let tier: GlassTier
    let onOcr: () -> Void
    let onSelect: () -> Void
    let onReader: () -> Void
    let onMoveToSpace: () -> Void
    let onNotes: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.curioColors) private var colors

    @State private var confirmingDelete = false

    /// Animate the sheet closed, then run the action. (`.sheet` dismissal is the platform
    /// animation; we dismiss first, then perform on the next runloop tick so the sheet has
    /// begun closing — matching the Android `sheetState.hide().invokeOnCompletion { … }`.)
    private func act(_ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.async { action() }
    }

    /// BibTeX export for the tile row. Unlike the Android `remember`, this recomputes on every
    /// body evaluation — `exportBibtex` is a pure, cheap string build, so the output is identical
    /// and memoization isn't worth `@State` plumbing here.
    private var bibtexText: String? { actions.exportBibtex() }

    private var curateActions: [CardAction] {
        var list: [CardAction] = []
        if !isProcessing {
            list.append(CardAction(
                label: bookmark.isAnalyzed ? "Re-curate" : "AI Curate",
                systemImage: bookmark.isAnalyzed ? "arrow.triangle.2.circlepath" : "brain.head.profile",
                tint: colors.primary
            ) { actions.onRunAiAnalysis() })
        }
        list.append(CardAction(
            label: bookmark.isDeepAnalyzed ? "Reanalyze+" : "Deep analyze",
            systemImage: "sparkles",
            tint: colors.tertiary
        ) { actions.onRunDeepAnalysis() })
        list.append(CardAction(
            label: (bookmark.ocrText?.nonEmptyBlank ?? false) ? "Update image text" : "Scan image (OCR)",
            systemImage: "camera.viewfinder",
            tint: colors.secondary,
            onClick: onOcr
        ))
        return list
    }

    private var moreActions: [CardAction] {
        var list: [CardAction] = []
        list.append(CardAction(label: "Share", systemImage: "square.and.arrow.up", tint: colors.onSurface.opacity(0.7)) {
            if CurioFormat.shareBookmark(shareableText) {
                CurioNotifier.notify("Share sheet opened")
            } else {
                CurioNotifier.notify("Failed to share")
            }
        })
        list.append(CardAction(label: "Reader view", systemImage: "book", tint: colors.primary, onClick: onReader))
        list.append(CardAction(
            label: (bookmark.notes?.nonEmptyBlank ?? false) ? "Edit note" : "Add note",
            systemImage: "pencil",
            tint: colors.tertiary,
            onClick: onNotes
        ))
        if bookmark.sourceType == nil {
            list.append(CardAction(label: "Resolve source", systemImage: "link", tint: colors.secondary) {
                actions.onResolveSource()
            })
        }
        if bookmark.sourceType == .ARXIV, let bib = bibtexText {
            list.append(CardAction(label: "Copy BibTeX", systemImage: "doc.on.doc", tint: Color(argb: 0xFFE53935)) {
                if CurioFormat.copyToClipboard(bib, label: "BibTeX") {
                    CurioNotifier.notify("Copied to clipboard")
                } else {
                    CurioNotifier.notify("Failed to copy")
                }
            })
        }
        if let tweetLink {
            list.append(CardAction(label: "View on X", systemImage: "arrow.up.forward.square", tint: colors.primary) {
                openUrlWithFeedback(tweetLink)
            })
        }
        return list
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                SheetHeader(bookmark: bookmark)
                SheetDivider().padding(.vertical, 4)

                SheetQuickIconRow(
                    bookmark: bookmark,
                    onCopy: {
                        act {
                            if CurioFormat.copyToClipboard(shareableText) {
                                CurioNotifier.notify("Copied to clipboard")
                            } else {
                                CurioNotifier.notify("Failed to copy")
                            }
                        }
                    },
                    onFavorite: { actions.onToggleFavorite() },
                    onReadLater: { actions.onToggleSavedForLater() },
                    onChangeSpace: { act(onMoveToSpace) },
                    onOpenLink: (bookmark.url?.nonEmptyBlank).map { url in
                        { act { openUrlWithFeedback(url) } }
                    }
                )

                if !curateActions.isEmpty {
                    SheetDivider().padding(.vertical, 8)
                    SheetSectionLabel("CURATE")
                    if isProcessing {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(colors.primary)
                            Text("Curating…")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(colors.onSurface.opacity(0.7))
                        }
                        .padding(.leading, 4)
                        .padding(.vertical, 2)
                    }
                    ForEach(curateActions) { action in
                        SheetListRow(action: action) { act(action.onClick) }
                    }
                }

                if !moreActions.isEmpty {
                    SheetDivider().padding(.vertical, 8)
                    SheetSectionLabel("MORE")
                    ForEach(moreActions) { action in
                        SheetListRow(action: action) { act(action.onClick) }
                    }
                }

                if chronosFlowInstalled {
                    SheetDivider().padding(.vertical, 8)
                    ChronosFlowActions(
                        onRemind: { choice in act { actions.onRemindInChronosFlow(choice) } },
                        onCapture: { act { actions.onCaptureToChronosFlow() } },
                        onCreateTask: { act { actions.onCreateChronosFlowTask() } }
                    )
                }

                SheetDivider().padding(.vertical, 8)

                // Select / Delete (two-step delete).
                if confirmingDelete {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(colors.error)
                        Text("Delete this card?")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(colors.onSurface)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { confirmingDelete = false } label: {
                            Text("CANCEL")
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(colors.onSurface.opacity(0.6))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        Button { act { actions.onDelete() } } label: {
                            Text("DELETE")
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(colors.error)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(colors.error.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sheet_delete_confirm_button_\(bookmark.id)")
                    }
                    .padding(.init(top: 8, leading: 14, bottom: 8, trailing: 8))
                    .frame(maxWidth: .infinity)
                    .background(colors.error.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(colors.error.opacity(0.25), lineWidth: 1) }
                    .accessibilityIdentifier("sheet_delete_confirm_\(bookmark.id)")
                } else {
                    SheetFooterRow(
                        onSelect: { act(onSelect) },
                        onDelete: { confirmingDelete = true }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(colors.surface)
    }
}

// MARK: - Sheet pieces

/// ChronosFlow productivity actions inside the options sheet: save the bookmark to ChronosFlow's
/// reading list with an optional "remind me to read later" time, drop it into the inbox, or turn
/// it into a follow-up task. The reminder row expands to a small set of preset times (the app has
/// no time picker). Shown only when ChronosFlow is installed. Port of the Android
/// `ChronosFlowActions` composable.
private struct ChronosFlowActions: View {
    let onRemind: (ChronosReminderChoice) -> Void
    let onCapture: () -> Void
    let onCreateTask: () -> Void

    @Environment(\.curioColors) private var colors
    @State private var remindExpanded = false

    var body: some View {
        Text("CHRONOSFLOW")
            .font(.system(size: 11, weight: .black))
            .tracking(0.6)
            .foregroundStyle(colors.primary)
        ChronosRow(systemImage: "alarm", label: "Remind me to read later", tint: colors.secondary) {
            remindExpanded.toggle()
        }
        if remindExpanded {
            ForEach(Array(ChronosReminderChoice.allCases.enumerated()), id: \.offset) { _, choice in
                Button { onRemind(choice) } label: {
                    Text(choice.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(colors.onSurface)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.init(top: 10, leading: 38, bottom: 10, trailing: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chronos_remind_\(choice.label)")
            }
        }
        ChronosRow(systemImage: "tray.and.arrow.down", label: "Capture to ChronosFlow inbox", tint: colors.tertiary, onClick: onCapture)
        ChronosRow(systemImage: "checklist", label: "Create ChronosFlow task", tint: colors.primary, onClick: onCreateTask)
    }
}

/// One tappable ChronosFlow row (icon + label). Port of the Android `ChronosRow` composable.
private struct ChronosRow: View {
    let systemImage: String
    let label: String
    let tint: Color
    let onClick: () -> Void

    @Environment(\.curioColors) private var colors

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.onSurface)
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chronos_row_\(label)")
    }
}

/// A thin divider used between options-sheet sections.
private struct SheetDivider: View {
    @Environment(\.curioColors) private var colors
    var body: some View {
        Rectangle()
            .fill(colors.onSurface.opacity(0.08))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

/// Card header with source accent and title preview.
private struct SheetHeader: View {
    let bookmark: Bookmark

    @Environment(\.curioColors) private var colors

    private var sourceAccent: Color {
        switch bookmark.sourceType {
        case .ARXIV: Color(argb: 0xFFE53935)
        case .GITHUB: Color(argb: 0xFF66BB6A)
        case .HUGGING_FACE: Color(argb: 0xFFFFB300)
        default: colors.primary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(sourceAccent)
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(CurioFormat.sourceDisplayName(bookmark)) · \(CurioFormat.relativeTime(bookmark.createdAt))")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(colors.primary)
                Text((bookmark.title?.nonEmptyOrNil) ?? CurioFormat.cleanSnippet(bookmark.text))
                    .font(.system(size: 18, weight: .black))
                    .lineSpacing(22 - 18)
                    .foregroundStyle(colors.onSurface)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Uppercase section label for grouped sheet actions.
private struct SheetSectionLabel: View {
    let text: String

    @Environment(\.curioColors) private var colors

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .black))
            .tracking(0.8)
            .foregroundStyle(colors.onSurface.opacity(0.45))
            .padding(.leading, 4)
            .padding(.bottom, 2)
    }
}

/// Icon-only quick actions row using outlined SF Symbols. Toggles stay in-sheet; navigational actions dismiss.
private struct SheetQuickIconRow: View {
    let bookmark: Bookmark
    let onCopy: () -> Void
    let onFavorite: () -> Void
    let onReadLater: () -> Void
    let onChangeSpace: () -> Void
    let onOpenLink: (() -> Void)?

    @Environment(\.curioColors) private var colors

    var body: some View {
        HStack(spacing: 8) {
            SheetIconButton(
                systemImage: "doc.on.doc",
                label: "Copy",
                tint: colors.onSurface.opacity(0.7),
                onClick: onCopy
            )
            SheetIconButton(
                systemImage: "heart",
                label: bookmark.isFavorite ? "Unfavorite" : "Favorite",
                tint: bookmark.isFavorite ? Color(argb: 0xFFFF5A6E) : colors.onSurface.opacity(0.7),
                active: bookmark.isFavorite,
                onClick: onFavorite
            )
            SheetIconButton(
                systemImage: "clock",
                label: bookmark.isSavedForLater ? "Remove from read later" : "Save for later",
                tint: bookmark.isSavedForLater ? colors.secondary : colors.onSurface.opacity(0.7),
                active: bookmark.isSavedForLater,
                onClick: onReadLater
            )
            SheetIconButton(
                systemImage: "square.grid.2x2",
                label: (bookmark.spaceId.map { !$0.isEmpty } ?? false) ? "Change space" : "Add to space",
                tint: colors.tertiary,
                onClick: onChangeSpace
            )
            if let onOpenLink {
                SheetIconButton(
                    systemImage: "link",
                    label: "Open link",
                    tint: colors.secondary,
                    onClick: onOpenLink
                )
            }
        }
    }
}

/// A single icon-only button in `SheetQuickIconRow`.
private struct SheetIconButton: View {
    let systemImage: String
    let label: String
    let tint: Color
    var active: Bool = false
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(tint.opacity(active ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    if active {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(tint.opacity(0.45), lineWidth: 1)
                    }
                }
                .bounceScale(active: active)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("sheet_icon_\(label)")
    }
}

/// Full-width list row for secondary sheet actions.
private struct SheetListRow: View {
    let action: CardAction
    let onClick: () -> Void

    @Environment(\.curioColors) private var colors

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 14) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(action.tint)
                    .frame(width: 20)
                Text(action.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.onSurface.opacity(0.25))
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 4)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sheet_row_\(action.label)")
    }
}

/// Compact footer for multi-select entry and destructive delete.
private struct SheetFooterRow: View {
    let onSelect: () -> Void
    let onDelete: () -> Void

    @Environment(\.curioColors) private var colors

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Select")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(colors.onSurface.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(colors.onSurface.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Delete")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(colors.error)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(colors.error.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sheet_delete_button")
        }
    }
}

// MARK: - URL open feedback

private func openUrlWithFeedback(_ rawUrl: String?) {
    switch CurioFormat.openUrl(rawUrl) {
    case .opened: break
    case .noLink: CurioNotifier.notify("No link on this bookmark")
    case .failed: CurioNotifier.notify("Couldn't open link")
    }
}

// MARK: - PostImageLoadingPlaceholder

/// Shimmer-style loading placeholder for post images. Mirrors Android `SubcomposeAsyncImage`
/// loading state with reduce-motion support (static tint vs pulsing alpha).
private struct PostImageLoadingPlaceholder: View {
    let srcColor: Color
    let reduceMotion: Bool

    @State private var pulse = false

    var body: some View {
        Rectangle()
            .fill(srcColor.opacity(reduceMotion ? 0.4 : (pulse ? 0.6 : 0.25)))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - String helpers

private extension String {
    /// Returns the original string when it is non-blank, else nil (Kotlin
    /// `takeIf { it.isNotBlank() }` — the value returned is the ORIGINAL, not the trimmed one).
    var nonEmptyOrNil: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
    /// True when this string is non-blank (Kotlin `!isNullOrBlank()` after unwrap).
    var nonEmptyBlank: Bool { !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
