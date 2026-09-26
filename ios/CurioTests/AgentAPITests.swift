import Darwin
import Foundation
import Testing
@testable import Curio

private final class FakeAgentLibrary: AgentLibrary, @unchecked Sendable {
    var userId: String? = "user"
    var bookmarks: [Bookmark] = []
    var vectors: [(String, Data)] = []
    var queryVector: [Float]? = [1, 0]
    var modelInstalled = true
    var spacesList: [Space] = []
    var allowWrites = false
    var keyOn = false
    var secretValues: [String] = []
    var saved: [ResearchCard] = []
    var added = 0

    func currentUserId() async -> String? { userId }
    func allBookmarks(userId: String) async -> [Bookmark] { bookmarks.filter { $0.userId == userId } }
    func bookmark(id: String) async -> Bookmark? { bookmarks.first { $0.id == id } }
    func embeddings(userId: String) async -> [(String, Data)] { vectors }
    func embedQuery(_ query: String) async -> [Float]? { queryVector }
    var embeddingModelInstalled: Bool { modelInstalled }
    func spaces(userId: String) async -> [Space] { spacesList }
    func writesAllowed() async -> Bool { allowWrites }
    func xaiConfigured() async -> Bool { keyOn }
    func secrets() async -> [String] { secretValues }
    func addBookmark(userId: String, text: String) async throws -> Bookmark {
        added += 1
        let bookmark = Bookmark(id: "manual_new", text: text, createdAt: 0, userId: userId)
        bookmarks.append(bookmark)
        return bookmark
    }
    func updateNotes(id: String, notes: String?) async {}
    func setFavorite(id: String, isFavorite: Bool) async {}
    func assignToSpace(ids: [String], spaceId: String?) async {}
    func saveResearch(_ card: ResearchCard) async throws { saved.append(card) }
    func researchCard(id: String) async -> ResearchCard? { saved.first { $0.id == id } }
}

private struct ScriptedSynthesizer: ResearchSynthesizer {
    var briefToReturn: ResearchBrief
    func brief(question: String, bookmarks: [Bookmark], privateMode: Bool, sources: [String]) async -> AgentToolResult {
        .success(briefToReturn.jsonText(), tier: briefToReturn.tier)
    }
}

private final class RecordingTransport: AgentTransport, @unchecked Sendable {
    var calls = 0
    var lastTool = ""
    var lastArguments = ""
    func perform(tool: String, argumentsJSON: String) async -> String {
        calls += 1
        lastTool = tool
        lastArguments = argumentsJSON
        return AgentToolResult.success("{\"id\":\"ok\"}").jsonText()
    }
}

private final class RecordingSynthesizer: ResearchSynthesizer, @unchecked Sendable {
    var calls = 0
    var sources: [String] = []
    func brief(question: String, bookmarks: [Bookmark], privateMode: Bool, sources: [String]) async -> AgentToolResult {
        calls += 1
        self.sources = sources
        let brief = ResearchBrief(
            answer: "from the web",
            claimBookmarkIds: [],
            caveats: "",
            readingList: [],
            citationURLs: ["https://example.com"],
            tier: "grok"
        )
        return .success(brief.jsonText(), tier: brief.tier)
    }
}

@Suite("Curio agent API")
struct AgentAPITests {

    private func bookmark(_ id: String, text: String, tags: [String] = [], notes: String? = nil) -> Bookmark {
        Bookmark(id: id, text: text, createdAt: 1, userId: "user", title: id, tags: tags, notes: notes)
    }

    @Test("availability probe is injectable")
    func availabilityProbe() {
        let gate = GenAiAvailability(probe: { .AVAILABLE })
        #expect(gate.status() == .AVAILABLE)
        #expect(gate.isNanoUsable())
        let off = GenAiAvailability(probe: { .UNAVAILABLE })
        #expect(off.isNanoUsable() == false)
    }

