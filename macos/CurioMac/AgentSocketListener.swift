import Darwin
import Foundation

/// Accepts agent connections on the local socket. The process that owns SwiftData is this app;
/// `curio-mcp` only forwards stdio.
final class AgentSocketListener: @unchecked Sendable {
    private let api: LibraryAgentAPI
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var started = false

    init(api: LibraryAgentAPI) {
        self.api = api
    }

    func startIfEnabled() {
        lock.lock()
        let shouldStart = !started && MacAgentPreferences.accessEnabled()
        if shouldStart { started = true }
        lock.unlock()
        guard shouldStart else { return }
        Task.detached { [api] in
            let server = AgentSocketIO.openServer()
            guard server >= 0 else { return }
            while true {
                let client = accept(server, nil, nil)
                if client < 0 { continue }
                Task.detached {
                    await Self.handle(client: client, api: api)
                    close(client)
                }
            }
        }
    }

    private static func handle(client: Int32, api: LibraryAgentAPI) async {
        guard let line = AgentSocketIO.readLine(fd: client),
              let request = AgentLine.parseRequest(line) else { return }
        let admitted = AgentRequestGate.admit(
            presented: request.token,
            expected: MacAgentPreferences.token(),
            accessEnabled: MacAgentPreferences.accessEnabled()
        )
        let payload: String
        let tier: String
        if admitted {
            payload = await api.call(tool: request.tool, argumentsJSON: request.argumentsJSON)
            tier = (payload.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["tier"] as? String) ?? ""
        } else {
            payload = AgentToolResult.failure(.badToken).jsonText()
            tier = ""
        }
        let audit = AgentAudit.line(
            client: "mcp",
            tool: request.tool,
            argumentHash: AgentAudit.argumentHash(request.argumentsJSON),
            tier: tier
        )
        appendAudit(audit)
        AgentSocketIO.writeLine(payload, fd: client)
    }

    private static func appendAudit(_ line: String) {
        let url = AgentSocketPath.fileURL().deletingLastPathComponent().appendingPathComponent("agent-audit.log")
        let data = Data((line + "\n").utf8)
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
