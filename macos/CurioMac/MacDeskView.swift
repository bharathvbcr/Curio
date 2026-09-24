import SwiftUI

/// Three-column research desk. The library on this Mac is filled by signing in to X.
/// Notes and favorites on the phone stay on the phone.
struct MacDeskView: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage(MacAgentPreferences.accessKey) private var agentAccess = false
    @AppStorage(MacAgentPreferences.writesKey) private var agentWrites = false
    @AppStorage(MacAgentPreferences.liveKey) private var liveResearch = false

    @State private var bookmarks: [Bookmark] = []
    @State private var spaces: [Space] = []
    @State private var selection: String?
    @State private var spaceSelection: String?
    @State private var query = ""
    @State private var researchQuestion = ""
    @State private var researchAnswer = ""
    @State private var status = "Sign in with X to pull the bookmarks on this account."
    @State private var showAgentSettings = false
    @State private var listener: AgentSocketListener?
    @State private var authModel: AuthViewModel?

    private var signedInId: String {
        if case let .signedIn(userId, _, _) = authModel?.authState { return userId }
        return ""
    }

    private var visible: [Bookmark] {
        let scoped = bookmarks.filter { spaceSelection == nil || $0.spaceId == spaceSelection }
        if query.isEmpty { return scoped }
        return scoped.filter { AgentLookup.keywordMatches($0, query: query) }
    }

    private var selected: Bookmark? { bookmarks.first { $0.id == selection } }

    var body: some View {
        Group {
            if let authModel {
                if signedInId.isEmpty {
                    LoginView(
                        state: authModel.authState,
                        tier: .full,
                        onLoginClick: { authModel.onLoginClick() },
                        errorMessage: authModel.loginError,
                        onDismissError: { authModel.clearLoginError() }
                    )
                } else {
                    desk
                }
            } else {
                ProgressView("Opening Curio")
            }
        }
        .task {
            if authModel == nil { authModel = environment.makeAuthViewModel() }
        }
        .task(id: signedInId) {
            guard !signedInId.isEmpty else { return }
            await reload()
            startAgentListener()
        }
    }

    private var desk: some View {
        NavigationSplitView {
            List(selection: $spaceSelection) {
                Text("Library").tag(String?.none)
                ForEach(spaces) { space in
                    Text(space.name).tag(Optional(space.id))
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } content: {
            VStack(spacing: 0) {
                TextField("Search bookmarks", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(8)
                List(visible, selection: $selection) { bookmark in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bookmark.title ?? bookmark.sourceTitle ?? "Untitled")
                            .font(.headline)
                        Text(bookmark.summary ?? String(bookmark.text.prefix(120)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .tag(bookmark.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Sync from X") { Task { await sync() } }
            }
            ToolbarItem {
                Button("Agents") { showAgentSettings = true }
            }
        }
        .sheet(isPresented: $showAgentSettings) { agentSettings }
        .onChange(of: agentAccess) { _, _ in startAgentListener() }
    }

    @ViewBuilder
    private var detail: some View {
        if let bookmark = selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(bookmark.title ?? "Untitled").font(.title2)
                    if let url = bookmark.url {
                        Link(url, destination: URL(string: url) ?? URL(string: "https://x.com")!)
                    }
                    Text(bookmark.text).textSelection(.enabled)
                    if let summary = bookmark.summary, !summary.isEmpty {
                        Text(summary).foregroundStyle(.secondary)
                    }
                    researchBox
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Curio").font(.largeTitle)
                Text("This Mac keeps its own library. Sign in with X to pull the same account. Notes, favorites, and embeddings on your iPhone do not come along.")
                researchBox
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var researchBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Research").font(.headline)
            TextField("Ask about a topic", text: $researchQuestion)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await research() } }
            Button("Research privately") { Task { await research() } }
                .keyboardShortcut("r", modifiers: [.command, .option])
            if !researchAnswer.isEmpty {
                Text(researchAnswer).textSelection(.enabled)
            }
        }
    }

    private var agentSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agent access").font(.title2)
            Toggle("Allow agents on this Mac to read the library", isOn: $agentAccess)
            Toggle("Allow agents to modify bookmarks", isOn: $agentWrites)
            Toggle("Allow live web research (xAI)", isOn: $liveResearch)
            Text("Read tools stay on-device unless live research is on. The xAI key and X tokens stay in the Keychain and are not returned to agents.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if agentAccess {
                Text(mcpSnippet).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Button("Copy configuration") {
                    _ = CurioFormat.copyToClipboard(mcpSnippet, label: "Curio MCP")
                }
            }
            Button("Done") { showAgentSettings = false }
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .frame(minWidth: 520)
        .onChange(of: agentAccess) { _, enabled in
            if enabled { _ = MacAgentPreferences.enableAccess() }
            startAgentListener()
        }
    }

    private var mcpSnippet: String {
        let binary = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/curio-mcp").path
        let token = MacAgentPreferences.token()
        return """
        {
          "mcpServers": {
            "curio": {
              "command": "\(binary)",
              "env": { "CURIO_AGENT_TOKEN": "\(token)" }
            }
          }
        }
        """
    }

    private func startAgentListener() {
        if agentAccess { _ = MacAgentPreferences.enableAccess() }
        if listener == nil {
            listener = AgentSocketListener(api: environment.makeLibraryAgentAPI())
        }
        listener?.startIfEnabled()
    }

    private func reload() async {
        guard let userId = await environment.tokenStore.getUserId() else {
            status = "Not signed in. Use Sync from X after signing in."
            return
        }
        bookmarks = await environment.bookmarkRepository.searchBookmarks(userId: userId, query: "")
        spaces = await environment.spaceStore.getSpaces(userId: userId)
        status = "\(bookmarks.count) bookmarks on this Mac."
    }

    private func sync() async {
        guard let userId = await environment.tokenStore.getUserId() else {
            status = "Sign in with X first. This Mac does not see the phone's local library."
            return
        }
        status = "Syncing from X…"
        do {
            try await environment.bookmarkRepository.syncBookmarks(userId: userId, fetchNextPage: false)
            await reload()
        } catch {
            status = error.localizedDescription
        }
    }

    private func research() async {
        let api = environment.makeLibraryAgentAPI()
        let result = await api.research(
            question: researchQuestion,
            privateMode: !liveResearch,
            sources: liveResearch ? ["web"] : [],
            limit: 8
        )
        researchAnswer = result.ok ? result.payload : "\(result.code ?? "error"): \(result.payload)"
    }
}
