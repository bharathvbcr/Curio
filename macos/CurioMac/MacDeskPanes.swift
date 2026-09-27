import AppKit
import SwiftUI

// MARK: - List row

struct DeskBookmarkRow: View {
    let bookmark: Bookmark
    let spaceName: String?
    let tint: Color

    @Environment(\.curioColors) private var colors

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.16))
                Image(systemName: MacDeskLibrary.symbol(for: bookmark))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(MacDeskLibrary.title(bookmark))
                        .curioText(CurioFont.titleSmall)
                        .foregroundStyle(colors.onSurface)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(CurioFormat.relativeTime(bookmark.createdAt))
                        .font(.caption)
                        .foregroundStyle(colors.onSurfaceVariant)
                }
                let excerpt = MacDeskLibrary.excerpt(bookmark)
                if !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.system(size: 13))
                        .foregroundStyle(colors.onSurfaceVariant)
                        .lineLimit(2)
                }
                meta
            }

            if bookmark.isFavorite || bookmark.isSavedForLater || MacDeskLibrary.nonempty(bookmark.notes) != nil {
                VStack(spacing: 4) {
                    if bookmark.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(colors.tertiary)
                    }
                    if bookmark.isSavedForLater {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(colors.secondary)
                    }
                    if MacDeskLibrary.nonempty(bookmark.notes) != nil {
                        Image(systemName: "note.text")
                            .foregroundStyle(colors.onSurfaceVariant)
                    }
                }
                .font(.caption2)
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MacDeskLibrary.accessibilityLabel(bookmark, spaceName: spaceName))
    }

    private var meta: some View {
        HStack(spacing: 6) {
            if let byline = MacDeskLibrary.byline(bookmark) {
                Text(byline)
            }
            if let host = MacDeskLibrary.host(bookmark) {
                Text(host)
            }
            if let spaceName {
                Text(spaceName)
            }
        }
        .font(.caption)
        .foregroundStyle(colors.primary)
        .lineLimit(1)
    }
}

// MARK: - Reader

struct DeskReader: View {
    let bookmark: Bookmark
    let spaceName: String?
    let spaces: [Space]
    @Binding var notesDraft: String
    @Binding var question: String
    let research: DeskResearchPresentation?
    let isResearching: Bool
    let liveResearch: Bool
    let notesDirty: Bool
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onShare: () -> Void
    let onFavorite: () -> Void
    let onLater: () -> Void
    let onFile: (String?) -> Void
    let onSaveNotes: () -> Void
    let onResearch: () -> Void
    let onCopyBibtex: () -> Void
    let onDelete: () -> Void

