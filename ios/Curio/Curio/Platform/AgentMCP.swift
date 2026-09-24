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
        guard accessEnabled, !expected.isEmpty else { return false }
        return presented == expected
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

/// MCP 2025-11-25 stdio framing. Notifications get no response. Tool calls go to `transport`
/// only after `gate` admits the client token.
struct MCPDispatcher: Sendable {
    var gate: @Sendable () -> Bool
    var transport: any AgentTransport
    var serverName: String = "curio"
    var serverVersion: String = "1.0.0"

    func handle(_ line: String) async -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = object["method"] as? String else {
            return nil
        }
        let id = object["id"]
        if id == nil {
            return nil
        }
        switch method {
        case "initialize":
            return rpc(id: id, result: [
                "protocolVersion": "2025-11-25",
                "capabilities": [
                    "tools": ["listChanged": false],
                    "resources": ["listChanged": false],
                    "prompts": ["listChanged": false]
                ],
                "serverInfo": ["name": serverName, "version": serverVersion]
            ])
        case "ping":
            return rpc(id: id, result: [:])
        case "tools/list":
            return rpc(id: id, result: ["tools": MCPCatalog.tools()])
        case "tools/call":
            guard gate() else {
                return rpc(id: id, result: MCPCatalog.errorContent(code: AgentFailure.badToken.rawValue, detail: "Agent access is off or the token does not match."))
            }
            let params = object["params"] as? [String: Any] ?? [:]
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let argumentsJSON = (try? JSONSerialization.data(withJSONObject: arguments)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            let payload = await transport.perform(tool: name, argumentsJSON: argumentsJSON)
            return rpc(id: id, result: MCPCatalog.toolContent(payload))
        case "resources/list":
            return rpc(id: id, result: ["resources": MCPCatalog.resources()])
        case "prompts/list":
            return rpc(id: id, result: ["prompts": MCPCatalog.prompts()])
        case "resources/read", "prompts/get":
            guard gate() else {
                return rpc(id: id, error: AgentFailure.badToken.rawValue)
            }
            let params = object["params"] as? [String: Any] ?? [:]
            let uri = (params["uri"] as? String) ?? (params["name"] as? String) ?? ""
            let payload = await transport.perform(tool: method == "resources/read" ? "read_resource" : "get_prompt", argumentsJSON: "{\"uri\":\"\(uri)\"}")
            if method == "resources/read" {
                return rpc(id: id, result: ["contents": [["uri": uri, "mimeType": "application/json", "text": payload]]])
            }
            return rpc(id: id, result: ["description": uri, "messages": [["role": "user", "content": ["type": "text", "text": payload]]]])
        default:
            return rpc(id: id, error: "method_not_found")
        }
    }

    private func rpc(id: Any?, result: [String: Any]) -> String {
        let object: [String: Any] = ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
        return encode(object)
    }

    private func rpc(id: Any?, error: String) -> String {
        let object: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": ["code": -32601, "message": error]
        ]
        return encode(object)
    }

    private func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
}

enum MCPCatalog {
    static func tools() -> [[String: Any]] { [
        tool("search_bookmarks", "Keyword search across text, title, summary, OCR, tags, and notes. Limit 1–50."),
        tool("semantic_search", "Meaning search over on-device embeddings. Errors when the model or index is missing."),
        tool("get_bookmark", "Full bookmark record by id."),
        tool("list_spaces", "Spaces in the library."),
        tool("list_space_bookmarks", "Bookmarks filed in a space."),
        tool("related_bookmarks", "Nearest neighbors of one bookmark."),
        tool("reading_queue", "Saved-for-later, then favorites."),
        tool("library_overview", "Counts, unenriched items, and embedding-model state."),
        tool("export_citations", "BibTeX, RIS, CSL-JSON, or Markdown for bookmark ids."),
        tool("research_topic", "Grounded brief. Private Apple Intelligence by default."),
        tool("save_bookmark", "Save text. Requires agent writes."),
        tool("add_note", "Set or clear a note. Requires agent writes."),
        tool("set_favorite", "Star or unstar. Requires agent writes."),
        tool("file_in_space", "File bookmarks into a space. Requires agent writes."),
        tool("save_research", "Store a research brief. Requires agent writes.")
    ] }

    static func resources() -> [[String: Any]] { [
        ["uri": "curio://library/recent", "name": "recent", "mimeType": "application/json"],
        ["uri": "curio://bookmark/{id}", "name": "bookmark", "mimeType": "application/json"],
        ["uri": "curio://space/{id}", "name": "space", "mimeType": "application/json"],
        ["uri": "curio://research/{id}", "name": "research", "mimeType": "application/json"]
    ] }

    static func prompts() -> [[String: Any]] { [
        ["name": "research-brief", "description": "Ask Curio for a grounded brief on a topic."],
        ["name": "compare-sources", "description": "Compare bookmarks the user names."],
        ["name": "reading-queue", "description": "Summarize the reading queue."]
    ] }

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
        let payload = "{\"ok\":false,\"code\":\"\(code)\",\"payload\":\"\(detail)\"}"
        return [
            "content": [["type": "text", "text": payload]],
            "isError": true
        ]
    }

    private static func tool(_ name: String, _ description: String) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": ["type": "object", "properties": [:], "additionalProperties": true]
        ]
    }
}

enum AgentSocketPath {
    static func fileURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("com.curio.mac", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("agent.sock")
    }
}

enum AgentAudit {
    static func argumentHash(_ json: String) -> String {
        let digest = SHA256.hash(data: Data(json.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func line(client: String, tool: String, argumentHash: String, tier: String, at: Date = Date()) -> String {
        let stamp = ISO8601DateFormatter().string(from: at)
        return "\(stamp)\t\(client)\t\(tool)\t\(argumentHash)\t\(tier)"
    }
}

/// Mac-only switches. Defaults are off so a fresh install does not publish the agent listener.
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