    @Test("semantic search with no vectors is index_empty")
    func emptyIndex() async {
        let library = FakeAgentLibrary()
        library.bookmarks = [bookmark("a", text: "diffusion")]
        library.vectors = []
        let api = LibraryAgentAPI(library: library, synthesizer: ScriptedSynthesizer(briefToReturn: ResearchBrief(answer: "", claimBookmarkIds: [], caveats: "", readingList: [], citationURLs: [], tier: "")), privateContextBudget: 1_500)
        let result = await api.semantic(query: "diffusion", limit: 5, anchorId: nil)
        #expect(result.ok == false)
        #expect(result.code == AgentFailure.indexEmpty.rawValue)
    }

    @Test("keyword search matches tags and notes")
    func keywordTags() async {
        let library = FakeAgentLibrary()
        library.bookmarks = [bookmark("a", text: "unrelated", tags: ["RLHF"], notes: nil)]
        let api = LibraryAgentAPI(library: library, synthesizer: ScriptedSynthesizer(briefToReturn: ResearchBrief(answer: "", claimBookmarkIds: [], caveats: "", readingList: [], citationURLs: [], tier: "")), privateContextBudget: 1_500)
        let result = await api.search(query: "rlhf", limit: 10)
        #expect(result.payload.contains("\"a\""))
    }

    @Test("private research rejects a claim id that was not retrieved")
    func citationGuard() async {
        let library = FakeAgentLibrary()
        library.bookmarks = [bookmark("a", text: "diffusion models")]
        library.vectors = [("a", VectorSearch.floatArrayToData([1, 0]))]
        library.queryVector = [1, 0]
        let brief = ResearchBrief(answer: "see nope", claimBookmarkIds: ["a", "nope"], caveats: "", readingList: [], citationURLs: [], tier: "test")
        let api = LibraryAgentAPI(library: library, synthesizer: ScriptedSynthesizer(briefToReturn: brief), privateContextBudget: 1_500)
        let result = await api.research(question: "diffusion", privateMode: true, sources: [], limit: 5)
        #expect(result.code == AgentFailure.citationRejected.rawValue)
        #expect(result.payload.contains("nope"))
    }

    @Test("private research reports context_exceeded with the bookmark ids")
    func contextBudget() async {
        let library = FakeAgentLibrary()
        library.bookmarks = [bookmark("a", text: String(repeating: "word ", count: 400))]
        library.vectors = [("a", VectorSearch.floatArrayToData([1, 0]))]
        library.queryVector = [1, 0]
        let api = LibraryAgentAPI(library: library, synthesizer: ScriptedSynthesizer(briefToReturn: ResearchBrief(answer: "x", claimBookmarkIds: ["a"], caveats: "", readingList: [], citationURLs: [], tier: "t")), privateContextBudget: 5)
        let result = await api.research(question: "word", privateMode: true, sources: [], limit: 5)
        #expect(result.code == AgentFailure.contextExceeded.rawValue)
        #expect(result.payload.contains("a"))
    }

    @Test("write tools fail while the write switch is off")
    func writesOff() async {
        let library = FakeAgentLibrary()
        library.allowWrites = false
        let api = LibraryAgentAPI(library: library, synthesizer: ScriptedSynthesizer(briefToReturn: ResearchBrief(answer: "", claimBookmarkIds: [], caveats: "", readingList: [], citationURLs: [], tier: "")), privateContextBudget: 1_500)
        let result = await api.call(tool: "save_bookmark", argumentsJSON: "{\"text\":\"hello\"}")
        #expect(result.contains("writes_disabled"))
        #expect(library.added == 0)
    }

    @Test("redactor strips a key that leaked into a tool payload")
    func redactsSecrets() async {
        let library = FakeAgentLibrary()
        library.secretValues = ["sk-test-secret-value"]
        library.bookmarks = [bookmark("a", text: "the key is sk-test-secret-value")]
        let api = LibraryAgentAPI(library: library, synthesizer: ScriptedSynthesizer(briefToReturn: ResearchBrief(answer: "", claimBookmarkIds: [], caveats: "", readingList: [], citationURLs: [], tier: "")), privateContextBudget: 1_500)
        let result = await api.call(tool: "get_bookmark", argumentsJSON: "{\"id\":\"a\"}")
        #expect(result.contains("[redacted]"))
        #expect(!result.contains("sk-test-secret-value"))
    }