    @Environment(\.curioColors) private var colors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actions
                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        if case let .success(image) = phase {
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .accessibilityLabel(bookmark.imageAltText ?? "Bookmark image")
                        }
                    }
                }
                if let summary = MacDeskLibrary.nonempty(bookmark.summary) {
                    Text(summary)
                        .curioText(CurioFont.bodyMedium)
                        .foregroundStyle(colors.onPrimaryContainer)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(colors.primaryContainer.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if !bookmark.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MarkdownText(markdown: bookmark.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !bookmark.tags.isEmpty {
                    Text(bookmark.tags.prefix(8).joined(separator: "  ·  "))
                        .font(.caption)
                        .foregroundStyle(colors.primary)
                }
                disclosures
                notes
                DeskResearchCard(
                    question: $question,
                    research: research,
                    isResearching: isResearching,
                    liveResearch: liveResearch,
                    onResearch: onResearch
                )
            }
            .padding(28)
            .frame(maxWidth: 740, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Web images only; a `file:` or custom-scheme URL from a synced post is ignored.
    private var imageURL: URL? {
        guard let raw = MacDeskLibrary.nonempty(bookmark.imageUrl) else { return nil }
        return MacDeskLibrary.safeWebURL(raw)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let eyebrow = spaceName ?? MacDeskLibrary.sourceLabel(bookmark.sourceType) {
                Text(eyebrow)
                    .curioText(CurioFont.labelSmall)
                    .textCase(.uppercase)
                    .foregroundStyle(colors.primary)
            }
            Text(MacDeskLibrary.title(bookmark))
                .curioText(CurioFont.headlineMedium)
                .foregroundStyle(colors.onBackground)
                .textSelection(.enabled)
            if let byline = MacDeskLibrary.byline(bookmark) {
                Text(byline)
                    .curioText(CurioFont.bodyMedium)
                    .foregroundStyle(colors.onSurfaceVariant)
            }
            Text(MacDeskLibrary.metaParts(bookmark).joined(separator: "  ·  "))
                .font(.caption)
                .foregroundStyle(colors.onSurfaceVariant)
            if let authors = MacDeskLibrary.nonempty(bookmark.sourceAuthors) {
                Text(authors)
                    .font(.callout)
                    .foregroundStyle(colors.onSurfaceVariant)
            }
            if bookmark.referenceCount > 1 {
                Text("\(bookmark.referenceCount) posts point at this source.")
                    .font(.caption)
                    .foregroundStyle(colors.onSurfaceVariant)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            .disabled(MacDeskLibrary.link(bookmark) == nil)
            .accessibilityIdentifier("mac_open_button")

            Button(action: onCopy) {
                Image(systemName: "link")
            }
            .help("Copy link")
            .accessibilityLabel("Copy link")

            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Share")
            .accessibilityLabel("Share")

            Menu {
                Button("Unfiled") { onFile(nil) }
                if !spaces.isEmpty { Divider() }
                ForEach(spaces) { space in
                    Button {
                        onFile(space.id)
                    } label: {
                        if bookmark.spaceId == space.id {
                            Label(space.name, systemImage: "checkmark")
                        } else {
                            Text(space.name)
                        }
                    }
                }
            } label: {
                Label(spaceName ?? "Unfiled", systemImage: "folder")
            }
            .menuStyle(.button)
            .help("File into a space")

            Spacer(minLength: 8)

            Button(action: onFavorite) {
                Image(systemName: bookmark.isFavorite ? "star.fill" : "star")
            }
            .foregroundStyle(bookmark.isFavorite ? colors.tertiary : colors.onSurface)
            .help(bookmark.isFavorite ? "Unstar" : "Star")
            .accessibilityLabel(bookmark.isFavorite ? "Unstar" : "Star")

            Button(action: onLater) {
                Image(systemName: bookmark.isSavedForLater ? "bookmark.fill" : "bookmark")
            }
            .help(bookmark.isSavedForLater ? "Remove from Read Later" : "Read later")
            .accessibilityLabel(bookmark.isSavedForLater ? "Remove from Read Later" : "Read later")

            Button(action: onCopyBibtex) {
                Image(systemName: "quote.opening")
            }
            .help("Copy BibTeX citation")
            .accessibilityLabel("Copy BibTeX citation")
            .disabled(MacDeskLibrary.bibtexCitation(bookmark) == nil)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .foregroundStyle(colors.error)
            .help("Delete bookmark")
            .accessibilityLabel("Delete bookmark")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @ViewBuilder
    private var disclosures: some View {
        if let ocr = MacDeskLibrary.nonempty(bookmark.ocrText) {
            DisclosureGroup("Text from the image") {
                Text(ocr)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
        if let deep = MacDeskLibrary.nonempty(bookmark.deepSummary),
           !deep.hasPrefix("{"), !deep.hasPrefix("[") {
            DisclosureGroup("Closer read") {
                MarkdownText(markdown: deep)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
        if let abstract = MacDeskLibrary.nonempty(bookmark.sourceAbstract), abstract != bookmark.text {
            DisclosureGroup("Source abstract") {
                Text(abstract)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note")
                .curioText(CurioFont.labelSmall)
                .textCase(.uppercase)
                .foregroundStyle(colors.primary)
            TextEditor(text: $notesDraft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 108, maxHeight: 240)
                .background(colors.surfaceVariant, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("Note")
            HStack {
                Text(notesDirty ? "Saving when you pause…" : "Notes stay on this Mac.")
                    .font(.caption)
                    .foregroundStyle(colors.onSurfaceVariant)
                Spacer()
                Button("Save Note", action: onSaveNotes)
                    .disabled(!notesDirty)
                    .keyboardShortcut("s", modifiers: .command)
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - Several selected

struct DeskBulkPanel: View {
    let bookmarks: [Bookmark]
    let spaces: [Space]
    let onFavorite: (Bool) -> Void
    let onLater: (Bool) -> Void
    let onFile: (String?) -> Void
    let onCopyLinks: () -> Void
    let onCopyBibtex: () -> Void
    let onExport: (DeskExportFormat) -> Void
    let onDelete: () -> Void
    let onClear: () -> Void

    @Environment(\.curioColors) private var colors

    private var starTarget: Bool { MacDeskLibrary.bulkFavoriteTarget(bookmarks) }
    private var laterTarget: Bool { MacDeskLibrary.bulkLaterTarget(bookmarks) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SELECTION")
                        .curioText(CurioFont.labelSmall)
                        .foregroundStyle(colors.primary)
                    Text(MacDeskLibrary.counted(bookmarks.count, "bookmark"))
                        .curioText(CurioFont.headlineLarge)
                        .foregroundStyle(colors.onBackground)
                    Text(summary)
                        .curioText(CurioFont.bodyLarge)
                        .foregroundStyle(colors.onSurfaceVariant)
                }

                HStack(spacing: 10) {
                    Button {
                        onFavorite(starTarget)
                    } label: {
                        Label(starTarget ? "Star All" : "Unstar All", systemImage: starTarget ? "star" : "star.slash")
                    }
                    Button {
                        onLater(laterTarget)
                    } label: {
                        Label(laterTarget ? "Read Later" : "Remove from Read Later", systemImage: "bookmark")
                    }
                    Menu {
                        Button("Unfiled") { onFile(nil) }
                        if !spaces.isEmpty { Divider() }
                        ForEach(spaces) { space in
                            Button(space.name) { onFile(space.id) }
                        }
                    } label: {
                        Label("File Into", systemImage: "folder")
                    }
                    .menuStyle(.button)
                }
                .buttonStyle(.bordered)

                HStack(spacing: 10) {
                    Button(action: onCopyLinks) {
                        Label("Copy Links", systemImage: "link")
                    }
                    Button(action: onCopyBibtex) {
                        Label("Copy BibTeX", systemImage: "quote.opening")
                    }
                    Menu {
                        ForEach(DeskExportFormat.allCases) { format in
                            Button(format.label + "…") { onExport(format) }
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .menuStyle(.button)
                }
                .buttonStyle(.bordered)

                HStack {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete \(bookmarks.count)…", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(colors.error)
                    Spacer()
                    Button("Clear Selection", action: onClear)
                        .buttonStyle(.borderless)
                        .keyboardShortcut(.cancelAction)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(bookmarks.prefix(12)) { bookmark in
                        Text("• " + MacDeskLibrary.title(bookmark))
                            .lineLimit(1)
                            .foregroundStyle(colors.onSurface)
                    }
                    if bookmarks.count > 12 {
                        Text("and \(bookmarks.count - 12) more")
                            .foregroundStyle(colors.onSurfaceVariant)
                    }
                }
                .font(.callout)
            }
            .controlSize(.regular)
            .padding(32)
            .frame(maxWidth: 740, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var summary: String {
        let starred = bookmarks.filter(\.isFavorite).count
        let later = bookmarks.filter(\.isSavedForLater).count
        let linked = bookmarks.filter { MacDeskLibrary.link($0) != nil }.count
        return "\(starred) starred · \(later) to read · \(linked) with links. Drag them onto a space in the sidebar to file them."
    }
}

// MARK: - Nothing selected

struct DeskWelcome: View {
    let title: String
    let message: String
    let summary: String
    @Binding var question: String
    let research: DeskResearchPresentation?
    let isResearching: Bool
    let liveResearch: Bool
    let onResearch: () -> Void

    @Environment(\.curioColors) private var colors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CURIO")
                        .curioText(CurioFont.labelSmall)
                        .textCase(.uppercase)
                        .foregroundStyle(colors.primary)
                    Text(title)
                        .curioText(CurioFont.headlineLarge)
                        .foregroundStyle(colors.onBackground)
                    Text(message)
                        .curioText(CurioFont.bodyLarge)
                        .foregroundStyle(colors.onSurfaceVariant)
                        .frame(maxWidth: 560, alignment: .leading)
                    Text(summary)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(colors.onSurface)
                        .padding(.top, 4)
                }
                DeskResearchCard(
                    question: $question,
                    research: research,
                    isResearching: isResearching,
                    liveResearch: liveResearch,
                    onResearch: onResearch
                )
                DeskShortcutsCard()
            }
            .padding(32)
            .frame(maxWidth: 740, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct DeskShortcutsCard: View {
    @Environment(\.curioColors) private var colors

    private let rows: [(String, String)] = [
        ("⌘N", "New bookmark"),
        ("⌘R", "Sync from X"),
        ("⇧⌘R", "Load older bookmarks"),
        ("⌘O", "Open the selected links"),
        ("⇧⌘S", "Star or unstar"),
        ("⇧⌘L", "Read later"),
        ("⇧⌘C", "Copy BibTeX"),
        ("⌘⌫", "Delete"),
        ("⌘A", "Select everything shown")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shortcuts")
                .curioText(CurioFont.labelSmall)
                .textCase(.uppercase)
                .foregroundStyle(colors.primary)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                ForEach(rows.indices, id: \.self) { index in
                    GridRow {
                        Text(rows[index].0)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(colors.onSurface)
                        Text(rows[index].1)
                            .font(.callout)
                            .foregroundStyle(colors.onSurfaceVariant)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(colors.outline.opacity(0.45), lineWidth: 1)
        )
    }
}

// MARK: - Research

struct DeskResearchCard: View {
    @Binding var question: String
    let research: DeskResearchPresentation?
    let isResearching: Bool
    let liveResearch: Bool
    let onResearch: () -> Void

    @Environment(\.curioColors) private var colors

    private var canAsk: Bool {
        !isResearching && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Research")
                    .curioText(CurioFont.labelSmall)
                    .textCase(.uppercase)
                    .foregroundStyle(colors.primary)
                Spacer()
                Text(liveResearch ? "Includes the live web" : "Uses this Mac only")
                    .font(.caption)
                    .foregroundStyle(colors.onSurfaceVariant)
            }
            TextField("Ask about something in this library", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(12)
                .background(colors.surfaceVariant, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onSubmit { if canAsk { onResearch() } }
            HStack {
                Button(action: onResearch) {
                    if isResearching {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Research")
                    }
                }
                .disabled(!canAsk)
                .accessibilityIdentifier("mac_research_button")
                Spacer()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            if let research {
                if let failure = research.failure {
                    Text(failure)
                        .curioText(CurioFont.bodyMedium)
                        .foregroundStyle(colors.error)
                } else if research.hasBody {
                    if !research.answer.isEmpty {
                        Text(research.answer)
                            .curioText(CurioFont.bodyMedium)
                            .foregroundStyle(colors.onSurface)
                            .textSelection(.enabled)
                    }
                    if !research.caveats.isEmpty {
                        Text(research.caveats)
                            .font(.callout)
                            .foregroundStyle(colors.onSurfaceVariant)
                            .textSelection(.enabled)
                    }
                    if !research.readingList.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reading")
                                .curioText(CurioFont.labelSmall)
                                .textCase(.uppercase)
                                .foregroundStyle(colors.primary)
                            ForEach(Array(research.readingList.enumerated()), id: \.offset) { _, item in
                                Text(item)
                                    .font(.callout)
                                    .foregroundStyle(colors.onSurface)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    if !research.citations.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(research.citations.enumerated()), id: \.offset) { _, raw in
                                // Citations come from a model: only web links become buttons.
                                if let url = MacDeskLibrary.safeWebURL(raw) {
                                    Button(raw) { _ = NSWorkspace.shared.open(url) }
                                        .buttonStyle(.link)
                                        .lineLimit(1)
                                        .help(raw)
                                } else {
                                    Text(raw)
                                        .font(.callout)
                                        .foregroundStyle(colors.onSurfaceVariant)
                                        .lineLimit(1)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                } else {
                    Text("No answer came back.")
                        .foregroundStyle(colors.onSurfaceVariant)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(colors.outline.opacity(0.45), lineWidth: 1)
        )
    }
}

// MARK: - Sheets

struct DeskSpaceSheet: View {
    let editor: DeskSpaceEditor
    let spaces: [Space]
    let onSave: (String, Int64, String) -> Void

    @State private var name: String
    @State private var selectedColor: Int64
    @State private var selectedIcon: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.curioColors) private var colors

    init(editor: DeskSpaceEditor, spaces: [Space], onSave: @escaping (String, Int64, String) -> Void) {
        self.editor = editor
        self.spaces = spaces
        self.onSave = onSave
        let existing = editor.existing
        _name = State(initialValue: existing?.name ?? "")
        _selectedColor = State(initialValue: existing?.color ?? MacDeskLibrary.spaceColorPalette.first?.color ?? 0xFF1E88E5)
        _selectedIcon = State(initialValue: existing?.icon ?? "folder")
    }

    private var problem: String? {
        MacDeskLibrary.spaceNameProblem(name, existing: spaces, excluding: editor.existing?.id)
    }

    private var title: String {
        switch editor {
        case .edit: return "Edit Space"
        case .newFiling(let ids): return ids.count > 1 ? "New Space for \(ids.count) Bookmarks" : "New Space"
        case .new: return "New Space"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .curioText(CurioFont.headlineSmall)
                .foregroundStyle(colors.onSurface)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .curioText(CurioFont.labelLarge)
                    .foregroundStyle(colors.onSurfaceVariant)
                TextField("Space name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                if let problem, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(colors.error)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .curioText(CurioFont.labelLarge)
                    .foregroundStyle(colors.onSurfaceVariant)
                HStack(spacing: 10) {
                    ForEach(MacDeskLibrary.spaceColorPalette, id: \.color) { item in
                        Button {
                            selectedColor = item.color
                        } label: {
                            Circle()
                                .fill(Color(packedARGB: item.color))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .strokeBorder(colors.onSurface, lineWidth: selectedColor == item.color ? 2.5 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(item.name)
                        .accessibilityLabel(item.name)
                        .accessibilityAddTraits(selectedColor == item.color ? .isSelected : [])
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .curioText(CurioFont.labelLarge)
                    .foregroundStyle(colors.onSurfaceVariant)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 8), count: 7), alignment: .leading, spacing: 8) {
                    ForEach(MacDeskLibrary.spaceIcons, id: \.self) { key in
                        Button {
                            selectedIcon = key
                        } label: {
                            Image(systemName: spaceIcon(key))
                                .font(.system(size: 15))
                                .frame(width: 30, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(selectedIcon == key ? colors.primaryContainer : Color.clear)
                                )
                                .foregroundStyle(selectedIcon == key ? colors.primary : colors.onSurfaceVariant)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(key.capitalized)
                        .accessibilityLabel(key.capitalized)
                        .accessibilityAddTraits(selectedIcon == key ? .isSelected : [])
                    }
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(editor.existing == nil ? "Create Space" : "Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(problem != nil)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 400)
    }

    private func save() {
        guard problem == nil, let clean = MacDeskLibrary.normalizedSpaceName(name) else { return }
        onSave(clean, selectedColor, selectedIcon)
        dismiss()
    }
}

struct DeskNewBookmarkSheet: View {
    let onSave: (String) -> Void

    @State private var text = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.curioColors) private var colors

    private var ready: Bool { MacDeskLibrary.normalizedNewBookmark(text) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Bookmark")
                .curioText(CurioFont.headlineSmall)
                .foregroundStyle(colors.onSurface)
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 140)
                .background(colors.surfaceVariant, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("Bookmark text or link")
            Text(text.count > MacDeskLibrary.maxNewBookmarkLength
                 ? "That is longer than \(MacDeskLibrary.maxNewBookmarkLength) characters."
                 : "Paste a link or write a note. It stays on this Mac and is not posted to X.")
                .font(.caption)
                .foregroundStyle(text.count > MacDeskLibrary.maxNewBookmarkLength ? colors.error : colors.onSurfaceVariant)
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    guard ready else { return }
                    onSave(text)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!ready)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            // Offer a copied web link, the most common reason to open this sheet.
            if text.isEmpty, let copied = NSPasteboard.general.string(forType: .string),
               MacDeskLibrary.safeWebURL(copied) != nil {
                text = copied.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}
