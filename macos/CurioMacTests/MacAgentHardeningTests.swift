#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import Testing
@testable import Curio

/// Adversarial tests for the agent path: the socket listener, the MCP dispatcher, and the
/// agent API's write tools. Everything here also runs against the Linux harness.
@Suite("Mac agent hardening", .serialized)
struct MacAgentHardeningTests {

    // MARK: - Listener

    @Test("silent clients time out instead of holding every slot")
    func silentClientsReleaseSlots() async throws {
        let rig = try ListenerRig(readTimeout: 0.4)
        defer { rig.tearDown() }
        var idle: [Int32] = []
        for _ in 0..<AgentSocketListener.maxInFlight {
            let fd = AgentSocketIO.openClient(at: rig.socket)
            try #require(fd >= 0)
            idle.append(fd)
        }
        defer { idle.forEach { close($0) } }
        try await Task.sleep(nanoseconds: 150_000_000)

        // Every slot is held: the next client hears "busy" at once rather than hanging.
        let busy = try rig.raw(AgentLine.request(token: "tok", tool: "library_overview", argumentsJSON: "{}"), timeout: 2)
        #expect(busy?.contains("busy") == true)

        // Once the read timeout passes the slots come back.
        try await Task.sleep(nanoseconds: 900_000_000)
        #expect(rig.listener.activeConnections == 0)
        let served = try rig.call(tool: "library_overview")
        #expect(served.contains("\"ok\":true"))
    }

    @Test("a client that trickles bytes is cut off at the deadline")
    func slowLoris() async throws {
        let rig = try ListenerRig(readTimeout: 0.5)
        defer { rig.tearDown() }
        let socket = rig.socket
        let started = Date()
        let reply: String? = await ListenerRig.onThread {
            let fd = AgentSocketIO.openClient(at: socket)
            guard fd >= 0 else { return "no connect" }
            defer { close(fd) }
            AgentSocketIO.setTimeouts(fd, read: 5, write: 5)
            // One byte every 150 ms never trips a per-call timeout of 500 ms.
            for byte in Array("{\"token\":\"tok\",\"tool\":\"library_overview\"}".utf8) {
                var value = byte
                if send(fd, &value, 1, testSendFlags) != 1 { break }
                usleep(150_000)
                if Date().timeIntervalSince(started) > 3 { break }
            }
            return AgentSocketIO.readLine(fd: fd)
        }
        #expect(reply == nil)
        #expect(Date().timeIntervalSince(started) < 4.5)
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(rig.listener.activeConnections == 0)
    }

    @Test("half a request followed by a hang-up frees the slot")
    func halfLineThenClose() async throws {
        let rig = try ListenerRig(readTimeout: 2)
        defer { rig.tearDown() }
        for _ in 0..<50 {
            let fd = AgentSocketIO.openClient(at: rig.socket)
            try #require(fd >= 0)
            var bytes = Array("{\"token\":\"tok\",\"to".utf8)
            _ = send(fd, &bytes, bytes.count, testSendFlags)
            close(fd)
        }
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(rig.listener.activeConnections == 0)
        #expect(try rig.call(tool: "library_overview").contains("\"ok\":true"))
    }

    @Test("an oversized request is dropped and the listener keeps serving")
    func oversizedRequest() async throws {
        let rig = try ListenerRig()
        defer { rig.tearDown() }
        let huge = String(repeating: "x", count: AgentSocketListener.maxRequestBytes + 10)
        let reply = try rig.raw(huge, timeout: 5)
        #expect(reply == nil)
        #expect(try rig.call(tool: "library_overview").contains("\"ok\":true"))
    }

    @Test("stop then start rebinds the same path immediately")
    func restart() async throws {
        let rig = try ListenerRig()
        defer { rig.tearDown() }
        for _ in 0..<5 {
            rig.listener.stop()
            #expect(rig.listener.start())
            #expect(try rig.call(tool: "library_overview").contains("\"ok\":true"))
        }
    }

    @Test("a second listener cannot steal a live socket")
    func secondListenerRefused() async throws {
        let rig = try ListenerRig()
        defer { rig.tearDown() }
        let intruder = AgentSocketListener(api: rig.api, socketURL: rig.socket, accessEnabled: { true }, token: { "other" })
        #expect(intruder.start() == false)
        #expect(try rig.call(tool: "library_overview").contains("\"ok\":true"))
        intruder.stop()
        // Stopping the refused listener must not unlink the live socket.
        #expect(try rig.call(tool: "library_overview").contains("\"ok\":true"))
    }

