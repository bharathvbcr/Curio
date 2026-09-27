import Foundation
import CryptoKit

/// Result a Curio agent tool returns to MCP and to the in-app desk. Failures are codes, not
/// sentences buried in a successful answer.
struct AgentToolResult: Sendable, Equatable, Codable {
    var ok: Bool
    var code: String?
    var payload: String
    var tier: String

    static func success(_ payload: String, tier: String = "") -> AgentToolResult {
        AgentToolResult(ok: true, code: nil, payload: payload, tier: tier)
    }

    static func failure(_ code: AgentFailure, payload: String = "") -> AgentToolResult {
        AgentToolResult(ok: false, code: code.rawValue, payload: payload, tier: "")
    }

    func jsonText() -> String {
        let object: [String: Any] = [
            "ok": ok,
            "code": code ?? "",
            "payload": payload,
            "tier": tier
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return "{\"ok\":false}" }
        return text
    }
}

enum AgentFailure: String, Sendable, Codable {
    case notSignedIn = "not_signed_in"
    case writesDisabled = "writes_disabled"
    case embeddingModelMissing = "embedding_model_missing"
    case indexEmpty = "index_empty"
    case keyMissing = "key_missing"
    case privateMode = "private_mode"
    case contextExceeded = "context_exceeded"
    case appUnavailable = "app_unavailable"
    case citationRejected = "citation_rejected"
    case modelUnavailable = "model_unavailable"
    case accessDisabled = "access_disabled"
    case badToken = "bad_token"
    case unknownTool = "unknown_tool"
    case notFound = "not_found"
    case invalidArguments = "invalid_arguments"
}

enum AgentRedactor {
    /// Replaces known secrets and bearer headers. Bookmark text is left intact.
    static func redact(_ text: String, secrets: [String]) -> String {
        var result = text
        for secret in secrets where secret.count >= 6 {
            result = result.replacingOccurrences(of: secret, with: "[redacted]")
        }
        if let regex = try? NSRegularExpression(pattern: "(?i)authorization:\\s*bearer\\s+\\S+", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "Authorization: [redacted]")
        }
        return result
    }
}

enum AgentRequestGate {
    /// A call is admitted only when agent access is on and the presented token matches the one
    /// the app generated. An empty expected token is a refusal.
    static func admit(presented: String, expected: String, accessEnabled: Bool) -> Bool {
        guard accessEnabled, !expected.isEmpty, !presented.isEmpty else { return false }
        return sameToken(presented, expected)
    }

    /// Byte-wise compare with no early exit, so a wrong token does not return faster
    /// when its first bytes differ.
    private static func sameToken(_ presented: String, _ expected: String) -> Bool {
        let left = Array(presented.utf8)
        let right = Array(expected.utf8)
        var diff: UInt8 = left.count == right.count ? 0 : 1
        let count = max(left.count, right.count)
        if count == 0 { return diff == 0 }
        for index in 0..<count {
            let l: UInt8 = index < left.count ? left[index] : 0
            let r: UInt8 = index < right.count ? right[index] : 0
            diff |= l ^ r
        }
        return diff == 0
    }
}

/// Newline JSON exchanged between `curio-mcp` and the Mac app. The app owns the library.
enum AgentLine {
    static func request(token: String, tool: String, argumentsJSON: String) -> String {
        let object: [String: Any] = ["token": token, "tool": tool, "arguments": argumentsJSON]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    static func parseRequest(_ line: String) -> (token: String, tool: String, argumentsJSON: String)? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = object["tool"] as? String else { return nil }
        let token = object["token"] as? String ?? ""
        let arguments = object["arguments"] as? String ?? "{}"
        return (token, tool, arguments)
    }
}

protocol AgentTransport: Sendable {
    func perform(tool: String, argumentsJSON: String) async -> String
}

/// MCP stdio framing. Speaks 2025-11-25 and negotiates down to the three earlier revisions a
/// client may ask for. Notifications and client responses get no reply. Tool calls, resource
/// reads, and prompts go to `transport` only after `gate` admits the client token.
struct MCPDispatcher: Sendable {
    static let supportedVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    /// JSON-RPC error codes. The -320xx range is this server's own.
    enum ErrorCode {
        static let parse = -32700
        static let invalidRequest = -32600
        static let methodNotFound = -32601
        static let invalidParams = -32602
        static let internalError = -32603
        static let unauthorized = -32001
        static let resourceNotFound = -32002
    }