    @Test("a refused token never reaches the transport")
    func refusedToken() async {
        let transport = RecordingTransport()
        let dispatcher = MCPDispatcher(gate: { false }, transport: transport)
        let line = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search_bookmarks","arguments":{"query":"a"}}}"#
        let response = await dispatcher.handle(line)
        #expect(transport.calls == 0)
        #expect(response?.contains("bad_token") == true)
    }

    @Test("initialize and an admitted tools/call complete")
    func mcpRoundTrip() async {
        let transport = RecordingTransport()
        let dispatcher = MCPDispatcher(gate: { true }, transport: transport)
        let initLine = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#
        let initialized = await dispatcher.handle(initLine)
        #expect(initialized?.contains("2025-11-25") == true)
        let call = #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"search_bookmarks","arguments":{"query":"a"}}}"#
        let response = await dispatcher.handle(call)
        #expect(transport.calls == 1)
        #expect(response?.contains("\"isError\":false") == true || response?.contains("\"isError\": false") == true)
    }

    @Test("mac agent access defaults off and enabling mints a token")
    func macAccessDefault() {
        let defaults = UserDefaults(suiteName: "curio.agent.tests.\(UUID().uuidString)")!
        #expect(MacAgentPreferences.accessEnabled(defaults) == false)
        #expect(MacAgentPreferences.writesAllowed(defaults) == false)
        let token = MacAgentPreferences.enableAccess(defaults)
        #expect(MacAgentPreferences.accessEnabled(defaults))
        #expect(AgentRequestGate.admit(presented: token, expected: token, accessEnabled: true))
        #expect(AgentRequestGate.admit(presented: "nope", expected: token, accessEnabled: true) == false)
        #expect(AgentRequestGate.admit(presented: token, expected: token, accessEnabled: false) == false)
        #expect(AgentRequestGate.admit(presented: "short", expected: token, accessEnabled: true) == false)
        #expect(AgentRequestGate.admit(presented: "", expected: token, accessEnabled: true) == false)
    }

    @Test("private research still requires the embedding index")
    func privateRequiresIndex() async {
        let library = FakeAgentLibrary()
        library.modelInstalled = false
        let api = LibraryAgentAPI(library: library, synthesizer: ScriptedSynthesizer(briefToReturn: ResearchBrief(answer: "", claimBookmarkIds: [], caveats: "", readingList: [], citationURLs: [], tier: "")), privateContextBudget: 1_500)
        let result = await api.research(question: "diffusion", privateMode: true, sources: [], limit: 5)
        #expect(result.code == AgentFailure.embeddingModelMissing.rawValue)
    }

    @Test("private mode rejects a live source before searching")
    func privateRejectsWeb() async {
        let library = FakeAgentLibrary()
        library.modelInstalled = false
        let api = LibraryAgentAPI(library: library, synthesizer: ScriptedSynthesizer(briefToReturn: ResearchBrief(answer: "", claimBookmarkIds: [], caveats: "", readingList: [], citationURLs: [], tier: "")), privateContextBudget: 1_500)
        let result = await api.research(question: "diffusion", privateMode: true, sources: ["web"], limit: 5)
        #expect(result.code == AgentFailure.privateMode.rawValue)
    }

    @Test("live web research proceeds when the embedding index is missing")
    func liveWithoutIndex() async {
        let library = FakeAgentLibrary()
        library.modelInstalled = false
        library.keyOn = true
        let synth = RecordingSynthesizer()
        let api = LibraryAgentAPI(library: library, synthesizer: synth, privateContextBudget: 1_500, liveAllowed: { true })
        let result = await api.research(question: "diffusion", privateMode: false, sources: ["web"], limit: 5)
        #expect(synth.calls == 1)
        #expect(synth.sources == ["web"])
        #expect(result.code != AgentFailure.embeddingModelMissing.rawValue)
        #expect(result.ok)
    }