    @Test("a stale socket file from a crash is replaced")
    func staleSocketReplaced() throws {
        let root = try ListenerRig.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let socket = root.appendingPathComponent("agent.sock")
        let orphan = AgentSocketIO.openServer(at: socket)
        try #require(orphan >= 0)
        close(orphan)
        #expect(FileManager.default.fileExists(atPath: socket.path))
        let listener = AgentSocketListener(api: ListenerRig.makeAPI(HardeningLibrary()), socketURL: socket, accessEnabled: { true }, token: { "tok" })
        #expect(listener.start())
        listener.stop()
    }

    @Test("two hundred concurrent requests all resolve")
    func burst() async throws {
        let rig = try ListenerRig()
        defer { rig.tearDown() }
        let socket = rig.socket
        let outcomes = await withTaskGroup(of: String.self) { group in
            for index in 0..<200 {
                group.addTask {
                    let tool = index % 3 == 0 ? "search_bookmarks" : "get_bookmark"
                    let args = index % 3 == 0 ? "{\"query\":\"alpha\"}" : "{\"id\":\"a\"}"
                    let line = AgentLine.request(token: index % 10 == 0 ? "wrong" : "tok", tool: tool, argumentsJSON: args)
                    // Clients block like separate processes would, on their own threads.
                    let answer = await ListenerRig.onThread { ListenerRig.exchange(socket: socket, line: line, timeout: 10) }
                    guard let reply = answer else { return "none" }
                    if reply.contains("busy") { return "busy" }
                    if reply.contains("bad_token") { return "denied" }
                    return reply.contains("\"ok\":true") ? "ok" : "other"
                }
            }
            var all: [String] = []
            for await outcome in group { all.append(outcome) }
            return all
        }
        #expect(outcomes.count == 200)
        #expect(!outcomes.contains("none"))
        #expect(!outcomes.contains("other"))
        #expect(outcomes.filter { $0 == "denied" }.count <= 20)
        #expect(outcomes.contains("ok"))
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(rig.listener.activeConnections == 0)
    }