    var gate: @Sendable () -> Bool
    var transport: any AgentTransport
    var serverName: String = "curio"
    var serverVersion: String = "1.0.0"

    /// The client's version when this server speaks it, otherwise the newest this server speaks.
    static func negotiatedVersion(_ requested: Any?) -> String {
        if let requested = requested as? String, supportedVersions.contains(requested) { return requested }
        return supportedVersions[0]
    }

    func handle(_ line: String) async -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard let data = trimmed.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return rpc(id: nil, code: ErrorCode.parse, message: "Parse error")
        }
        guard let object = parsed as? [String: Any] else {
            return rpc(id: nil, code: ErrorCode.invalidRequest, message: "Expected one JSON-RPC object; batches are not supported")
        }
        let id = object["id"]
        guard let method = object["method"] as? String, !method.isEmpty else {
            // A client response (result or error) needs no reply; anything else with an id is invalid.
            if id == nil || object["result"] != nil || object["error"] != nil { return nil }
            return rpc(id: Self.echoable(id), code: ErrorCode.invalidRequest, message: "Missing method")
        }
        guard let id else { return nil }
        guard Self.isValidId(id) else {
            return rpc(id: nil, code: ErrorCode.invalidRequest, message: "id must be a string or a number")
        }
        if let rawParams = object["params"], !(rawParams is [String: Any]), !(rawParams is NSNull) {
            return rpc(id: id, code: ErrorCode.invalidParams, message: "params must be an object")
        }
        let params = object["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return rpc(id: id, result: [
                "protocolVersion": Self.negotiatedVersion(params["protocolVersion"]),
                "capabilities": [
                    "tools": ["listChanged": false],
                    "resources": ["listChanged": false, "subscribe": false],
                    "prompts": ["listChanged": false]
                ],
                "serverInfo": ["name": serverName, "title": "Curio", "version": serverVersion],
                "instructions": MCPCatalog.instructions
            ])
        case "ping":
            return rpc(id: id, result: [:])
        case "tools/list":
            return rpc(id: id, result: ["tools": MCPCatalog.tools()])
        case "tools/call":
            guard gate() else {
                return rpc(id: id, result: MCPCatalog.errorContent(code: AgentFailure.badToken.rawValue, detail: "Agent access is off or the token does not match."))
            }
            guard let name = params["name"] as? String, !name.isEmpty else {
                return rpc(id: id, code: ErrorCode.invalidParams, message: "Missing tool name")
            }
            guard MCPCatalog.toolNames.contains(name) else {
                return rpc(id: id, code: ErrorCode.invalidParams, message: "Unknown tool: \(name)")
            }
            if let rawArguments = params["arguments"], !(rawArguments is [String: Any]), !(rawArguments is NSNull) {
                return rpc(id: id, code: ErrorCode.invalidParams, message: "arguments must be an object")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            if let problem = MCPCatalog.validate(tool: name, arguments: arguments) {
                return rpc(id: id, result: MCPCatalog.errorContent(code: AgentFailure.invalidArguments.rawValue, detail: problem))
            }
            let argumentsJSON = MCPCatalog.jsonText(arguments)
            let payload = await transport.perform(tool: name, argumentsJSON: argumentsJSON.isEmpty ? "{}" : argumentsJSON)
            return rpc(id: id, result: MCPCatalog.toolContent(payload))
        case "resources/list":
            return rpc(id: id, result: ["resources": MCPCatalog.resources()])
        case "resources/templates/list":
            return rpc(id: id, result: ["resourceTemplates": MCPCatalog.resourceTemplates()])
        case "prompts/list":
            return rpc(id: id, result: ["prompts": MCPCatalog.prompts()])
        case "resources/read":
            guard gate() else {
                return rpc(id: id, code: ErrorCode.unauthorized, message: AgentFailure.badToken.rawValue)
            }
            guard let uri = params["uri"] as? String, !uri.isEmpty else {
                return rpc(id: id, code: ErrorCode.invalidParams, message: "Missing uri")
            }
            let payload = await transport.perform(tool: "read_resource", argumentsJSON: MCPCatalog.jsonText(["uri": uri, "name": uri]))
            switch MCPCatalog.unwrap(payload) {
            case .success(let text):
                return rpc(id: id, result: ["contents": [["uri": uri, "mimeType": "application/json", "text": text]]])
            case .failure(let failure):
                let code = failure.code == AgentFailure.notFound.rawValue || failure.code == AgentFailure.unknownTool.rawValue
                    ? ErrorCode.resourceNotFound
                    : (failure.code == AgentFailure.badToken.rawValue ? ErrorCode.unauthorized : ErrorCode.internalError)
                return rpc(id: id, code: code, message: failure.message, data: ["uri": uri, "code": failure.code])
            }
        case "prompts/get":
            guard gate() else {
                return rpc(id: id, code: ErrorCode.unauthorized, message: AgentFailure.badToken.rawValue)
            }
            guard let name = params["name"] as? String, !name.isEmpty else {
                return rpc(id: id, code: ErrorCode.invalidParams, message: "Missing prompt name")
            }
            guard MCPCatalog.promptNames.contains(name) else {
                return rpc(id: id, code: ErrorCode.invalidParams, message: "Unknown prompt: \(name)")
            }
            var arguments: [String: Any] = ["name": name, "uri": name]
            if let extra = params["arguments"] as? [String: Any] {
                arguments["arguments"] = extra
            }
            let payload = await transport.perform(tool: "get_prompt", argumentsJSON: MCPCatalog.jsonText(arguments))
            switch MCPCatalog.unwrap(payload) {
            case .success(let text):
                return rpc(id: id, result: ["description": name, "messages": [["role": "user", "content": ["type": "text", "text": text]]]])
            case .failure(let failure):
                return rpc(id: id, code: failure.code == AgentFailure.badToken.rawValue ? ErrorCode.unauthorized : ErrorCode.internalError,
                           message: failure.message, data: ["code": failure.code])
            }
        default:
            return rpc(id: id, code: ErrorCode.methodNotFound, message: "Method not found: \(method)")
        }
    }

    private static func isValidId(_ id: Any) -> Bool {
        if id is String || id is NSNull { return true }
        if let number = id as? NSNumber { return String(cString: number.objCType) != "c" }
        return false
    }

    private static func echoable(_ id: Any?) -> Any? {
        guard let id, isValidId(id) else { return nil }
        return id
    }

    private func rpc(id: Any?, result: [String: Any]) -> String {
        let object: [String: Any] = ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
        return encode(object)
    }

    private func rpc(id: Any?, code: Int, message: String, data: [String: Any]? = nil) -> String {
        var error: [String: Any] = ["code": code, "message": message]
        if let data { error["data"] = data }
        let object: [String: Any] = ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": error]
        return encode(object)
    }

    private func encode(_ object: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: object),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Could not encode the response"}}"#
    }
}