    @Test("live web research stays off until the Mac switch is on")
    func liveBlockedWhenSwitchOff() async {
        let library = FakeAgentLibrary()
        library.modelInstalled = true
        library.keyOn = true
        library.vectors = [("a", VectorSearch.floatArrayToData([1, 0]))]
        library.queryVector = [1, 0]
        library.bookmarks = [bookmark("a", text: "diffusion models")]
        let synth = RecordingSynthesizer()
        let api = LibraryAgentAPI(library: library, synthesizer: synth, privateContextBudget: 1_500, liveAllowed: { false })
        let result = await api.research(question: "diffusion", privateMode: false, sources: ["web"], limit: 5)
        #expect(synth.calls == 0)
        #expect(result.code == AgentFailure.privateMode.rawValue)
        #expect(result.payload.contains("live_research_disabled"))
    }

    @Test("live web research reports a missing xAI key instead of an empty index")
    func liveReportsMissingKey() async {
        let library = FakeAgentLibrary()
        library.modelInstalled = true
        library.vectors = []
        library.keyOn = false
        let synth = RecordingSynthesizer()
        let api = LibraryAgentAPI(library: library, synthesizer: synth, privateContextBudget: 1_500, liveAllowed: { true })
        let result = await api.research(question: "diffusion", privateMode: false, sources: ["web"], limit: 5)
        #expect(synth.calls == 0)
        #expect(result.code == AgentFailure.keyMissing.rawValue)
    }