    @Test("start and stop from many tasks leave one consistent state")
    func startStopRace() async throws {
        let rig = try ListenerRig()
        defer { rig.tearDown() }
        let listener = rig.listener
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<64 {
                group.addTask {
                    if index % 2 == 0 { listener.start() } else { listener.stop() }
                }
            }
        }
        listener.stop()
        #expect(listener.isListening == false)
        #expect(listener.start())
        #expect(try rig.call(tool: "library_overview").contains("\"ok\":true"))
    }

    @Test("every request lands in the audit log without its arguments")
    func auditTrail() async throws {
        let rig = try ListenerRig()
        defer { rig.tearDown() }
        _ = try rig.call(tool: "search_bookmarks", arguments: "{\"query\":\"secret words\"}")
        _ = try rig.raw(AgentLine.request(token: "nope", tool: "get_bookmark", argumentsJSON: "{}"), timeout: 2)
        _ = try rig.raw("not json", timeout: 2)
        _ = try rig.call(tool: "evil\ttool\nname")
        let entries = rig.listener.auditLog.recent(limit: 10)
        #expect(entries.count == 4)
        #expect(entries.contains { $0.tool == "search_bookmarks" && $0.outcome == "ok" })
        #expect(entries.contains { $0.outcome == AgentFailure.badToken.rawValue })
        #expect(entries.contains { $0.outcome == "malformed" })
        #expect(entries.contains { $0.tool == "evil tool name" })
        let raw = try String(contentsOf: rig.listener.auditLog.url, encoding: .utf8)
        #expect(!raw.contains("secret words"))
    }

    // MARK: - Audit log

    @Test("the audit log rotates instead of wiping history")
    func auditRotation() throws {
        let root = try ListenerRig.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = AgentAuditLog(url: root.appendingPathComponent("audit.log"), maxBytes: 2_048)
        for index in 0..<200 {
            log.append(AgentAudit.line(client: "mcp", tool: "tool_\(index)", argumentHash: "h", tier: "", outcome: "ok"))
        }
        let live = (try? FileManager.default.attributesOfItem(atPath: log.url.path)[.size] as? Int) ?? 0
        #expect(live <= 2_048)
        #expect(FileManager.default.fileExists(atPath: log.rotatedURL.path))
        let recent = log.recent(limit: 5)
        #expect(recent.first?.tool == "tool_199")
        #expect(recent.count == 5)
        log.clear()
        #expect(log.recent().isEmpty)
    }

    @Test("audit lines parse old and new layouts and skip junk")
    func auditParsing() {
        #expect(AgentAuditEntry(line: "2026-01-01T00:00:00Z\tmcp\tget_bookmark\tabc\tlocal")?.outcome == "")
        #expect(AgentAuditEntry(line: "2026-01-01T00:00:00Z\tmcp\tget_bookmark\tabc\t\tnot_found")?.succeeded == false)
        #expect(AgentAuditEntry(line: "garbage") == nil)
        #expect(AgentAuditEntry(line: "") == nil)
        #expect(AgentActivityFormat.sanitizedTool("") == "(none)")
        #expect(AgentActivityFormat.sanitizedTool(String(repeating: "a", count: 200)).count == 65)
    }

    // MARK: - MCP dispatcher

    @Test("malformed JSON-RPC gets the spec's error codes")
    func jsonRpcErrors() async throws {
        let dispatcher = MCPDispatcher(gate: { true }, transport: EchoTransport())
        #expect(try code(await dispatcher.handle("{not json")) == -32700)
        #expect(try code(await dispatcher.handle("[1,2]")) == -32600)
        #expect(try code(await dispatcher.handle(#"{"jsonrpc":"2.0","id":1}"#)) == -32600)
        #expect(try code(await dispatcher.handle(#"{"jsonrpc":"2.0","id":true,"method":"ping"}"#)) == -32600)
        #expect(try code(await dispatcher.handle(#"{"jsonrpc":"2.0","id":1,"method":"nope"}"#)) == -32601)
        #expect(try code(await dispatcher.handle(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":[1]}"#)) == -32602)
        #expect(try code(await dispatcher.handle(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"drop_tables"}}"#)) == -32602)
        #expect(try code(await dispatcher.handle(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{}}"#)) == -32602)
        // Notifications and client responses get no reply at all.
        #expect(await dispatcher.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        #expect(await dispatcher.handle(#"{"jsonrpc":"2.0","id":5,"result":{}}"#) == nil)
        #expect(await dispatcher.handle("   ") == nil)
    }

    @Test("initialize echoes a supported version and falls back to the newest")
    func versionNegotiation() async throws {
        let dispatcher = MCPDispatcher(gate: { true }, transport: EchoTransport())
        for version in MCPDispatcher.supportedVersions {
            let reply = await dispatcher.handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"\#(version)"}}"#)
            #expect(try result(reply)["protocolVersion"] as? String == version)
        }
        let future = await dispatcher.handle(#"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#)
        #expect(try result(future)["protocolVersion"] as? String == MCPDispatcher.supportedVersions[0])
        #expect(try result(future)["instructions"] as? String != nil)
    }

    @Test("every tool advertises a real input schema")
    func toolSchemas() throws {
        let tools = MCPCatalog.tools()
        #expect(tools.count == MCPCatalog.toolNames.count)
        for tool in tools {
            let schema = try #require(tool["inputSchema"] as? [String: Any])
            #expect(schema["type"] as? String == "object")
            let properties = try #require(schema["properties"] as? [String: Any])
            for key in schema["required"] as? [String] ?? [] {
                #expect(properties[key] != nil, "\(tool["name"] ?? "") requires undeclared \(key)")
            }
            #expect(JSONSerialization.isValidJSONObject(tool))
        }
        let search = try #require(tools.first { $0["name"] as? String == "search_bookmarks" })
        let props = try #require((search["inputSchema"] as? [String: Any])?["properties"] as? [String: Any])
        #expect(props["query"] != nil && props["limit"] != nil)
    }

    @Test("bad arguments come back as a tool error the agent can read")
    func argumentValidation() async throws {
        let transport = EchoTransport()
        let dispatcher = MCPDispatcher(gate: { true }, transport: transport)
        let cases: [(String, String)] = [
            (#"{"name":"get_bookmark","arguments":{}}"#, "id is required"),
            (#"{"name":"get_bookmark","arguments":{"id":7}}"#, "id must be a string"),
            (#"{"name":"search_bookmarks","arguments":{"limit":"ten"}}"#, "limit must be a whole number"),
            (#"{"name":"search_bookmarks","arguments":{"limit":2.5}}"#, "limit must be a whole number"),
            (#"{"name":"set_favorite","arguments":{"id":"a","favorite":1}}"#, "favorite must be true or false"),
            (#"{"name":"file_in_space","arguments":{"ids":"a"}}"#, "ids must be an array"),
            (#"{"name":"export_citations","arguments":{"format":"docx"}}"#, "format must be one of")
        ]
        for (params, expected) in cases {
            let reply = await dispatcher.handle(#"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":\#(params)}"#)
            let object = try result(reply)
            #expect(object["isError"] as? Bool == true)
            let text = ((object["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
            #expect(text.contains(expected), "\(params) → \(text)")
        }
        #expect(transport.calls == 0)
        let nullSpace = await dispatcher.handle(#"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"file_in_space","arguments":{"ids":["a"],"spaceId":null}}}"#)
        #expect(try result(nullSpace)["isError"] as? Bool == false)
        #expect(transport.calls == 1)
    }

    @Test("resource reads map failures to errors and templates are listed")
    func resources() async throws {
        let transport = EchoTransport()
        transport.reply = AgentToolResult.failure(.notFound, payload: "not_found").jsonText()
        let dispatcher = MCPDispatcher(gate: { true }, transport: transport)
        #expect(try code(await dispatcher.handle(#"{"jsonrpc":"2.0","id":1,"method":"resources/read","params":{"uri":"curio://bookmark/zz"}}"#)) == -32002)
        #expect(try code(await dispatcher.handle(#"{"jsonrpc":"2.0","id":1,"method":"resources/read","params":{}}"#)) == -32602)
        transport.reply = AgentToolResult.success("[{\"id\":\"a\"}]").jsonText()
        let read = try result(await dispatcher.handle(#"{"jsonrpc":"2.0","id":1,"method":"resources/read","params":{"uri":"curio://library/recent"}}"#))
        let text = ((read["contents"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        #expect(text == "[{\"id\":\"a\"}]")
        let templates = try result(await dispatcher.handle(#"{"jsonrpc":"2.0","id":1,"method":"resources/templates/list"}"#))
        #expect((templates["resourceTemplates"] as? [[String: Any]])?.count == 3)
        let closed = MCPDispatcher(gate: { false }, transport: transport)
        #expect(try code(await closed.handle(#"{"jsonrpc":"2.0","id":1,"method":"resources/read","params":{"uri":"curio://library/recent"}}"#)) == -32001)
        #expect(try code(await dispatcher.handle(#"{"jsonrpc":"2.0","id":1,"method":"prompts/get","params":{"name":"nope"}}"#)) == -32602)
    }

    @Test("random bytes never crash the dispatcher")
    func dispatcherFuzz() async {
        let dispatcher = MCPDispatcher(gate: { true }, transport: EchoTransport())
        var generator = SeededGenerator(seed: 42)
        let alphabet = Array("{}[]\":,0123456789abcdefnulltrue-.\\ \t\u{0}é😀")
        for _ in 0..<2_000 {
            let length = Int.random(in: 0..<80, using: &generator)
            let line = String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
            if let reply = await dispatcher.handle(line) {
                #expect((try? JSONSerialization.jsonObject(with: Data(reply.utf8))) != nil)
            }
        }
        let fragments = [
            #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search_bookmarks","arguments":{"limit":1e308}}}"#,
            #"{"jsonrpc":"2.0","id":1e400,"method":"ping"}"#,
            #"{"jsonrpc":"2.0","id":{"a":1},"method":"ping"}"#,
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":null}}"#
        ]
        for line in fragments {
            if let reply = await dispatcher.handle(line) {
                #expect((try? JSONSerialization.jsonObject(with: Data(reply.utf8))) != nil)
            }
        }
    }

    // MARK: - Agent API

    @Test("hostile numbers are clamped instead of trapping")
    func hostileNumbers() async {
        let api = ListenerRig.makeAPI(HardeningLibrary())
        for limit in ["1e300", "-1e300", "9223372036854775807", "-5", "0", "3.7", "true", "\"12\""] {
            let reply = await api.call(tool: "search_bookmarks", argumentsJSON: "{\"query\":\"\",\"limit\":\(limit)}")
            #expect(reply.contains("\"ok\":true"), "limit \(limit)")
        }
    }

    @Test("write tools only touch this user's bookmarks and real spaces")
    func writeScoping() async {
        let library = HardeningLibrary()
        library.writes = true
        let api = ListenerRig.makeAPI(library)
        #expect(await api.call(tool: "set_favorite", argumentsJSON: "{\"id\":\"ghost\"}").contains("not_found"))
        #expect(await api.call(tool: "set_favorite", argumentsJSON: "{\"id\":\"theirs\"}").contains("not_found"))
        #expect(await api.call(tool: "add_note", argumentsJSON: "{\"id\":\"theirs\",\"note\":\"x\"}").contains("not_found"))
        #expect(await api.call(tool: "get_bookmark", argumentsJSON: "{\"id\":\"theirs\"}").contains("not_found"))
        #expect(await api.call(tool: "file_in_space", argumentsJSON: "{\"ids\":[\"a\"],\"spaceId\":\"nowhere\"}").contains("space_not_found"))
        let filed = await api.call(tool: "file_in_space", argumentsJSON: "{\"ids\":[\"a\",\"a\",\" \",\"theirs\"],\"spaceId\":\"lab\"}")
        #expect(filed.contains("\"ok\":true"))
        #expect(library.filed == [["a"]])
        #expect(await api.call(tool: "save_bookmark", argumentsJSON: "{\"text\":\"   \"}").contains("invalid_arguments"))
        let tooLong = String(repeating: "n", count: AgentLimits.maxNoteCharacters + 1)
        #expect(await api.call(tool: "add_note", argumentsJSON: "{\"id\":\"a\",\"note\":\"\(tooLong)\"}").contains("invalid_arguments"))
        #expect(await api.call(tool: "set_read_later", argumentsJSON: "{\"id\":\"a\",\"later\":true}").contains("\"ok\":true"))
        #expect(library.later == ["a"])
        #expect(await api.call(tool: "save_research", argumentsJSON: "{\"question\":\"q\",\"answer\":\"\"}").contains("invalid_arguments"))
    }

    @Test("write tools stay refused while writes are off")
    func writesOff() async {
        let library = HardeningLibrary()
        let api = ListenerRig.makeAPI(library)
        for (tool, args) in [
            ("set_read_later", "{\"id\":\"a\"}"),
            ("file_in_space", "{\"ids\":[\"a\"]}"),
            ("add_note", "{\"id\":\"a\",\"note\":\"n\"}")
        ] {
            #expect(await api.call(tool: tool, argumentsJSON: args).contains("writes_disabled"))
        }
        #expect(library.filed.isEmpty && library.later.isEmpty)
    }

    // MARK: - Helpers

    private func object(_ reply: String?) throws -> [String: Any] {
        let text = try #require(reply)
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func code(_ reply: String?) throws -> Int? {
        (try object(reply)["error"] as? [String: Any])?["code"] as? Int
    }

    private func result(_ reply: String?) throws -> [String: Any] {
        try #require(try object(reply)["result"] as? [String: Any])
    }
}

// MARK: - Test doubles

/// Raw sends in these tests must not raise SIGPIPE when the listener hangs up first.
#if canImport(Darwin)
let testSendFlags: Int32 = 0
#else
let testSendFlags = Int32(MSG_NOSIGNAL)
#endif

final class HardeningLibrary: AgentLibrary, @unchecked Sendable {
    private let lock = NSLock()
    var writes = false
    var filed: [[String]] = []
    var later: [String] = []
    let rows: [Bookmark] = [
        Bookmark(id: "a", text: "alpha notes", createdAt: 2, userId: "me"),
        Bookmark(id: "b", text: "beta", createdAt: 1, userId: "me"),
        Bookmark(id: "theirs", text: "alpha elsewhere", createdAt: 3, userId: "someone-else")
    ]

    func currentUserId() async -> String? { "me" }
    func allBookmarks(userId: String) async -> [Bookmark] { rows.filter { $0.userId == userId } }
    func bookmark(id: String) async -> Bookmark? { rows.first { $0.id == id } }
    func embeddings(userId: String) async -> [(String, Data)] { [] }
    func embedQuery(_ query: String) async -> [Float]? { nil }
    var embeddingModelInstalled: Bool { false }
    func spaces(userId: String) async -> [Space] {
        [Space(id: "lab", userId: "me", name: "Lab", color: 0, icon: "folder", createdAt: 0)]
    }
    func writesAllowed() async -> Bool { writes }
    func xaiConfigured() async -> Bool { false }
    func secrets() async -> [String] { [] }
    func addBookmark(userId: String, text: String) async throws -> Bookmark {
        Bookmark(id: "manual_1", text: text, createdAt: 0, userId: userId)
    }
    func updateNotes(id: String, notes: String?) async {}
    func setFavorite(id: String, isFavorite: Bool) async {}
    func assignToSpace(ids: [String], spaceId: String?) async {
        lock.withLock { filed.append(ids) }
    }
    func setSavedForLater(id: String, isSavedForLater: Bool) async {
        lock.withLock { later.append(id) }
    }
    func saveResearch(_ card: ResearchCard) async throws {}
    func researchCard(id: String) async -> ResearchCard? { nil }
}

private struct SilentSynthesizer: ResearchSynthesizer {
    func brief(question: String, bookmarks: [Bookmark], privateMode: Bool, sources: [String]) async -> AgentToolResult {
        .failure(.modelUnavailable)
    }
}

private final class EchoTransport: AgentTransport, @unchecked Sendable {
    var calls = 0
    var reply = AgentToolResult.success("{}").jsonText()
    func perform(tool: String, argumentsJSON: String) async -> String {
        calls += 1
        return reply
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

final class ListenerRig: Sendable {
    let root: URL
    let socket: URL
    let api: LibraryAgentAPI
    let listener: AgentSocketListener

    init(readTimeout: TimeInterval = 2) throws {
        root = try Self.makeRoot()
        socket = root.appendingPathComponent("agent.sock")
        api = Self.makeAPI(HardeningLibrary())
        listener = AgentSocketListener(api: api, socketURL: socket, accessEnabled: { true }, token: { "tok" }, readTimeout: readTimeout)
        guard listener.start() else { throw RigError.bind }
    }

    enum RigError: Error { case bind }

    static func makeRoot() throws -> URL {
        // Short path: sockaddr_un caps socket paths near 104 bytes.
        let root = URL(fileURLWithPath: "/tmp/ch-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func makeAPI(_ library: HardeningLibrary) -> LibraryAgentAPI {
        LibraryAgentAPI(library: library, synthesizer: SilentSynthesizer(), privateContextBudget: 1_500, liveAllowed: { false })
    }

    func tearDown() {
        listener.stop()
        try? FileManager.default.removeItem(at: root)
    }

    func call(tool: String, arguments: String = "{}") throws -> String {
        let line = AgentLine.request(token: "tok", tool: tool, argumentsJSON: arguments)
        return try #require(Self.exchange(socket: socket, line: line, timeout: 5))
    }

    func raw(_ line: String, timeout: TimeInterval) throws -> String? {
        Self.exchange(socket: socket, line: line, timeout: timeout)
    }

    static func onThread<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            Thread { continuation.resume(returning: work()) }.start()
        }
    }

    /// Retries a refused connect the way `curio-mcp` does: macOS refuses Unix-socket connects
    /// once the listen backlog is full instead of queueing them.
    static func exchange(socket: URL, line: String, timeout: TimeInterval) -> String? {
        var fd: Int32 = -1
        for attempt in 0..<40 {
            fd = AgentSocketIO.openClient(at: socket)
            if fd >= 0 { break }
            usleep(useconds_t(min(200_000, 10_000 * (attempt + 1))))
        }
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        AgentSocketIO.setTimeouts(fd, read: timeout, write: timeout)
        // A refusal ("busy") can arrive before the request is written, so read even if the write failed.
        _ = AgentSocketIO.writeLine(line, fd: fd)
        return AgentSocketIO.readLine(fd: fd)
    }
}
