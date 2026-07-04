//
//  CurioDialogs.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/CurioDialogs.kt
//         (LocalSlideUpDismiss, SlideUpCard, ManualAddBookmarkDialog, NotesEditorDialog,
//          BulkCategoryDialog, CurioEmptyState).
//
//  The app's slide-up card pattern (the replacement for centered modal dialogs) plus the
//  add/notes/category dialogs and the empty state.
//
//  CONVENTIONS §8/§9:
//   - `SlideUpCard` → a `.sheet` with `.presentationDetents([.fraction(0.92)])`, a drag
//     indicator, a 28pt top-corner glass background, and the grab handle / scroll / insets the
//     callers rely on. The Android `LocalSlideUpDismiss` CompositionLocal becomes a SwiftUI
//     environment value (`\.slideUpDismiss`) that animates the sheet closed; with a `.sheet`
//     the dismissal is the platform animation, so the environment closure routes through the
//     standard `dismiss` for Cancel/confirm buttons.
//   - NotesEditorDialog: empty save clears the note (trim → nil) and the button flips
//     CLEAR/SAVE; exact user-facing strings preserved.
//   - BulkCategoryDialog: the fixed 9-category list + per-row deterministic category color dot.
//   - CurioEmptyState: the orbital sphere + exact copy + INITIALIZE RETRIEVAL SYNC action.
//   - Press feedback via `.curioPressBounce`; honor Reduce Transparency through `glassSurface`.
//

import SwiftUI

// MARK: - LocalSlideUpDismiss (environment)

/// Within a `SlideUpCard`, dismisses the card (animating it closed) rather than tearing it
/// down instantly. Read it inside the card body and use it for Cancel/confirm buttons so every
/// dismissal animates: `@Environment(\.slideUpDismiss) private var dismissCard`. Defaults to a
/// no-op outside a card. Ports the Compose `LocalSlideUpDismiss` CompositionLocal.
private struct SlideUpDismissKey: EnvironmentKey {
    // No-op default closure; safe to share as a constant.
    nonisolated(unsafe) static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var slideUpDismiss: () -> Void {
        get { self[SlideUpDismissKey.self] }
        set { self[SlideUpDismissKey.self] = newValue }
    }
}

// MARK: - SlideUpCard

/// A bottom-anchored card that slides up from the bottom of the screen — the app's replacement
/// for centered modal dialogs. Presented as a `.sheet` (which owns its own scrim, drag-to-
/// dismiss, and back handling) detented to 92% of the screen height, with a glass surface,
/// grab handle, scroll, and keyboard/safe-area insets so callers supply ONLY their content.
///
/// In-card buttons dismiss via `@Environment(\.slideUpDismiss)`.
///
/// - Note: Android rendered this inside a full-bleed `Dialog` and hand-rolled the slide
///   animation; on iOS the native `.sheet` provides the equivalent slide-up + scrim. The
///   `tier`/`tint`/`borderColor` glass styling is preserved on the sheet content background.
struct SlideUpCard<Content: View>: View {
    let tier: GlassTier
    var borderColor: Color? = nil
    var tint: Color? = nil
    var contentPadding: CGFloat = 24
    var spacing: CGFloat = 16
    var horizontalAlignment: HorizontalAlignment = .leading
    @ViewBuilder var content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @Environment(\.curioColors) private var colors

    private var resolvedTint: Color { tint ?? colors.surface.opacity(0.96) }
    private var resolvedBorder: Color { borderColor ?? colors.primary.opacity(0.25) }

    var body: some View {
        ScrollView {
            VStack(alignment: horizontalAlignment, spacing: spacing) {
                // Grab handle (the sheet also shows the system drag indicator; this mirrors
                // the Android card's own 40×4 handle for visual parity).
                Capsule()
                    .fill(colors.onSurface.opacity(0.22))
                    .frame(width: 40, height: 4)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 10)

                content()
            }
            .padding(.horizontal, contentPadding)
            .padding(.bottom, contentPadding)
            .frame(maxWidth: .infinity, alignment: horizontalAlignment == .center ? .center : .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 28, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 28,
                style: .continuous
            )
            .glassSurface(
                tier: tier,
                shape: UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 28, style: .continuous),
                tint: resolvedTint,
                borderColor: resolvedBorder
            )
            .ignoresSafeArea()
        )
        .presentationDetents([.fraction(0.92)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        .environment(\.slideUpDismiss, { dismiss() })
    }
}

// MARK: - ManualAddBookmarkDialog