    @Test("resource uris that contain quotes stay valid JSON")
    func quotedResourceURI() async throws {
        let transport = RecordingTransport()
        let dispatcher = MCPDispatcher(gate: { true }, transport: transport)
        let uri = "curio://bookmark/a\"b"
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 3,
            "method": "resources/read",
            "params": ["uri": uri]
        ]
        let line = String(data: try JSONSerialization.data(withJSONObject: message), encoding: .utf8)!
        _ = await dispatcher.handle(line)
        let data = try #require(transport.lastArguments.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["uri"] as? String == uri)
    }

    @Test("tool errors that contain quotes stay valid JSON")
    func errorContentEscapes() throws {
        let content = MCPCatalog.errorContent(code: "bad_token", detail: "say \"hi\"")
        let text = try #require((content["content"] as? [[String: Any]])?.first?["text"] as? String)
        let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(object["ok"] as? Bool == false)
        #expect(object["code"] as? String == "bad_token")
        #expect(object["payload"] as? String == "say \"hi\"")
    }

    @Test("advertised prompts are not an unknown tool")
    func promptTool() async {
        let library = FakeAgentLibrary()
        let api = LibraryAgentAPI(library: library, synthesizer: ScriptedSynthesizer(briefToReturn: ResearchBrief(answer: "", claimBookmarkIds: [], caveats: "", readingList: [], citationURLs: [], tier: "")), privateContextBudget: 1_500)
        let result = await api.call(tool: "get_prompt", argumentsJSON: "{\"name\":\"research-brief\"}")
        #expect(result.contains("unknown_tool") == false)
        #expect(result.contains("research"))
    }

    @Test("live sources turn on xAI web search")
    func liveSourcesEnableSearch() {
        let on = CurioResearchSynthesizer.chatParts(question: "diffusion", bookmarks: [], sources: ["library", "web"])
        #expect(on.searchParameters != nil)
        let off = CurioResearchSynthesizer.chatParts(question: "diffusion", bookmarks: [], sources: ["library"])
        #expect(off.searchParameters == nil)
        #expect(CurioResearchSynthesizer.mergedCitations(["https://a.test"], ["https://a.test", "https://b.test"]) == ["https://a.test", "https://b.test"])
    }

    @Test("mcp configuration points at whichever embedded helper exists")
    func helperPath() throws {
        let root = URL(fileURLWithPath: "/tmp/cb-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Contents/Resources", isDirectory: true)
        let macos = root.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let resourceBinary = resources.appendingPathComponent("curio-mcp")
        try Data([0x00]).write(to: resourceBinary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: resourceBinary.path)
        let found = try #require(MacAgentInstall.helperURL(bundleURL: root))
        #expect(found.path == resourceBinary.path)

        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let macosBinary = macos.appendingPathComponent("curio-mcp")
        try Data([0x00]).write(to: macosBinary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: macosBinary.path)
        let preferred = try #require(MacAgentInstall.helperURL(bundleURL: root))
        #expect(preferred.path == macosBinary.path)

        let snippet = MacAgentInstall.configuration(bundleURL: root, token: "tok\"en")
        let object = try #require(JSONSerialization.jsonObject(with: Data(snippet.utf8)) as? [String: Any])
        let servers = try #require(object["mcpServers"] as? [String: Any])
        let curio = try #require(servers["curio"] as? [String: Any])
        #expect(curio["command"] as? String == macosBinary.path)
        let env = try #require(curio["env"] as? [String: Any])
        #expect(env["CURIO_AGENT_TOKEN"] as? String == "tok\"en")
    }

    @Test("the helper finds the app bundle from either embed location")
    func appBundleLocator() {
        let resources = URL(fileURLWithPath: "/tmp/Curio.app/Contents/Resources/curio-mcp")
        let macos = URL(fileURLWithPath: "/tmp/Curio.app/Contents/MacOS/curio-mcp")
        #expect(AgentAppLocator.appBundle(containing: resources)?.lastPathComponent == "Curio.app")
        #expect(AgentAppLocator.appBundle(containing: macos)?.lastPathComponent == "Curio.app")
        #expect(AgentAppLocator.appBundle(containing: URL(fileURLWithPath: "/tmp/curio-mcp")) == nil)
    }

    @Test("a closed peer does not kill the writer")
    func closedPeerWrite() throws {
        let (server, url) = try openTempServer()
        defer { close(server); unlink(url.path) }
        let client = AgentSocketIO.openClient(at: url)
        #expect(client >= 0)
        let accepted = accept(server, nil, nil)
        #expect(accepted >= 0)
        var sendBuffer: Int32 = 1024
        _ = setsockopt(accepted, SOL_SOCKET, SO_SNDBUF, &sendBuffer, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(accepted, F_GETFL)
        if flags >= 0 { _ = fcntl(accepted, F_SETFL, flags | O_NONBLOCK) }
        close(client)
        let payload = String(repeating: "x", count: 200_000)
        let first = AgentSocketIO.writeLine(payload, fd: accepted)
        let second = AgentSocketIO.writeLine(payload, fd: accepted)
        #expect(first == false || second == false)
        close(accepted)
    }

    @Test("an oversized line does not desynchronize the next message")
    func oversizedLine() throws {
        let (server, url) = try openTempServer()
        defer { close(server); unlink(url.path) }
        let client = AgentSocketIO.openClient(at: url)
        let accepted = accept(server, nil, nil)
        defer { close(client); close(accepted) }
        var bytes = Array(repeating: UInt8(ascii: "a"), count: 40)
        bytes.append(10)
        bytes.append(contentsOf: Array("{\"ok\":true}\n".utf8))
        var offset = 0
        while offset < bytes.count {
            let wrote = bytes.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.write(client, base.advanced(by: offset), bytes.count - offset)
            }
            if wrote <= 0 { break }
            offset += wrote
        }
        #expect(AgentSocketIO.readLine(fd: accepted, maxBytes: 16) == nil)
        #expect(AgentSocketIO.readLine(fd: accepted, maxBytes: 16) == "{\"ok\":true}")
    }

    @Test("concurrent clients round-trip full lines")
    func concurrentClients() async throws {
        let (server, url) = try openTempServer()
        defer { close(server); unlink(url.path) }
        let echo = Task.detached {
            for _ in 0..<8 {
                let client = accept(server, nil, nil)
                if client < 0 { continue }
                if let line = AgentSocketIO.readLine(fd: client) {
                    _ = AgentSocketIO.writeLine(line, fd: client)
                }
                close(client)
            }
        }
        let results = await withTaskGroup(of: Bool.self) { group in
            for index in 0..<8 {
                group.addTask {
                    let fd = AgentSocketIO.openClient(at: url)
                    guard fd >= 0 else { return false }
                    defer { close(fd) }
                    let body = "id=\(index)-" + String(repeating: "q", count: 64_000)
                    guard AgentSocketIO.writeLine(body, fd: fd) else { return false }
                    return AgentSocketIO.readLine(fd: fd) == body
                }
            }
            var ok = 0
            for await value in group where value { ok += 1 }
            return ok
        }
        #expect(results == 8)
        await echo.value
    }

