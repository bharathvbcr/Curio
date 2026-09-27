import Foundation

/// One line of the agent audit log. Arguments are stored only as a hash.
struct AgentAuditEntry: Equatable, Sendable {
    var stamp: String
    var client: String
    var tool: String
    var argumentHash: String
    var tier: String
    var outcome: String

    var date: Date? { ISO8601DateFormatter().date(from: stamp) }

    var succeeded: Bool { outcome == "ok" || outcome.isEmpty }

    /// Parses a tab-separated audit line. Older five-column lines have no outcome.
    init?(line: String) {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5, !parts[0].isEmpty, !parts[2].isEmpty else { return nil }
        stamp = parts[0]
        client = parts[1]
        tool = parts[2]
        argumentHash = parts[3]
        tier = parts[4]
        outcome = parts.count > 5 ? parts[5] : ""
    }
}

/// Append-only audit log with one rotated generation. Writes never throw to the caller.
final class AgentAuditLog: @unchecked Sendable {
    static let defaultMaxBytes = 1_000_000

    let url: URL
    let maxBytes: Int
    private let lock = NSLock()

    init(url: URL, maxBytes: Int = AgentAuditLog.defaultMaxBytes) {
        self.url = url
        self.maxBytes = max(1_024, maxBytes)
    }

    var rotatedURL: URL { url.appendingPathExtension("1") }

    func append(_ line: String) {
        let clean = line.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        let data = Data((clean + "\n").utf8)
        lock.lock()
        defer { lock.unlock() }
        let manager = FileManager.default
        if let size = (try? manager.attributesOfItem(atPath: url.path))?[.size] as? Int,
           size + data.count > maxBytes {
            try? manager.removeItem(at: rotatedURL)
            try? manager.moveItem(at: url, to: rotatedURL)
        }
        if manager.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
            try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    /// Newest first, across the live and rotated files. Malformed lines are skipped.
    func recent(limit: Int = 200) -> [AgentAuditEntry] {
        guard limit > 0 else { return [] }
        lock.lock()
        let live = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let rotated = (try? String(contentsOf: rotatedURL, encoding: .utf8)) ?? ""
        lock.unlock()
        var entries: [AgentAuditEntry] = []
        for text in [live, rotated] {
            for line in text.split(separator: "\n").reversed() {
                if let entry = AgentAuditEntry(line: String(line)) {
                    entries.append(entry)
                    if entries.count >= limit { return entries }
                }
            }
        }
        return entries
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: rotatedURL)
    }
}

/// Plain-language labels for the audit viewer.
enum AgentActivityFormat {
    static func toolLabel(_ tool: String) -> String {
        switch tool {
        case "search_bookmarks": return "Searched bookmarks"
        case "semantic_search": return "Searched by meaning"
        case "get_bookmark": return "Read a bookmark"
        case "list_spaces": return "Listed spaces"
        case "list_space_bookmarks": return "Read a space"
        case "related_bookmarks": return "Found related bookmarks"
        case "reading_queue": return "Read the reading queue"
        case "library_overview": return "Read the library overview"
        case "export_citations": return "Exported citations"
        case "research_topic": return "Researched a topic"
        case "save_bookmark": return "Saved a bookmark"
        case "add_note": return "Changed a note"
        case "set_favorite": return "Starred or unstarred"
        case "set_read_later": return "Changed Read Later"
        case "file_in_space": return "Filed bookmarks"
        case "save_research": return "Saved research"
        case "read_resource": return "Read a resource"
        case "get_prompt": return "Loaded a prompt"
        default: return tool
        }
    }

    static func outcomeLabel(_ outcome: String) -> String {
        switch outcome {
        case "", "ok": return "Done"
        case AgentFailure.badToken.rawValue: return "Refused: token or access off"
        case AgentFailure.writesDisabled.rawValue: return "Refused: changes are off"
        case AgentFailure.notSignedIn.rawValue: return "Refused: not signed in"
        case "malformed": return "Refused: malformed request"
        default: return outcome.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Keeps a client-supplied tool name from breaking the tab-separated log.
    static func sanitizedTool(_ raw: String) -> String {
        let cleaned = raw.unicodeScalars.map { scalar -> Character in
            CharacterSet.controlCharacters.contains(scalar) || scalar == "\t" ? " " : Character(scalar)
        }
        let text = String(cleaned).trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return "(none)" }
        return text.count > 64 ? String(text.prefix(64)) + "…" : text
    }
}