enum MCPCatalog {
    static let instructions = """
    Curio is the user's bookmark library on this Mac. Read tools never leave the Mac. \
    research_topic stays private unless the user turned on live research in Curio's Agent settings. \
    Write tools (save_bookmark, add_note, set_favorite, set_read_later, file_in_space, save_research) \
    fail with writes_disabled until the user allows changes. Cite bookmarks by the ids the tools return.
    """

    /// One advertised tool. `required` names keys that must be present; `nullable` keys may be JSON null.
    struct ToolSpec {
        var name: String
        var title: String
        var description: String
        var properties: [(String, [String: Any])]
        var required: [String] = []
        var nullable: [String] = []
        var readOnly: Bool
        var idempotent: Bool = true
        var openWorld: Bool = false
    }

    private static func string(_ description: String) -> [String: Any] { ["type": "string", "description": description] }
    private static func limit(_ fallback: Int) -> [String: Any] {
        ["type": "integer", "minimum": 1, "maximum": 50, "default": fallback, "description": "Most results to return (1–50)."]
    }
    private static func ids(_ description: String) -> [String: Any] {
        ["type": "array", "items": ["type": "string"], "description": description]
    }

    static func specs() -> [ToolSpec] { [
        ToolSpec(name: "search_bookmarks", title: "Search bookmarks",
                 description: "Keyword search across text, title, summary, OCR, tags, and notes. Newest first.",
                 properties: [("query", string("Words to look for. Empty returns the newest bookmarks.")), ("limit", limit(10))],
                 readOnly: true),
        ToolSpec(name: "semantic_search", title: "Search by meaning",
                 description: "Meaning search over on-device embeddings. Fails with embedding_model_missing or index_empty instead of guessing.",
                 properties: [("query", string("What to look for.")), ("limit", limit(10))],
                 required: ["query"], readOnly: true),
        ToolSpec(name: "get_bookmark", title: "Get a bookmark",
                 description: "Full bookmark record by id.",
                 properties: [("id", string("Bookmark id."))], required: ["id"], readOnly: true),
        ToolSpec(name: "list_spaces", title: "List spaces",
                 description: "Spaces (collections) in the library with their ids and counts.",
                 properties: [], readOnly: true),
        ToolSpec(name: "list_space_bookmarks", title: "List a space",
                 description: "Bookmarks filed in one space.",
                 properties: [("spaceId", string("Space id from list_spaces."))], required: ["spaceId"], readOnly: true),
        ToolSpec(name: "related_bookmarks", title: "Related bookmarks",
                 description: "Nearest neighbors of one bookmark by embedding.",
                 properties: [("id", string("Bookmark id.")), ("limit", limit(10))], required: ["id"], readOnly: true),
        ToolSpec(name: "reading_queue", title: "Reading queue",
                 description: "Saved-for-later bookmarks, then favorites.",
                 properties: [("limit", limit(20))], readOnly: true),
        ToolSpec(name: "library_overview", title: "Library overview",
                 description: "Counts, unenriched items, and embedding-model state.",
                 properties: [], readOnly: true),
        ToolSpec(name: "export_citations", title: "Export citations",
                 description: "BibTeX, RIS, CSL-JSON, or Markdown for the given ids (all bookmarks when ids is empty).",
                 properties: [
                    ("ids", ids("Bookmark ids. Empty exports the whole library.")),
                    ("format", ["type": "string", "enum": ["bibtex", "ris", "csl-json", "markdown"], "default": "bibtex"])
                 ], readOnly: true),
        ToolSpec(name: "research_topic", title: "Research a topic",
                 description: "Grounded brief from the library. Private (on this Mac) by default; live sources need the user's switch and an xAI key.",
                 properties: [
                    ("question", string("The question to answer.")),
                    ("private", ["type": "boolean", "default": true, "description": "Keep the brief on this Mac."]),
                    ("sources", ["type": "array", "items": ["type": "string", "enum": ["library", "web", "x", "news"]], "description": "Live sources beyond the library. Requires private = false."]),
                    ("limit", limit(8))
                 ], required: ["question"], readOnly: true, idempotent: false, openWorld: true),
        ToolSpec(name: "save_bookmark", title: "Save a bookmark",
                 description: "Save text or a link as a new bookmark. Requires agent writes.",
                 properties: [("text", string("Text or URL to save."))], required: ["text"], readOnly: false, idempotent: false),
        ToolSpec(name: "add_note", title: "Set a note",
                 description: "Set a bookmark's note. An empty note clears it. Requires agent writes.",
                 properties: [("id", string("Bookmark id.")), ("note", string("Note text."))], required: ["id", "note"], readOnly: false),
        ToolSpec(name: "set_favorite", title: "Star a bookmark",
                 description: "Star or unstar a bookmark. Requires agent writes.",
                 properties: [("id", string("Bookmark id.")), ("favorite", ["type": "boolean", "default": true])], required: ["id"], readOnly: false),
        ToolSpec(name: "set_read_later", title: "Read later",
                 description: "Add a bookmark to Read Later or take it off. Requires agent writes.",
                 properties: [("id", string("Bookmark id.")), ("later", ["type": "boolean", "default": true])], required: ["id"], readOnly: false),
        ToolSpec(name: "file_in_space", title: "File into a space",
                 description: "File bookmarks into a space. Omit spaceId (or send null) to unfile. Requires agent writes.",
                 properties: [("ids", ids("Bookmark ids.")), ("spaceId", ["type": ["string", "null"], "description": "Space id from list_spaces."])],
                 required: ["ids"], nullable: ["spaceId"], readOnly: false),
        ToolSpec(name: "save_research", title: "Save research",
                 description: "Store a research brief the user can read later. Requires agent writes.",
                 properties: [("question", string("The question.")), ("answer", string("The brief.")), ("ids", ids("Bookmark ids the answer cites."))],
                 required: ["question", "answer"], readOnly: false, idempotent: false)
    ] }

