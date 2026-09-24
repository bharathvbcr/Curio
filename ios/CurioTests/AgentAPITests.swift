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
    func brief(question: String, bookmarks: [Bookmark], privateMode: Bool) async -> AgentToolResult {
        .success(briefToReturn.jsonText(), tier: briefToReturn.tier)
    }
}

private final class RecordingTransport: AgentTransport, @unchecked Sendable {
    var calls = 0
    func perform(tool: String, argumentsJSON: String) async -> String {
        calls += 1
        return AgentToolResult.success("{\"id\":\"ok\"}").jsonText()
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
    }
}
