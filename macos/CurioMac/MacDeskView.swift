import SwiftUI

/// Three-column research desk. This Mac keeps its own library, filled by signing in to X.
/// Notes and stars made on the phone stay on the phone.
struct MacDeskView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.curioColors) private var colors
    @AppStorage(MacAgentPreferences.accessKey) private var agentAccess = false
    @AppStorage(MacAgentPreferences.writesKey) private var agentWrites = false
    @AppStorage(MacAgentPreferences.liveKey) private var liveResearch = false
    @AppStorage(MacAgentPreferences.tokenKey) private var agentToken = ""

    @State private var bookmarks: [Bookmark] = []
    @State private var spaces: [Space] = []
    @State private var selection: String?
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
    @State private var listener: AgentSocketListener?
    @State private var authModel: AuthViewModel?
    @State private var showingNewSpaceSheet = false
    @State private var bookmarkToDelete: Bookmark?
    @State private var spaceToDelete: Space?

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
        MacDeskLibrary.visible(bookmarks, scope: scope, query: query)
    }

    private var selected: Bookmark? { bookmarks.first { $0.id == selection } }

    private var subtitle: String {
        if isSyncing { return "Syncing from X…" }
        if isResearching { return "Researching…" }
        if let statusNote { return statusNote }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(visible.count) of \(MacDeskLibrary.count(bookmarks, scope: scope))"
        }
        let count = MacDeskLibrary.count(bookmarks, scope: scope)
        return count == 1 ? "1 bookmark" : "\(count) bookmarks"
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
        .sheet(isPresented: $showingNewSpaceSheet) {
            NewSpaceSheet(isPresented: $showingNewSpaceSheet) { name, color, icon in
                Task { await createSpace(name: name, color: color, icon: icon) }
            }
            .curioTheme()
        }
        .confirmationDialog(
            "Delete Bookmark?",
            isPresented: Binding(get: { bookmarkToDelete != nil }, set: { if !$0 { bookmarkToDelete = nil } }),
            titleVisibility: .visible,
            presenting: bookmarkToDelete
        ) { bookmark in
            Button("Delete Bookmark", role: .destructive) {
                Task { await deleteBookmark(bookmark) }
            }
            Button("Cancel", role: .cancel) { bookmarkToDelete = nil }
        } message: { bookmark in
            Text("Are you sure you want to delete “\(MacDeskLibrary.title(bookmark))”? This cannot be undone.")
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
            Text("Are you sure you want to delete “\(space.name)”? Bookmarks in this space will become unfiled.")
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
        .focusedValue(\.macDeskCommands, commandBridge)
        .onChange(of: agentAccess) { _, enabled in
            if enabled { agentToken = MacAgentPreferences.enableAccess() }
            startAgentListener()
        }
        .onChange(of: visible.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil }
        }
        .onChange(of: selection) { _, id in
            notesDraft = bookmarks.first { $0.id == id }?.notes ?? ""
        }
        .onChange(of: spaces.map(\.id)) { _, ids in
            if case let .space(id) = scope, !ids.contains(id) { scope = .library }
        }
    }

    private var commandBridge: MacDeskCommands {
        MacDeskCommands(
            canOpen: selected.flatMap(MacDeskLibrary.link) != nil,
            canCurate: selected != nil,
            canDelete: selected != nil,
            canExport: selected != nil && MacDeskLibrary.link(selected!) != nil,
            sync: { Task { await sync() } },
            openLink: { openSelection() },
            toggleFavorite: { Task { await toggleFavorite() } },
            toggleLater: { Task { await toggleLater() } },
            deleteBookmark: {
                if let selected { bookmarkToDelete = selected }
            },
            copyBibtex: {
                if let selected { copyBibtex(selected) }
            },
            newSpace: { showingNewSpaceSheet = true },
            research: { Task { await research() } },
            signOut: { signOut() }
        )
    }

    @ToolbarContentBuilder
    private var deskToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await sync() }
            } label: {
                if isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(isSyncing)
            .help("Pull bookmarks from X")
            .accessibilityIdentifier("mac_sync_button")
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

    private var sidebar: some View {
        List(selection: $scope) {
            Section("Library") {
                ForEach(DeskScope.sidebar, id: \.self) { item in
                    Label(MacDeskLibrary.scopeTitle(item, spaces: spaces), systemImage: MacDeskLibrary.scopeSymbol(item, spaces: spaces))
                        .badge(MacDeskLibrary.count(bookmarks, scope: item))
                        .tag(item)
                }
            }
            Section {
                if orderedSpaces.isEmpty {
                    Text("No spaces yet. Click + to create one.")
                        .font(.caption)
                        .foregroundStyle(colors.onSurfaceVariant)
                        .selectionDisabled()
                }
                ForEach(orderedSpaces) { space in
                    spaceRow(space)
                        .tag(DeskScope.space(space.id))
                        .contextMenu { spaceMenu(space) }
                }
            } header: {
                HStack {
                    Text("Spaces")
                    Spacer()
                    Button {
                        showingNewSpaceSheet = true
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
                .foregroundStyle(Color(packedARGB: space.color))
        }
        .badge(MacDeskLibrary.count(bookmarks, scope: .space(space.id)))
    }

    private var contentColumn: some View {
        Group {
            if visible.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: emptySymbol)
                } description: {
                    Text(emptyMessage)
                } actions: {
                    if bookmarks.isEmpty {
                        Button("Sync from X") { Task { await sync() } }
                            .disabled(isSyncing)
                    } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Clear Search") { query = "" }
                    }
                }
            } else {
                List(visible, selection: $selection) { bookmark in
                    DeskBookmarkRow(
                        bookmark: bookmark,
                        spaceName: spaceName(bookmark.spaceId),
                        tint: spaceTint(bookmark)
                    )
                        .tag(bookmark.id)
                        .contextMenu { rowMenu(bookmark) }
                        .accessibilityIdentifier("bookmark_row_\(bookmark.id)")
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .navigationTitle(MacDeskLibrary.scopeTitle(scope, spaces: spaces))
        .navigationSubtitle(subtitle)
        .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 480)
    }

    private var emptyTitle: String {
        if bookmarks.isEmpty { return "No bookmarks yet" }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "No matches" }
        return "Nothing here"
    }

    private var emptySymbol: String {
        if bookmarks.isEmpty { return "books.vertical" }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "magnifyingglass" }
        return MacDeskLibrary.scopeSymbol(scope, spaces: spaces)
    }

    private var emptyMessage: String {
        let phrase = MacDeskLibrary.scopePhrase(scope, spaces: spaces)
        if bookmarks.isEmpty {
            return "Sync from X to fill this Mac. Notes and stars on your iPhone stay on the phone."
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return "Nothing in \(phrase) matches “\(trimmed)”."
        }
        return "No bookmarks in \(phrase)."
    }

    private var detailColumn: some View {
        VStack(spacing: 0) {
            if statusIsError, let statusNote {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(statusNote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(3)
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
            if let bookmark = selected {
                DeskReader(
                    bookmark: bookmark,
                    spaceName: spaceName(bookmark.spaceId),
                    spaces: orderedSpaces,
                    notesDraft: $notesDraft,
                    question: $researchQuestion,
                    research: researchResult,
                    isResearching: isResearching,
                    liveResearch: liveResearch,
                    notesDirty: notesDraft != (bookmark.notes ?? ""),
                    onOpen: { open(bookmark) },
                    onCopy: { copy(bookmark) },
                    onShare: { _ = CurioFormat.shareBookmark(MacDeskLibrary.shareText(bookmark)) },
                    onFavorite: { Task { await setFavorite(bookmark, next: !bookmark.isFavorite) } },
                    onLater: { Task { await setLater(bookmark, next: !bookmark.isSavedForLater) } },
                    onFile: { spaceId in Task { await file(bookmark, into: spaceId) } },
                    onSaveNotes: { Task { await saveNotes(bookmark) } },
                    onResearch: { Task { await research() } },
                    onCopyBibtex: { copyBibtex(bookmark) },
                    onDelete: { bookmarkToDelete = bookmark }
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
            return "This Mac keeps its own library. Sign in with X and sync to pull bookmarks from that account. Notes, stars, and embeddings on your iPhone do not come along."
        }
        return "Select a bookmark to read it. Research below stays on this Mac unless live web is turned on in Agent settings."
    }

    @ViewBuilder
    private func rowMenu(_ bookmark: Bookmark) -> some View {
        Button("Open") { open(bookmark) }
            .disabled(MacDeskLibrary.link(bookmark) == nil)
        Button("Copy Link") { copy(bookmark) }
        Button("Share") { _ = CurioFormat.shareBookmark(MacDeskLibrary.shareText(bookmark)) }
        Divider()
        Button(bookmark.isFavorite ? "Unstar" : "Star") {
            Task { await setFavorite(bookmark, next: !bookmark.isFavorite) }
        }
        Button(bookmark.isSavedForLater ? "Remove from Read Later" : "Read Later") {
            Task { await setLater(bookmark, next: !bookmark.isSavedForLater) }
        }
        Divider()
        Menu("File into") {
            Button("Unfiled") { Task { await file(bookmark, into: nil) } }
            ForEach(orderedSpaces) { space in
                Button(space.name) { Task { await file(bookmark, into: space.id) } }
            }
        }
        Divider()
        Button("Copy BibTeX Citation") { copyBibtex(bookmark) }
            .disabled(MacDeskLibrary.bibtexCitation(bookmark) == nil)
        Button("Delete Bookmark", role: .destructive) {
            bookmarkToDelete = bookmark
        }
    }

    @ViewBuilder
    private func spaceMenu(_ space: Space) -> some View {
        Button(space.isPinned ? "Unpin Space" : "Pin Space") {
            Task { await togglePinSpace(space) }
        }
        Divider()
        Button("Delete Space", role: .destructive) {
            spaceToDelete = space
        }
    }

    private func spaceName(_ id: String?) -> String? {
        guard let id else { return nil }
        return spaces.first { $0.id == id }?.name
    }

    private func spaceTint(_ bookmark: Bookmark) -> Color {
        guard let id = bookmark.spaceId,
              let space = spaces.first(where: { $0.id == id }),
              (space.color >> 24) & 0xFF != 0 else {
            return colors.primary
        }
        return Color(packedARGB: space.color)
    }

    private func startAgentListener() {
        if agentAccess { agentToken = MacAgentPreferences.enableAccess() }
        if listener == nil {
            listener = AgentSocketListener(api: environment.makeLibraryAgentAPI())
        }
        listener?.start()
    }

    @discardableResult
    private func reload(ticket: Int? = nil) async -> Bool {
        if let ticket, ticket != epoch { return false }
        guard let userId = await environment.tokenStore.getUserId() else {
            guard ticket == nil || ticket == epoch else { return false }
            bookmarks = []
            spaces = []
            statusNote = "Sign in with X before syncing. This Mac does not see the phone's library."
            statusIsError = true
            return false
        }
        let loadedBookmarks = await environment.bookmarkRepository.searchBookmarks(userId: userId, query: "")
        let loadedSpaces = await environment.spaceStore.getSpaces(userId: userId)
        guard !Task.isCancelled else { return false }
        guard ticket == nil || ticket == epoch else { return false }
        bookmarks = loadedBookmarks
        spaces = loadedSpaces
        statusNote = nil
        statusIsError = false
        return true
    }

    private func sync() async {
        let ticket = epoch
        guard !isSyncing else { return }
        guard let userId = await environment.tokenStore.getUserId() else {
            statusNote = "Sign in with X before syncing. This Mac does not see the phone's library."
            statusIsError = true
            return
        }
        isSyncing = true
        statusNote = nil
        statusIsError = false
        defer { if ticket == epoch { isSyncing = false } }
        do {
            try await environment.bookmarkRepository.syncBookmarks(userId: userId, fetchNextPage: false)
            guard ticket == epoch else { return }
            guard await reload(ticket: ticket) else { return }
            statusNote = "Synced from X."
            statusIsError = false
        } catch {
            guard ticket == epoch else { return }
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            statusNote = message.isEmpty ? "Sync failed." : message
            statusIsError = true
        }
    }

    private func research() async {
        let question = researchQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            statusNote = "Ask a question first."
            statusIsError = true
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
            statusNote = failure
            statusIsError = true
        }
    }

    private func openSelection() {
        guard let selected else { return }
        open(selected)
    }

    private func open(_ bookmark: Bookmark) {
        switch CurioFormat.openUrl(MacDeskLibrary.link(bookmark)) {
        case .opened:
            statusNote = nil
            statusIsError = false
        case .noLink:
            statusNote = "No link on this bookmark."
            statusIsError = true
        case .failed:
            statusNote = "Couldn’t open the link."
            statusIsError = true
        }
    }

    private func copy(_ bookmark: Bookmark) {
        if let link = MacDeskLibrary.link(bookmark) {
            statusIsError = !CurioFormat.copyToClipboard(link, label: "Curio")
            statusNote = statusIsError ? "Couldn’t copy the link." : "Copied the link."
        } else {
            let text = bookmark.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                statusNote = "Nothing to copy."
                statusIsError = true
                return
            }
            statusIsError = !CurioFormat.copyToClipboard(text, label: "Curio")
            statusNote = statusIsError ? "Couldn’t copy the text." : "Copied the text."
        }
    }

    private func toggleFavorite() async {
        guard let selected else { return }
        await setFavorite(selected, next: !selected.isFavorite)
    }

    private func toggleLater() async {
        guard let selected else { return }
        await setLater(selected, next: !selected.isSavedForLater)
    }

    private func setFavorite(_ bookmark: Bookmark, next: Bool) async {
        await mutate(bookmark.id) {
            await environment.bookmarkRepository.setFavorite(id: bookmark.id, isFavorite: next)
        }
    }

    private func setLater(_ bookmark: Bookmark, next: Bool) async {
        await mutate(bookmark.id) {
            await environment.bookmarkRepository.setSavedForLater(id: bookmark.id, isSavedForLater: next)
        }
    }

    private func file(_ bookmark: Bookmark, into spaceId: String?) async {
        await mutate(bookmark.id) {
            await environment.bookmarkRepository.assignToSpace(ids: [bookmark.id], spaceId: spaceId)
        }
    }

    private func saveNotes(_ bookmark: Bookmark) async {
        let trimmed = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = await mutate(bookmark.id) {
            await environment.bookmarkRepository.updateNotes(id: bookmark.id, notes: trimmed.isEmpty ? nil : trimmed)
        }
        if saved {
            notesDraft = bookmarks.first { $0.id == bookmark.id }?.notes ?? ""
        }
    }

    @discardableResult
    private func mutate(_ id: String, _ change: @MainActor () async -> Void) async -> Bool {
        let ticket = epoch
        await change()
        guard ticket == epoch else { return false }
        guard await reload(ticket: ticket) else { return false }
        selection = id
        return true
    }

    private func createSpace(name: String, color: Int64, icon: String) async {
        guard !signedInId.isEmpty else { return }
        let newSpace = await environment.bookmarkRepository.createSpace(
            userId: signedInId,
            name: name,
            color: color,
            icon: icon
        )
        statusNote = "Created Space “\(newSpace.name)”."
        statusIsError = false
        scope = .space(newSpace.id)
    }

    private func togglePinSpace(_ space: Space) async {
        await environment.bookmarkRepository.setSpacePinned(id: space.id, pinned: !space.isPinned)
    }

    private func deleteSpace(_ space: Space) async {
        if case .space(space.id) = scope {
            scope = .library
        }
        await environment.bookmarkRepository.deleteSpace(id: space.id)
        statusNote = "Deleted Space “\(space.name)”."
        statusIsError = false
    }

    private func deleteBookmark(_ bookmark: Bookmark) async {
        let id = bookmark.id
        if selection == id { selection = nil }
        await environment.bookmarkRepository.deleteBookmarks(ids: [id])
        statusNote = "Deleted bookmark."
        statusIsError = false
    }

    private func copyBibtex(_ bookmark: Bookmark) {
        guard let citation = MacDeskLibrary.bibtexCitation(bookmark) else {
            statusNote = "No citation available for this bookmark."
            statusIsError = true
            return
        }
        statusIsError = !CurioFormat.copyToClipboard(citation, label: "BibTeX")
        statusNote = statusIsError ? "Couldn’t copy BibTeX." : "Copied BibTeX citation."
    }

    private func signOut() {
        epoch += 1
        isSyncing = false
        isResearching = false
        authModel?.onLogout()
        bookmarks = []
        spaces = []
        selection = nil
        scope = .library
        query = ""
        researchQuestion = ""
        researchResult = nil
        notesDraft = ""
        statusNote = nil
        statusIsError = false
    }
}

// MARK: - Rows and the reading pane

private struct DeskBookmarkRow: View {
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

            if bookmark.isFavorite || bookmark.isSavedForLater {
                VStack(spacing: 4) {
                    if bookmark.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(colors.tertiary)
                            .accessibilityLabel("Starred")
                    }
                    if bookmark.isSavedForLater {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(colors.secondary)
                            .accessibilityLabel("Read later")
                    }
                }
                .font(.caption2)
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

private struct DeskReader: View {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(colors.primaryContainer.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if !bookmark.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MarkdownText(markdown: bookmark.text)
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

    private var imageURL: URL? {
        guard let raw = MacDeskLibrary.nonempty(bookmark.imageUrl) else { return nil }
        return URL(string: raw)
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
                .frame(height: 108)
                .background(colors.surfaceVariant, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack {
                Text("Notes stay on this Mac.")
                    .font(.caption)
                    .foregroundStyle(colors.onSurfaceVariant)
                Spacer()
                Button("Save Note", action: onSaveNotes)
                    .disabled(!notesDirty)
                    .controlSize(.small)
            }
        }
    }
}

private struct DeskWelcome: View {
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
            }
            .padding(32)
            .frame(maxWidth: 740, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct DeskResearchCard: View {
    @Binding var question: String
    let research: DeskResearchPresentation?
    let isResearching: Bool
    let liveResearch: Bool
    let onResearch: () -> Void

    @Environment(\.curioColors) private var colors

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
            HStack {
                Button(action: onResearch) {
                    if isResearching {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Research")
                    }
                }
                .disabled(isResearching || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                            }
                        }
                    }
                    if !research.citations.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(research.citations.enumerated()), id: \.offset) { _, url in
                                Button(url) { _ = CurioFormat.openUrl(url) }
                                    .buttonStyle(.link)
                                    .lineLimit(1)
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

// MARK: - New Space Sheet

private struct NewSpaceSheet: View {
    @Binding var isPresented: Bool
    let onCreate: (String, Int64, String) -> Void

    @State private var name: String = ""
    @State private var selectedColor: Int64 = MacDeskLibrary.spaceColorPalette.first?.color ?? 0xFF1E88E5
    @State private var selectedIcon: String = MacDeskLibrary.spaceIcons.first ?? "folder"

    @Environment(\.curioColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New Space")
                .curioText(CurioFont.headlineSmall)
                .foregroundStyle(colors.onSurface)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .curioText(CurioFont.labelLarge)
                    .foregroundStyle(colors.onSurfaceVariant)
                TextField("Space name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .curioText(CurioFont.labelLarge)
                    .foregroundStyle(colors.onSurfaceVariant)
                HStack(spacing: 10) {
                    ForEach(MacDeskLibrary.spaceColorPalette, id: \.color) { item in
                        Circle()
                            .fill(Color(packedARGB: item.color))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .strokeBorder(colors.onSurface, lineWidth: selectedColor == item.color ? 2.5 : 0)
                            )
                            .contentShape(Circle())
                            .onTapGesture {
                                selectedColor = item.color
                            }
                            .help(item.name)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .curioText(CurioFont.labelLarge)
                    .foregroundStyle(colors.onSurfaceVariant)
                HStack(spacing: 12) {
                    ForEach(MacDeskLibrary.spaceIcons, id: \.self) { icon in
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(selectedIcon == icon ? colors.primaryContainer : Color.clear)
                            )
                            .foregroundStyle(selectedIcon == icon ? colors.primary : colors.onSurfaceVariant)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedIcon = icon
                            }
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create Space") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onCreate(trimmed, selectedColor, selectedIcon)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 380)
    }
}
