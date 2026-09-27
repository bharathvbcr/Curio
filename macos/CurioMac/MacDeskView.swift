import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Three-column research desk. This Mac keeps its own library, filled by signing in to X.
/// Notes and stars made on the phone stay on the phone.
struct MacDeskView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.curioColors) private var colors
    @AppStorage(MacAgentPreferences.accessKey) private var agentAccess = false
    @AppStorage(MacAgentPreferences.writesKey) private var agentWrites = false
    @AppStorage(MacAgentPreferences.liveKey) private var liveResearch = false
    @AppStorage(MacAgentPreferences.tokenKey) private var agentToken = ""
    @AppStorage("mac_desk_sort") private var sortRaw = DeskSort.newest.rawValue

    @State private var bookmarks: [Bookmark] = []
    @State private var spaces: [Space] = []
    @State private var selection: Set<String> = []
    @State private var scope: DeskScope = .library
    @State private var query = ""
    @State private var researchQuestion = ""
    @State private var researchResult: DeskResearchPresentation?
    @State private var notesDraft = ""
    @State private var statusNote: String?
    @State private var statusIsError = false
    @State private var isSyncing = false
    @State private var isResearching = false
    @State private var epoch = 0
    @State private var authModel: AuthViewModel?
    @State private var spaceEditor: DeskSpaceEditor?
    @State private var showingNewBookmark = false
    @State private var pendingDeletion: [Bookmark] = []
    @State private var spaceToDelete: Space?

    private var sort: DeskSort { DeskSort(rawValue: sortRaw) ?? .newest }

    private var signedInId: String {
        if case let .signedIn(userId, _, _) = authModel?.authState { return userId }
        return ""
    }

    private var accountLabel: String {
        guard let authModel else { return "Account" }
        if case let .signedIn(_, username, name) = authModel.authState {
            if let handle = MacDeskLibrary.nonempty(username) {
                return handle.hasPrefix("@") ? handle : "@\(handle)"
            }
            if let name = MacDeskLibrary.nonempty(name) { return name }
        }
        return "Account"
    }

    private var orderedSpaces: [Space] { MacDeskLibrary.orderedSpaces(spaces) }

    private var visible: [Bookmark] {
        MacDeskLibrary.visible(bookmarks, scope: scope, query: query, sort: sort)
    }

    /// Selected bookmarks in list order.
    private var selectedBookmarks: [Bookmark] {
        guard !selection.isEmpty else { return [] }
        return MacDeskLibrary.sorted(bookmarks.filter { selection.contains($0.id) }, by: sort)
    }

    /// The one bookmark in the reader, when exactly one is selected.
    private var selected: Bookmark? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return bookmarks.first { $0.id == id }
    }

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var subtitle: String {
        if isSyncing { return "Syncing from X…" }
        if isResearching { return "Researching…" }
        if let statusNote { return statusNote }
        if selection.count > 1 { return "\(selection.count) selected" }
        let total = MacDeskLibrary.count(bookmarks, scope: scope)
        if hasQuery { return "\(visible.count) of \(total)" }
        return MacDeskLibrary.counted(total, "bookmark")
    }

    var body: some View {
        Group {
            if let authModel {
                if signedInId.isEmpty {
                    login(authModel)
                } else {
                    desk
                }
            } else {
                launching
            }
        }
        .task {
            if authModel == nil { authModel = environment.makeAuthViewModel() }
            startAgentListener()
        }
        .task(id: signedInId) {
            guard !signedInId.isEmpty else { return }
            await reload()
            for await newBookmarks in environment.bookmarkRepository.getBookmarksFlow(userId: signedInId).values {
                bookmarks = newBookmarks
            }
        }
        .task(id: signedInId) {
            guard !signedInId.isEmpty else { return }
            for await newSpaces in environment.bookmarkRepository.getSpacesFlow(userId: signedInId).values {
                spaces = newSpaces
            }
        }
        .task(id: statusNote) {
            // Confirmations fade; errors stay until dismissed.
            guard let note = statusNote, !statusIsError else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if statusNote == note && !statusIsError { statusNote = nil }
        }
        .sheet(item: $spaceEditor) { editor in
            DeskSpaceSheet(editor: editor, spaces: spaces) { name, color, icon in
                Task { await saveSpace(editor, name: name, color: color, icon: icon) }
            }
            .curioTheme()
        }
        .sheet(isPresented: $showingNewBookmark) {
            DeskNewBookmarkSheet { text in
                Task { await addBookmark(text) }
            }
            .curioTheme()
        }
        .confirmationDialog(
            pendingDeletion.count > 1 ? "Delete \(pendingDeletion.count) Bookmarks?" : "Delete Bookmark?",
            isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } }),
            titleVisibility: .visible
        ) {
            Button(pendingDeletion.count > 1 ? "Delete \(pendingDeletion.count) Bookmarks" : "Delete Bookmark", role: .destructive) {
                let doomed = pendingDeletion
                pendingDeletion = []
                Task { await deleteBookmarks(doomed) }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = [] }
        } message: {
            if pendingDeletion.count == 1, let only = pendingDeletion.first {
                Text("“\(MacDeskLibrary.title(only))” will be removed from this Mac. This cannot be undone.")
            } else {
                Text("They will be removed from this Mac. This cannot be undone.")
            }
        }
        .confirmationDialog(
            "Delete Space?",
            isPresented: Binding(get: { spaceToDelete != nil }, set: { if !$0 { spaceToDelete = nil } }),
            titleVisibility: .visible,
            presenting: spaceToDelete
        ) { space in
            Button("Delete Space", role: .destructive) {
                Task { await deleteSpace(space) }
            }
            Button("Cancel", role: .cancel) { spaceToDelete = nil }
        } message: { space in
            Text("“\(space.name)” will be deleted. Its bookmarks become unfiled.")
        }
    }

    private var launching: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Opening Curio")
                .curioText(CurioFont.labelLarge)
                .foregroundStyle(colors.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Curio")
    }

    private func login(_ authModel: AuthViewModel) -> some View {
        LoginView(
            state: authModel.authState,
            tier: .full,
            onLoginClick: { authModel.onLoginClick() },
            errorMessage: authModel.loginError,
            onDismissError: { authModel.clearLoginError() }
        )
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Curio")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("Agents", systemImage: "cpu")
                }
                .help("Agent access for this Mac")
            }
        }
    }

    private var desk: some View {
        NavigationSplitView {
            sidebar
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $query, placement: .toolbar, prompt: "Search bookmarks")
        .toolbar { deskToolbar }
        .focusedSceneValue(\.macDeskCommands, commandBridge)
        .onChange(of: agentAccess) { _, enabled in
            if enabled { agentToken = MacAgentPreferences.enableAccess() }
            startAgentListener()
        }
        .onChange(of: visible.map(\.id)) { _, ids in
            let kept = MacDeskLibrary.reconciledSelection(selection, visibleIds: ids)
            if kept != selection { selection = kept }
        }
        .onChange(of: selection) { old, new in
            flushNote(leaving: old, for: new)
            notesDraft = singleBookmark(in: new)?.notes ?? ""
        }
        .onChange(of: spaces.map(\.id)) { _, ids in
            if case let .space(id) = scope, !ids.contains(id) { scope = .library }
        }
        .task(id: noteAutosaveKey) {
            // Autosave a paused note so closing the window never loses it.
            guard let bookmark = selected,
                  MacDeskLibrary.notesChanged(draft: notesDraft, saved: bookmark.notes) else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await persistNote(notesDraft, for: bookmark.id)
        }
    }

    private var noteAutosaveKey: String {
        "\(selected?.id ?? "")|\(notesDraft)"
    }

    private var commandBridge: MacDeskCommands {
        MacDeskCommands(
            selectionCount: selection.count,
            canOpen: selectedBookmarks.contains { MacDeskLibrary.link($0) != nil },
            canExport: !bookmarks.isEmpty,
            isSyncing: isSyncing,
            sort: sort,
            sync: { Task { await sync(older: false) } },
            loadOlder: { Task { await sync(older: true) } },
            newBookmark: { showingNewBookmark = true },
            openLink: { openSelection() },
            toggleFavorite: { Task { await setFavorite(selectedBookmarks, next: MacDeskLibrary.bulkFavoriteTarget(selectedBookmarks)) } },
            toggleLater: { Task { await setLater(selectedBookmarks, next: MacDeskLibrary.bulkLaterTarget(selectedBookmarks)) } },
            deleteBookmark: { pendingDeletion = selectedBookmarks },
            copyBibtex: { copyBibtex(selectedBookmarks) },
            copyLinks: { copyLinks(selectedBookmarks) },
            export: { format in export(format) },
            setSort: { sortRaw = $0.rawValue },
            newSpace: { spaceEditor = .new },
            research: { Task { await research() } },
            signOut: { signOut() }
        )
    }

    @ToolbarContentBuilder
    private var deskToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingNewBookmark = true
            } label: {
                Label("New Bookmark", systemImage: "plus")
            }
            .help("Save a link or a note (⌘N)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await sync(older: false) }
            } label: {
                if isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(isSyncing)
            .help("Pull new bookmarks from X (⌘R)")
            .accessibilityIdentifier("mac_sync_button")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Sort By", selection: $sortRaw) {
                    ForEach(DeskSort.allCases) { sort in
                        Text(sort.label).tag(sort.rawValue)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Menu("Export \(selection.count > 1 ? "Selection" : MacDeskLibrary.scopeTitle(scope, spaces: spaces))") {
                    ForEach(DeskExportFormat.allCases) { format in
                        Button(format.label + "…") { export(format) }
                    }
                }
                .disabled(bookmarks.isEmpty)
                Button("Load Older from X") { Task { await sync(older: true) } }
                    .disabled(isSyncing)
            } label: {
                Label("View", systemImage: "line.3.horizontal.decrease.circle")
            }
            .help("Sort, export, and load more")
        }
        ToolbarItem(placement: .primaryAction) {
            SettingsLink {
                Label("Agents", systemImage: "cpu")
            }
            .help("Agent access for this Mac")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Text(accountLabel)
                Divider()
                Button("Sign Out", role: .destructive) { signOut() }
                    .accessibilityIdentifier("mac_sign_out_button")
            } label: {
                Label(accountLabel, systemImage: "person.crop.circle")
            }
            .help(accountLabel)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: Binding<DeskScope?>(get: { scope }, set: { if let next = $0 { scope = next } })) {
            Section("Library") {
                ForEach(DeskScope.sidebar, id: \.self) { item in
                    Label(MacDeskLibrary.scopeTitle(item, spaces: spaces), systemImage: MacDeskLibrary.scopeSymbol(item, spaces: spaces))
                        .badge(MacDeskLibrary.count(bookmarks, scope: item))
                        .tag(item)
                        .dropDestination(for: String.self) { ids, _ in
                            dropped(ids, on: item)
                        }
                }
            }
            Section {
                if orderedSpaces.isEmpty {
                    Text("No spaces yet. Click + or drag bookmarks here after creating one.")
                        .font(.caption)
                        .foregroundStyle(colors.onSurfaceVariant)
                        .selectionDisabled()
                }
                ForEach(orderedSpaces) { space in
                    spaceRow(space)
                        .tag(DeskScope.space(space.id))
                        .contextMenu { spaceMenu(space) }
                        .dropDestination(for: String.self) { ids, _ in
                            dropped(ids, on: .space(space.id))
                        }
                }
            } header: {
                HStack {
                    Text("Spaces")
                    Spacer()
                    Button {
                        spaceEditor = .new
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.plain)
                    .help("Create a new Space")
                    .accessibilityLabel("Create Space")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Curio")
        .navigationSplitViewColumnWidth(min: 200, ideal: 228, max: 280)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(accountLabel)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(colors.onSurface)
                    .lineLimit(1)
                Text(agentAccess ? (agentWrites ? "Agents can edit" : "Agents can read") : "Agents off")
                    .font(.caption)
                    .foregroundStyle(colors.onSurfaceVariant)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func spaceRow(_ space: Space) -> some View {
        Label {
            HStack(spacing: 6) {
                Text(space.name)
                    .lineLimit(1)
                if space.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(colors.onSurfaceVariant)
                        .accessibilityLabel("Pinned")
                }
                if space.isSmart {
                    Text("Smart")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(colors.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(colors.secondary.opacity(0.16), in: Capsule())
                }
            }
        } icon: {
            Image(systemName: spaceIcon(space.icon))
                .foregroundStyle(spaceColor(space))
        }
        .badge(MacDeskLibrary.count(bookmarks, scope: .space(space.id)))
    }

    @ViewBuilder
    private func spaceMenu(_ space: Space) -> some View {
        Button("Edit Space…") { spaceEditor = .edit(space) }
        Button(space.isPinned ? "Unpin Space" : "Pin Space") {
            Task { await togglePinSpace(space) }
        }
        Divider()
        Menu("Export Space") {
            ForEach(DeskExportFormat.allCases) { format in
                Button(format.label + "…") {
                    let members = MacDeskLibrary.visible(bookmarks, scope: .space(space.id), query: "", sort: sort)
                    export(members, format: format, title: space.name)
                }
            }
        }
        Divider()
        Button("Delete Space…", role: .destructive) {
            spaceToDelete = space
        }
    }

    // MARK: - List

    private var contentColumn: some View {
        let shown = visible
        return Group {
            if shown.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: emptySymbol)
                } description: {
                    Text(emptyMessage)
                } actions: {
                    if bookmarks.isEmpty {
                        Button("Sync from X") { Task { await sync(older: false) } }
                            .disabled(isSyncing)
                        Button("New Bookmark…") { showingNewBookmark = true }
                    } else if hasQuery {
                        Button("Clear Search") { query = "" }
                    }
                }
            } else {
                List(shown, selection: $selection) { bookmark in
                    DeskBookmarkRow(
                        bookmark: bookmark,
                        spaceName: spaceName(bookmark.spaceId),
                        tint: spaceTint(bookmark)
                    )
                    .tag(bookmark.id)
                    .draggable(bookmark.id)
                    .accessibilityIdentifier("bookmark_row_\(bookmark.id)")
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .contextMenu(forSelectionType: String.self) { ids in
                    rowMenu(ids)
                } primaryAction: { ids in
                    for bookmark in bookmarks where ids.contains(bookmark.id) { open(bookmark) }
                }
                .copyable(selectedBookmarks.compactMap(MacDeskLibrary.link))
                .onDeleteCommand { pendingDeletion = selectedBookmarks }
            }
        }
        .navigationTitle(MacDeskLibrary.scopeTitle(scope, spaces: spaces))
        .navigationSubtitle(subtitle)
        .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 520)
    }

    private var emptyTitle: String {
        if bookmarks.isEmpty { return "No bookmarks yet" }
        if hasQuery { return "No matches" }
        return "Nothing here"
    }

    private var emptySymbol: String {
        if bookmarks.isEmpty { return "books.vertical" }
        if hasQuery { return "magnifyingglass" }
        return MacDeskLibrary.scopeSymbol(scope, spaces: spaces)
    }

    private var emptyMessage: String {
        let phrase = MacDeskLibrary.scopePhrase(scope, spaces: spaces)
        if bookmarks.isEmpty {
            return "Sync from X to fill this Mac, or save a link yourself. Notes and stars on your iPhone stay on the phone."
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return "Nothing in \(phrase) matches “\(trimmed)”."
        }
        if case .space = scope {
            return "No bookmarks in \(phrase). Drag bookmarks onto it in the sidebar to file them."
        }
        return "No bookmarks in \(phrase)."
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<String>) -> some View {
        let targets = MacDeskLibrary.sorted(bookmarks.filter { ids.contains($0.id) }, by: sort)
        if !targets.isEmpty {
            let many = targets.count > 1
            Button(many ? "Open \(targets.count) Links" : "Open") { targets.forEach(open) }
                .disabled(!targets.contains { MacDeskLibrary.link($0) != nil })
            Button(many ? "Copy Links" : "Copy Link") { copyLinks(targets) }
            if !many, let only = targets.first {
                Button("Share…") { _ = CurioFormat.shareBookmark(MacDeskLibrary.shareText(only)) }
            }
            Divider()
            let star = MacDeskLibrary.bulkFavoriteTarget(targets)
            Button(star ? "Star" : "Unstar") { Task { await setFavorite(targets, next: star) } }
            let later = MacDeskLibrary.bulkLaterTarget(targets)
            Button(later ? "Read Later" : "Remove from Read Later") { Task { await setLater(targets, next: later) } }
            Divider()
            Menu("File into") {
                Button("Unfiled") { Task { await file(targets, into: nil) } }
                if !orderedSpaces.isEmpty { Divider() }
                ForEach(orderedSpaces) { space in
                    Button(space.name) { Task { await file(targets, into: space.id) } }
                }
                Divider()
                Button("New Space…") { spaceEditor = .newFiling(targets.map(\.id)) }
            }
            Divider()
            Button("Copy BibTeX Citation\(many ? "s" : "")") { copyBibtex(targets) }
                .disabled(!targets.contains { MacDeskLibrary.bibtexCitation($0) != nil })
            Menu("Export") {
                ForEach(DeskExportFormat.allCases) { format in
                    Button(format.label + "…") { export(targets, format: format, title: many ? "Selection" : MacDeskLibrary.title(targets[0])) }
                }
            }
            Divider()
            Button(many ? "Delete \(targets.count) Bookmarks…" : "Delete Bookmark…", role: .destructive) {
                pendingDeletion = targets
            }
        }
    }

    // MARK: - Detail

    private var detailColumn: some View {
        VStack(spacing: 0) {
            if statusIsError, let statusNote {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(statusNote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(3)
                        .textSelection(.enabled)
                    Button("Dismiss") {
                        self.statusNote = nil
                        statusIsError = false
                    }
                    .buttonStyle(.borderless)
                }
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(colors.errorContainer)
                .foregroundStyle(colors.onErrorContainer)
            }
            if selection.count > 1 {
                DeskBulkPanel(
                    bookmarks: selectedBookmarks,
                    spaces: orderedSpaces,
                    onFavorite: { next in Task { await setFavorite(selectedBookmarks, next: next) } },
                    onLater: { next in Task { await setLater(selectedBookmarks, next: next) } },
                    onFile: { spaceId in Task { await file(selectedBookmarks, into: spaceId) } },
                    onCopyLinks: { copyLinks(selectedBookmarks) },
                    onCopyBibtex: { copyBibtex(selectedBookmarks) },
                    onExport: { format in export(format) },
                    onDelete: { pendingDeletion = selectedBookmarks },
                    onClear: { selection = [] }
                )
            } else if let bookmark = selected {
                DeskReader(
                    bookmark: bookmark,
                    spaceName: spaceName(bookmark.spaceId),
                    spaces: orderedSpaces,
                    notesDraft: $notesDraft,
                    question: $researchQuestion,
                    research: researchResult,
                    isResearching: isResearching,
                    liveResearch: liveResearch,
                    notesDirty: MacDeskLibrary.notesChanged(draft: notesDraft, saved: bookmark.notes),
                    onOpen: { open(bookmark) },
                    onCopy: { copy(bookmark) },
                    onShare: { _ = CurioFormat.shareBookmark(MacDeskLibrary.shareText(bookmark)) },
                    onFavorite: { Task { await setFavorite([bookmark], next: !bookmark.isFavorite) } },
                    onLater: { Task { await setLater([bookmark], next: !bookmark.isSavedForLater) } },
                    onFile: { spaceId in Task { await file([bookmark], into: spaceId) } },
                    onSaveNotes: { Task { await persistNote(notesDraft, for: bookmark.id) } },
                    onResearch: { Task { await research() } },
                    onCopyBibtex: { copyBibtex([bookmark]) },
                    onDelete: { pendingDeletion = [bookmark] }
                )
            } else {
                DeskWelcome(
                    title: MacDeskLibrary.scopeTitle(scope, spaces: spaces),
                    message: welcomeMessage,
                    summary: MacDeskLibrary.librarySummary(bookmarks: bookmarks, spaces: spaces),
                    question: $researchQuestion,
                    research: researchResult,
                    isResearching: isResearching,
                    liveResearch: liveResearch,
                    onResearch: { Task { await research() } }
                )
            }
        }
        .background(colors.background)
    }

    private var welcomeMessage: String {
        if bookmarks.isEmpty {
            return "This Mac keeps its own library. Sync to pull bookmarks from your X account, or press ⌘N to save a link. Notes, stars, and embeddings on your iPhone do not come along."
        }
        return "Select a bookmark to read it, or several to star, file, or export them together. Research below stays on this Mac unless live web is turned on in Agent settings."
    }

    // MARK: - Helpers

    private func singleBookmark(in ids: Set<String>) -> Bookmark? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return bookmarks.first { $0.id == id }
    }

    private func spaceName(_ id: String?) -> String? {
        guard let id else { return nil }
        return spaces.first { $0.id == id }?.name
    }

    private func spaceColor(_ space: Space) -> Color {
        (space.color >> 24) & 0xFF == 0 ? colors.primary : Color(packedARGB: space.color)
    }

    private func spaceTint(_ bookmark: Bookmark) -> Color {
        guard let id = bookmark.spaceId, let space = spaces.first(where: { $0.id == id }) else {
            return colors.primary
        }
        return spaceColor(space)
    }

    private func startAgentListener() {
        if agentAccess { agentToken = MacAgentPreferences.enableAccess() }
        MacAgentHost.shared.start(environment: environment)
    }

    private func setStatus(_ note: String, error: Bool = false) {
        statusNote = note
        statusIsError = error
    }

    // MARK: - Loading

    @discardableResult
    private func reload(ticket: Int? = nil) async -> Bool {
        if let ticket, ticket != epoch { return false }
        guard let userId = await environment.tokenStore.getUserId() else {
            guard ticket == nil || ticket == epoch else { return false }
            bookmarks = []
            spaces = []
            setStatus("Sign in with X before syncing. This Mac does not see the phone's library.", error: true)
            return false
        }
        let loadedBookmarks = await environment.bookmarkRepository.searchBookmarks(userId: userId, query: "")
        let loadedSpaces = await environment.spaceStore.getSpaces(userId: userId)
        guard !Task.isCancelled else { return false }
        guard ticket == nil || ticket == epoch else { return false }
        bookmarks = loadedBookmarks
        spaces = loadedSpaces
        return true
    }

    private func sync(older: Bool) async {
        let ticket = epoch
        guard !isSyncing else { return }
        guard let userId = await environment.tokenStore.getUserId() else {
            setStatus("Sign in with X before syncing. This Mac does not see the phone's library.", error: true)
            return
        }
        let before = bookmarks.count
        isSyncing = true
        statusNote = nil
        statusIsError = false
        defer { if ticket == epoch { isSyncing = false } }
        do {
            try await environment.bookmarkRepository.syncBookmarks(userId: userId, fetchNextPage: older)
            guard ticket == epoch else { return }
            guard await reload(ticket: ticket) else { return }
            let added = max(0, bookmarks.count - before)
            if added > 0 {
                setStatus("Added \(MacDeskLibrary.counted(added, "bookmark")) from X.")
            } else {
                setStatus(older ? "No older bookmarks on X." : "Up to date with X.")
            }
        } catch {
            guard ticket == epoch else { return }
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            setStatus(message.isEmpty ? "Sync failed." : message, error: true)
        }
    }

    private func research() async {
        let question = researchQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            setStatus("Ask a question first.", error: true)
            return
        }
        guard question.count <= AgentLimits.maxQuestionCharacters else {
            setStatus("That question is too long. Keep it under \(AgentLimits.maxQuestionCharacters) characters.", error: true)
            return
        }
        let ticket = epoch
        guard !isResearching else { return }
        isResearching = true
        researchResult = nil
        statusNote = nil
        statusIsError = false
        defer { if ticket == epoch { isResearching = false } }
        let api = environment.makeLibraryAgentAPI()
        let result = await api.research(
            question: question,
            privateMode: !liveResearch,
            sources: liveResearch ? ["web"] : [],
            limit: 8
        )
        guard ticket == epoch else { return }
        let presented = DeskResearchPresentation.from(ok: result.ok, code: result.code, payload: result.payload)
        researchResult = presented
        if let failure = presented.failure {
            setStatus(failure, error: true)
        }
    }

    // MARK: - Reading and copying

    private func openSelection() {
        selectedBookmarks.forEach(open)
    }

    private func open(_ bookmark: Bookmark) {
        switch CurioFormat.openUrl(MacDeskLibrary.link(bookmark)) {
        case .opened:
            break
        case .noLink:
            setStatus("No link on “\(MacDeskLibrary.title(bookmark))”.", error: true)
        case .failed:
            setStatus("Couldn’t open the link.", error: true)
        }
    }

    private func copy(_ bookmark: Bookmark) {
        if let link = MacDeskLibrary.link(bookmark) {
            let ok = CurioFormat.copyToClipboard(link, label: "Curio")
            setStatus(ok ? "Copied the link." : "Couldn’t copy the link.", error: !ok)
        } else {
            let text = bookmark.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                setStatus("Nothing to copy.", error: true)
                return
            }
            let ok = CurioFormat.copyToClipboard(text, label: "Curio")
            setStatus(ok ? "Copied the text." : "Couldn’t copy the text.", error: !ok)
        }
    }

    private func copyLinks(_ targets: [Bookmark]) {
        if targets.count == 1, let only = targets.first {
            copy(only)
            return
        }
        let links = targets.compactMap(MacDeskLibrary.link)
        guard !links.isEmpty else {
            setStatus("None of these bookmarks has a link.", error: true)
            return
        }
        let ok = CurioFormat.copyToClipboard(links.joined(separator: "\n"), label: "Curio")
        setStatus(ok ? "Copied \(MacDeskLibrary.counted(links.count, "link"))." : "Couldn’t copy the links.", error: !ok)
    }

    private func copyBibtex(_ targets: [Bookmark]) {
        let citations = targets.compactMap(MacDeskLibrary.bibtexCitation)
        guard !citations.isEmpty else {
            setStatus(targets.count > 1 ? "None of these bookmarks can be cited." : "No citation available for this bookmark.", error: true)
            return
        }
        let ok = CurioFormat.copyToClipboard(citations.joined(separator: "\n\n"), label: "BibTeX")
        let noun = MacDeskLibrary.counted(citations.count, "citation")
        setStatus(ok ? "Copied \(noun)." : "Couldn’t copy BibTeX.", error: !ok)
    }

    // MARK: - Export

    /// The selection when there is one, else what the list shows.
    private func export(_ format: DeskExportFormat) {
        if selection.count > 0 {
            export(selectedBookmarks, format: format, title: selection.count == 1 ? MacDeskLibrary.title(selectedBookmarks[0]) : "Selection")
        } else {
            export(visible, format: format, title: MacDeskLibrary.scopeTitle(scope, spaces: spaces))
        }
    }

    private func export(_ targets: [Bookmark], format: DeskExportFormat, title: String) {
        let usable = MacDeskLibrary.exportableCount(targets, format: format)
        guard usable > 0 else {
            let reason = format == .ris || format == .cslJson
                ? "\(format.label) needs resolved papers, repos, or DOIs. Try BibTeX or Markdown."
                : "Nothing to export."
            setStatus(reason, error: true)
            return
        }
        let text = MacDeskLibrary.exportText(targets, format: format, spaces: spaces)
        let panel = NSSavePanel()
        panel.title = "Export \(format.label)"
        panel.nameFieldStringValue = MacDeskLibrary.exportFilename(scopeTitle: title, format: format)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let type = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            let skipped = targets.count - usable
            let note = skipped > 0
                ? "Exported \(MacDeskLibrary.counted(usable, "bookmark")); \(skipped) had nothing to cite."
                : "Exported \(MacDeskLibrary.counted(usable, "bookmark"))."
            setStatus(note)
        } catch {
            setStatus("Couldn’t write \(url.lastPathComponent): \(error.localizedDescription)", error: true)
        }
    }

    // MARK: - Changes

    private func setFavorite(_ targets: [Bookmark], next: Bool) async {
        guard !targets.isEmpty else { return }
        for bookmark in targets where bookmark.isFavorite != next {
            await environment.bookmarkRepository.setFavorite(id: bookmark.id, isFavorite: next)
        }
        await refresh()
        if targets.count > 1 {
            setStatus(next ? "Starred \(targets.count)." : "Unstarred \(targets.count).")
        }
    }

    private func setLater(_ targets: [Bookmark], next: Bool) async {
        guard !targets.isEmpty else { return }
        for bookmark in targets where bookmark.isSavedForLater != next {
            await environment.bookmarkRepository.setSavedForLater(id: bookmark.id, isSavedForLater: next)
        }
        await refresh()
        if targets.count > 1 {
            setStatus(next ? "Added \(targets.count) to Read Later." : "Removed \(targets.count) from Read Later.")
        }
    }

    private func file(_ targets: [Bookmark], into spaceId: String?) async {
        guard !targets.isEmpty else { return }
        if let spaceId, !spaces.contains(where: { $0.id == spaceId }) {
            setStatus("That space no longer exists.", error: true)
            return
        }
        await environment.bookmarkRepository.assignToSpace(ids: targets.map(\.id), spaceId: spaceId)
        await refresh()
        let destination = spaceName(spaceId) ?? "Unfiled"
        setStatus(targets.count > 1 ? "Filed \(targets.count) into \(destination)." : "Filed into \(destination).")
    }

    /// Drops from the list: onto a space files, onto Unfiled unfiles, onto Favorites stars, onto
    /// Read Later queues. Dragging one row of a multi-selection moves the whole selection.
    private func dropped(_ ids: [String], on target: DeskScope) -> Bool {
        let dragged = Set(ids)
        let moving = dragged.isSubset(of: selection) ? selection : dragged
        let targets = bookmarks.filter { moving.contains($0.id) }
        guard !targets.isEmpty else { return false }
        switch target {
        case .space(let id):
            Task { await file(targets, into: id) }
        case .unfiled:
            Task { await file(targets, into: nil) }
        case .favorites:
            Task { await setFavorite(targets, next: true) }
        case .later:
            Task { await setLater(targets, next: true) }
        case .library, .annotated:
            return false
        }
        return true
    }

    private func refresh() async {
        let ticket = epoch
        await reload(ticket: ticket)
    }

    /// When the reader moves off a bookmark with an unsaved note, save it rather than drop it.
    private func flushNote(leaving old: Set<String>, for new: Set<String>) {
        guard old.count == 1, let previousId = old.first, new != old,
              let previous = bookmarks.first(where: { $0.id == previousId }),
              MacDeskLibrary.notesChanged(draft: notesDraft, saved: previous.notes) else { return }
        let pending = notesDraft
        Task { await persistNote(pending, for: previousId) }
    }

    private func persistNote(_ draft: String, for id: String) async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= AgentLimits.maxNoteCharacters else {
            setStatus("That note is too long to save. Keep it under \(AgentLimits.maxNoteCharacters) characters.", error: true)
            return
        }
        await environment.bookmarkRepository.updateNotes(id: id, notes: trimmed.isEmpty ? nil : trimmed)
        await refresh()
        // Only tidy the draft when the same bookmark is still open and nothing new was typed.
        if selected?.id == id, notesDraft.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed {
            notesDraft = trimmed
        }
    }

    private func addBookmark(_ raw: String) async {
        guard let text = MacDeskLibrary.normalizedNewBookmark(raw) else {
            setStatus("Write something or paste a link to save.", error: true)
            return
        }
        guard !signedInId.isEmpty else { return }
        do {
            let saved = try await environment.bookmarkRepository.addBookmark(userId: signedInId, text: text)
            await refresh()
            if case .space(let id) = scope {
                await environment.bookmarkRepository.assignToSpace(ids: [saved.id], spaceId: id)
                await refresh()
            } else if !MacDeskLibrary.matches(saved, scope: scope) {
                scope = .library
            }
            query = ""
            selection = [saved.id]
            setStatus("Saved.")
        } catch {
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            setStatus(message.isEmpty ? "Couldn’t save the bookmark." : message, error: true)
        }
    }

    private func deleteBookmarks(_ targets: [Bookmark]) async {
        guard !targets.isEmpty else { return }
        let ids = targets.map(\.id)
        selection.subtract(ids)
        await environment.bookmarkRepository.deleteBookmarks(ids: ids)
        await refresh()
        setStatus(targets.count > 1 ? "Deleted \(targets.count) bookmarks." : "Deleted bookmark.")
    }

    private func saveSpace(_ editor: DeskSpaceEditor, name: String, color: Int64, icon: String) async {
        guard !signedInId.isEmpty else { return }
        if let problem = MacDeskLibrary.spaceNameProblem(name, existing: spaces, excluding: editor.existing?.id) {
            setStatus(problem, error: true)
            return
        }
        guard let clean = MacDeskLibrary.normalizedSpaceName(name) else { return }
        switch editor {
        case .edit(let space):
            // Keep what this sheet does not edit: description, rules, and pin.
            await environment.bookmarkRepository.updateSpace(
                id: space.id,
                name: clean,
                color: color,
                icon: icon,
                description: space.description,
                rules: space.rules,
                isPinned: space.isPinned
            )
            await refresh()
            setStatus("Updated “\(clean)”.")
        case .new, .newFiling:
            let created = await environment.bookmarkRepository.createSpace(userId: signedInId, name: clean, color: color, icon: icon)
            if case .newFiling(let ids) = editor, !ids.isEmpty {
                await environment.bookmarkRepository.assignToSpace(ids: ids, spaceId: created.id)
            }
            await refresh()
            setStatus("Created “\(created.name)”.")
            scope = .space(created.id)
        }
    }

    private func togglePinSpace(_ space: Space) async {
        await environment.bookmarkRepository.setSpacePinned(id: space.id, pinned: !space.isPinned)
        await refresh()
    }

    private func deleteSpace(_ space: Space) async {
        if case .space(space.id) = scope {
            scope = .library
        }
        await environment.bookmarkRepository.deleteSpace(id: space.id)
        await refresh()
        setStatus("Deleted “\(space.name)”.")
    }

    private func signOut() {
        if let bookmark = selected, MacDeskLibrary.notesChanged(draft: notesDraft, saved: bookmark.notes) {
            let pending = notesDraft
            let id = bookmark.id
            let repository = environment.bookmarkRepository
            let trimmed = pending.trimmingCharacters(in: .whitespacesAndNewlines)
            Task { await repository.updateNotes(id: id, notes: trimmed.isEmpty ? nil : trimmed) }
        }
        epoch += 1
        isSyncing = false
        isResearching = false
        authModel?.onLogout()
        bookmarks = []
        spaces = []
        selection = []
        scope = .library
        query = ""
        researchQuestion = ""
        researchResult = nil
        notesDraft = ""
        statusNote = nil
        statusIsError = false
        pendingDeletion = []
        spaceEditor = nil
    }
}

/// Which space sheet is showing. `newFiling` files the given bookmarks into the new space.
enum DeskSpaceEditor: Identifiable {
    case new
    case newFiling([String])
    case edit(Space)

    var id: String {
        switch self {
        case .new: return "new"
        case .newFiling(let ids): return "new-" + ids.joined(separator: ",")
        case .edit(let space): return "edit-" + space.id
        }
    }

    var existing: Space? {
        if case .edit(let space) = self { return space }
        return nil
    }
}