    static var toolNames: Set<String> { Set(specs().map(\.name)) }

    static func tools() -> [[String: Any]] {
        specs().map { spec in
            var properties: [String: Any] = [:]
            for (key, schema) in spec.properties { properties[key] = schema }
            var schema: [String: Any] = ["type": "object", "properties": properties]
            if !spec.required.isEmpty { schema["required"] = spec.required }
            return [
                "name": spec.name,
                "title": spec.title,
                "description": spec.description,
                "inputSchema": schema,
                "annotations": [
                    "title": spec.title,
                    "readOnlyHint": spec.readOnly,
                    "destructiveHint": false,
                    "idempotentHint": spec.idempotent,
                    "openWorldHint": spec.openWorld
                ]
            ]
        }
    }

    /// Checks presence and JSON type of each declared argument. Unknown keys pass through.
    /// Returns a sentence an agent can act on, or nil when the call is well formed.
    static func validate(tool: String, arguments: [String: Any]) -> String? {
        guard let spec = specs().first(where: { $0.name == tool }) else { return "Unknown tool: \(tool)" }
        for key in spec.required {
            guard let value = arguments[key], !(value is NSNull) || spec.nullable.contains(key) else {
                return "\(key) is required."
            }
        }
        for (key, schema) in spec.properties {
            guard let value = arguments[key] else { continue }
            if value is NSNull {
                if spec.nullable.contains(key) || !spec.required.contains(key) { continue }
                return "\(key) cannot be null."
            }
            let type = (schema["type"] as? String) ?? ((schema["type"] as? [String])?.first { $0 != "null" } ?? "")
            switch type {
            case "string":
                guard value is String else { return "\(key) must be a string." }
                if let allowed = schema["enum"] as? [String], let text = value as? String,
                   !allowed.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) {
                    return "\(key) must be one of: \(allowed.joined(separator: ", "))."
                }
            case "integer":
                guard let number = value as? NSNumber, String(cString: number.objCType) != "c",
                      number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue else {
                    return "\(key) must be a whole number."
                }
            case "boolean":
                guard let number = value as? NSNumber, String(cString: number.objCType) == "c" else {
                    return "\(key) must be true or false."
                }
            case "array":
                guard let items = value as? [Any], items.allSatisfy({ $0 is String }) else {
                    return "\(key) must be an array of strings."
                }
            default:
                continue
            }
        }
        return nil
    }

    static func resources() -> [[String: Any]] { [
        ["uri": "curio://library/recent", "name": "recent", "title": "Recent bookmarks", "mimeType": "application/json"]
    ] }

    static func resourceTemplates() -> [[String: Any]] { [
        ["uriTemplate": "curio://bookmark/{id}", "name": "bookmark", "title": "A bookmark", "mimeType": "application/json"],
        ["uriTemplate": "curio://space/{id}", "name": "space", "title": "Bookmarks in a space", "mimeType": "application/json"],
        ["uriTemplate": "curio://research/{id}", "name": "research", "title": "A saved research brief", "mimeType": "application/json"]
    ] }

    static let promptNames: Set<String> = ["research-brief", "compare-sources", "reading-queue"]

    static func prompts() -> [[String: Any]] { [
        ["name": "research-brief", "title": "Research brief", "description": "Ask Curio for a grounded brief on a topic.",
         "arguments": [["name": "topic", "description": "What to research.", "required": false]]],
        ["name": "compare-sources", "title": "Compare sources", "description": "Compare bookmarks the user names.",
         "arguments": [["name": "topic", "description": "What to compare them on.", "required": false]]],
        ["name": "reading-queue", "title": "Reading queue", "description": "Summarize the reading queue."]
    ] }

    /// Splits an `AgentToolResult` line into its payload or its failure. A line that is not
    /// a result passes through as text.
    static func unwrap(_ payload: String) -> Result<String, UnwrapError> {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = object["ok"] as? Bool else {
            return .success(payload)
        }
        let inner = object["payload"] as? String ?? ""
        if ok { return .success(inner) }
        let code = (object["code"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "failed"
        return .failure(UnwrapError(code: code, message: inner.isEmpty ? code : inner))
    }

    struct UnwrapError: Error, Equatable {
        var code: String
        var message: String
    }

    static func toolContent(_ payload: String) -> [String: Any] {
        let isError: Bool
        if let data = payload.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ok = object["ok"] as? Bool {
            isError = !ok
        } else {
            isError = false
        }
        return [
            "content": [["type": "text", "text": payload]],
            "isError": isError
        ]
    }

    static func errorContent(code: String, detail: String) -> [String: Any] {
        let payload = jsonText(["ok": false, "code": code, "payload": detail, "tier": ""])
        return [
            "content": [["type": "text", "text": payload]],
            "isError": true
        ]
    }

    static func jsonText(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
}

enum AgentSocketPath {
    static func fileURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("com.curio.mac", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        // Only this user may reach the socket or read the audit log beside it.
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        return directory.appendingPathComponent("agent.sock")
    }
}

enum AgentAudit {
    static func argumentHash(_ json: String) -> String {
        let digest = SHA256.hash(data: Data(json.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Tab-separated: time, client, tool, argument hash, tier, outcome (`ok` or a failure code).
    static func line(client: String, tool: String, argumentHash: String, tier: String, outcome: String = "", at: Date = Date()) -> String {
        let stamp = ISO8601DateFormatter().string(from: at)
        return "\(stamp)\t\(client)\t\(tool)\t\(argumentHash)\t\(tier)\t\(outcome)"
    }
}

/// Mac-only switches. Defaults are off. The desk may listen on the local socket either way;
/// a call is admitted only after the user turns access on and presents the minted token.
/// iOS keeps its own assistant-write default and does not read these keys.
enum MacAgentPreferences {
    static let accessKey = "mac_agent_access_enabled"
    static let writesKey = "mac_agent_writes_allowed"
    static let tokenKey = "mac_agent_token"
    static let liveKey = "mac_agent_live_research"

    static func accessEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: accessKey) as? Bool ?? false
    }

    static func writesAllowed(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: writesKey) as? Bool ?? false
    }

    static func liveResearchAllowed(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: liveKey) as? Bool ?? false
    }

    static func token(_ defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: tokenKey) ?? ""
    }

    static func enableAccess(_ defaults: UserDefaults = .standard) -> String {
        defaults.set(true, forKey: accessKey)
        if token(defaults).isEmpty {
            defaults.set(UUID().uuidString, forKey: tokenKey)
        }
        return token(defaults)
    }
}