#if os(macOS)
    @Test("the listener retries a failed bind and then serves a tool")
    func listenerRetriesThenServes() async throws {
        let root = URL(fileURLWithPath: "/tmp/cl-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let sock = root.appendingPathComponent("n", isDirectory: true).appendingPathComponent("a.sock")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FakeAgentLibrary()
        library.bookmarks = [bookmark("a", text: "diffusion models")]
        let api = LibraryAgentAPI(library: library, synthesizer: ScriptedSynthesizer(briefToReturn: ResearchBrief(answer: "", claimBookmarkIds: [], caveats: "", readingList: [], citationURLs: [], tier: "")), privateContextBudget: 1_500)
        let listener = AgentSocketListener(api: api, socketURL: sock, accessEnabled: { true }, token: { "secret" })
        #expect(listener.start() == false)
        try FileManager.default.createDirectory(at: sock.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(listener.start() == true)
        defer { listener.stop() }

        let denied = try roundTrip(sock: sock, token: "nope", tool: "search_bookmarks", arguments: "{\"query\":\"diffusion\"}")
        #expect(denied.contains("bad_token"))
        #expect(denied.contains("diffusion") == false)

        let malformed = try rawRoundTrip(sock: sock, line: "not-json")
        #expect(malformed.contains("malformed"))

        let allowed = try roundTrip(sock: sock, token: "secret", tool: "search_bookmarks", arguments: "{\"query\":\"diffusion\"}")
        let allowedObject = try #require(JSONSerialization.jsonObject(with: Data(allowed.utf8)) as? [String: Any])
        #expect(allowedObject["ok"] as? Bool == true)
        #expect((allowedObject["payload"] as? String)?.contains("diffusion models") == true)
    }

    @Test("eight clients can query the listener at once")
    func listenerStress() async throws {
        let root = URL(fileURLWithPath: "/tmp/cs-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sock = root.appendingPathComponent("agent.sock")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FakeAgentLibrary()
        library.bookmarks = [bookmark("a", text: "diffusion models")]
        let api = LibraryAgentAPI(library: library, synthesizer: ScriptedSynthesizer(briefToReturn: ResearchBrief(answer: "", claimBookmarkIds: [], caveats: "", readingList: [], citationURLs: [], tier: "")), privateContextBudget: 1_500)
        let listener = AgentSocketListener(api: api, socketURL: sock, accessEnabled: { true }, token: { "secret" })
        #expect(listener.start() == true)
        defer { listener.stop() }
        let hits = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    guard let line = try? roundTrip(sock: sock, token: "secret", tool: "get_bookmark", arguments: "{\"id\":\"a\"}"),
                          let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                          object["ok"] as? Bool == true,
                          let payload = object["payload"] as? String else { return false }
                    return payload.contains("diffusion models")
                }
            }
            var ok = 0
            for await value in group where value { ok += 1 }
            return ok
        }
        #expect(hits == 8)
    }
#endif

    private func openTempServer() throws -> (Int32, URL) {
        let url = URL(fileURLWithPath: "/tmp/curio-\(UUID().uuidString.prefix(8)).sock")
        let server = AgentSocketIO.openServer(at: url)
        try #require(server >= 0)
        return (server, url)
    }

#if os(macOS)
    private func roundTrip(sock: URL, token: String, tool: String, arguments: String) throws -> String {
        let line = AgentLine.request(token: token, tool: tool, argumentsJSON: arguments)
        return try rawRoundTrip(sock: sock, line: line)
    }

    private func rawRoundTrip(sock: URL, line: String) throws -> String {
        let fd = AgentSocketIO.openClient(at: sock)
        try #require(fd >= 0)
        defer { close(fd) }
        try #require(AgentSocketIO.writeLine(line, fd: fd))
        return try #require(AgentSocketIO.readLine(fd: fd))
    }
#endif
}