/// Add a snippet or URL with an instant AI summary preview before committing. Mirrors the
/// Android dialog: text field, error text on empty submit, a PREVIEW COGNITIVE SUMMARY trigger
/// that calls `onRequestPreview`, the resulting INSTANT AI PREVIEW panel, and CANCEL /
/// PROCESS & ADD actions.
///
/// - Note: Android passed the whole `BookmarkViewModel` and called
///   `viewModel.getInstantSummaryPreview(text) { preview -> … }`. To keep this leaf widget
///   decoupled from the (Platform-layer) ViewModel, the preview call is hoisted as
///   `onRequestPreview(text, completion)` — the owning screen wires it to the VM. Behavior and
///   strings are identical.
struct ManualAddBookmarkDialog: View {
    let tier: GlassTier
    let onAddBookmark: (String) -> Void
    /// `getInstantSummaryPreview(text) { preview in … }` hoisted as a closure.
    let onRequestPreview: (String, @escaping (String?) -> Void) -> Void

    @Environment(\.slideUpDismiss) private var dismissCard
    @Environment(\.curioColors) private var colors

    @State private var textInput: String = ""
    @State private var errorText: String = ""
    @State private var previewSummary: String? = nil
    @State private var isPreviewLoading: Bool = false

    var body: some View {
        SlideUpCard(tier: tier, spacing: 16, horizontalAlignment: .center) {
            Text("ADD SNIPPET OR URL")
                .font(.system(size: 18, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(colors.primary)

            Text("Enter a URL link or a plain text snippet. You can instantly preview the summary before committing the bookmark database save.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(colors.onSurface.opacity(0.6))
                .multilineTextAlignment(.center)

            TextEditor(text: $textInput)
                .font(.system(size: 14, weight: .medium))
                .frame(height: 140)
                .scrollContentBackground(.hidden)
                .padding(8)
                .overlay(alignment: .topLeading) {
                    if textInput.isEmpty {
                        Text("https://example.com/article\n\nOr type/paste your snippet to analyze here...")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(colors.onSurface.opacity(0.4))
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.clear))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(textInput.isEmpty ? colors.onSurface.opacity(0.15) : colors.primary, lineWidth: 1)
                }
                .accessibilityIdentifier("manual_bookmark_input")
                .onChange(of: textInput) { _, newValue in
                    if !newValue.isBlank { errorText = "" }
                }

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(colors.error)
            }

            // Instant Summarization Preview widget.
            if isPreviewLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(colors.primary)
                Text("Architecting cognitive preview...")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(colors.primary)
            }

            if let summary = previewSummary {
                VStack(alignment: .leading, spacing: 6) {
                    Text("INSTANT AI PREVIEW")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(colors.primary)
                    Text(summary)
                        .font(.system(size: 12, weight: .regular))
                        .lineSpacing(16 - 12)
                        .foregroundStyle(colors.onSurface)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .glassSurface(
                    tier: tier,
                    shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                    tint: colors.primary.opacity(0.05)
                )
            }

            // Preview trigger button.
            if !textInput.isBlank && !isPreviewLoading {
                Button {
                    isPreviewLoading = true
                    onRequestPreview(textInput) { preview in
                        isPreviewLoading = false
                        previewSummary = preview
                    }
                } label: {
                    Text("PREVIEW COGNITIVE SUMMARY")
                        .font(.system(size: 14, weight: .heavy))
                        .tracking(0.1)
                        .foregroundStyle(colors.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(colors.secondary.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.curioPressBounce)
                .accessibilityIdentifier("instant_preview_button")
            }

            HStack(spacing: 12) {
                Button { dismissCard() } label: {
                    Text("CANCEL")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(colors.onSurface.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(colors.onSurface.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.curioPressBounce)

                Button {
                    if textInput.isBlank {
                        errorText = "Field cannot be empty"
                    } else {
                        onAddBookmark(textInput)
                        dismissCard()
                    }
                } label: {
                    Text("PROCESS & ADD")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(colors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(colors.primary,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.curioPressBounce)
                .accessibilityIdentifier("manual_bookmark_submit")
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - NotesEditorDialog

/// Editor for a bookmark's personal note/annotation. Pre-fills `existingNote`; an empty save
/// clears the note (trim → nil). The save button flips between CLEAR and SAVE. Local-only.
struct NotesEditorDialog: View {
    let existingNote: String?
    let tier: GlassTier
    let onSave: (String?) -> Void

    @Environment(\.slideUpDismiss) private var dismissCard
    @Environment(\.curioColors) private var colors

    @State private var noteInput: String

    init(existingNote: String?, tier: GlassTier, onSave: @escaping (String?) -> Void) {
        self.existingNote = existingNote
        self.tier = tier
        self.onSave = onSave
        _noteInput = State(initialValue: existingNote ?? "")
    }

    private var existingIsBlank: Bool { (existingNote ?? "").isBlank }

    var body: some View {
        SlideUpCard(
            tier: tier,
            borderColor: colors.tertiary.opacity(0.25),
            spacing: 16,
            horizontalAlignment: .center
        ) {
            Text(existingIsBlank ? "ADD A NOTE" : "EDIT NOTE")
                .font(.system(size: 18, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(colors.tertiary)

            Text("Your private annotation for this entry — thoughts, why you saved it, follow-ups. Stays on this device.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(colors.onSurface.opacity(0.6))
                .multilineTextAlignment(.center)

            TextEditor(text: $noteInput)
                .font(.system(size: 14, weight: .medium))
                .frame(height: 160)
                .scrollContentBackground(.hidden)
                .padding(8)
                .overlay(alignment: .topLeading) {
                    if noteInput.isEmpty {
                        Text("Type your note here…")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(colors.onSurface.opacity(0.4))
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(noteInput.isEmpty ? colors.onSurface.opacity(0.15) : colors.tertiary, lineWidth: 1)
                }
                .accessibilityIdentifier("note_editor_input")

            HStack(spacing: 12) {
                Button { dismissCard() } label: {
                    Text("CANCEL")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(colors.onSurface.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(colors.onSurface.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.curioPressBounce)

                Button {
                    // Trim → nil clears the note downstream.
                    let trimmed = noteInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(trimmed.isEmpty ? nil : trimmed)
                } label: {
                    Text(noteInput.isBlank && !existingIsBlank ? "CLEAR" : "SAVE")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(colors.onTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(colors.tertiary,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.curioPressBounce)
                .accessibilityIdentifier("note_editor_save")
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - BulkCategoryDialog

/// Choose a destination category for all selected bookmarks. Fixed 9-category list, each with a
/// deterministic color dot (the Java-hashCode palette), plus a CANCEL action.
struct BulkCategoryDialog: View {
    let tier: GlassTier
    let onCategorySelected: (String) -> Void

    @Environment(\.slideUpDismiss) private var dismissCard
    @Environment(\.curioColors) private var colors

    /// The exact fixed list from the Android dialog.
    private let categories = ["Work", "Personal", "Reading List", "Development", "Design", "Marketing", "Crypto", "Business", "Life"]

    var body: some View {
        SlideUpCard(tier: tier, spacing: 16, horizontalAlignment: .center) {
            Text("CATEGORIZE SELECT ITEMS")
                .font(.system(size: 18, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(colors.primary)

            Text("Choose a destination category descriptor for all selected bookmarks.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(colors.onSurface.opacity(0.6))
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    Button {
                        onCategorySelected(cat)
                        dismissCard()
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(CurioFormat.getCategoryColor(cat))
                                .frame(width: 10, height: 10)
                            Text(cat.uppercased())
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(colors.onSurface.opacity(0.8))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(colors.onSurface.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.curioPressBounce)
                }
            }
            .frame(maxWidth: .infinity)

            Button { dismissCard() } label: {
                Text("CANCEL")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(colors.onSurface.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(colors.onSurface.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.curioPressBounce)
        }
    }
}

// MARK: - CurioEmptyState

/// The library-empty state: a glowing orbital sphere with a frosted shield orb, the exact
/// title/body copy, and the INITIALIZE RETRIEVAL SYNC action button.
struct CurioEmptyState: View {
    let tier: GlassTier
    var onActionClick: () -> Void = {}

    @Environment(\.curioColors) private var colors

    var body: some View {
        VStack(spacing: 20) {
            // Glowing orbital sphere representing an offline index.
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                colors.primary.opacity(0.25),
                                colors.secondary.opacity(0.05),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 50
                        )
                    )
                    .frame(width: 100, height: 100)

                // Frosted central shield orb.
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(colors.primary)
                    .accessibilityLabel("No bookmarks")
                    .frame(width: 64, height: 64)
                    .glassSurface(
                        tier: tier,
                        shape: RoundedRectangle(cornerRadius: 20, style: .continuous),
                        tint: colors.surface.opacity(0.6),
                        borderColor: colors.primary.opacity(0.3)
                    )
            }

            VStack(spacing: 8) {
                Text("YOUR CURIO ARCHIVE IS EMPTY")
                    .font(.system(size: 18, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(colors.onSurface)
                Text("Sync down recent bookmarks from your X timeline, or manually input text snippets and web links to build your curated, searchable database.")
                    .font(.system(size: 12, weight: .regular))
                    .lineSpacing(18 - 12)
                    .foregroundStyle(colors.onSurface.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            Button(action: onActionClick) {
                Text("INITIALIZE RETRIEVAL SYNC")
                    .font(.system(size: 11, weight: .black))
                    .tracking(0.5)
                    .foregroundStyle(colors.onPrimary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(colors.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.curioPressBounce)
            .accessibilityIdentifier("empty_state_action")
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .glassSurface(
            tier: tier,
            shape: RoundedRectangle(cornerRadius: 32, style: .continuous),
            tint: colors.surface.opacity(0.4),
            borderColor: colors.primary.opacity(0.15)
        )
        .padding(.vertical, 40)
        .padding(.horizontal, 8)
    }
}