/// Where the embedded `curio-mcp` helper lives, and the client config that points at it.
enum MacAgentInstall {
    static let helperName = "curio-mcp"

    /// Prefers `Contents/MacOS`, then the legacy Resources copy XcodeGen used to emit.
    static func helperURL(
        bundleURL: URL,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        let relative = [
            "Contents/MacOS/\(helperName)",
            "Contents/Resources/\(helperName)"
        ]
        for suffix in relative {
            let url = bundleURL.appendingPathComponent(suffix)
            if isExecutable(url.path) { return url }
        }
        return nil
    }

    static func configuration(
        bundleURL: URL,
        token: String,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String {
        let binary = helperURL(bundleURL: bundleURL, isExecutable: isExecutable)?.path
            ?? bundleURL.appendingPathComponent("Contents/MacOS/\(helperName)").path
        let object: [String: Any] = [
            "mcpServers": [
                "curio": [
                    "command": binary,
                    "env": ["CURIO_AGENT_TOKEN": token]
                ]
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

/// Walks up from a helper executable to the `.app` bundle that contains it.
enum AgentAppLocator {
    static func appBundle(containing executable: URL) -> URL? {
        var url = executable.resolvingSymlinksInPath().standardizedFileURL
        if url.pathExtension != "app" {
            url.deleteLastPathComponent()
        }
        for _ in 0..<8 {
            if url.pathExtension == "app" { return url }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return nil }
            url = parent
        }
        return nil
    }
}
