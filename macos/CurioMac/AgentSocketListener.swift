import Darwin
import Foundation

/// Accepts agent connections on the local socket. The process that owns SwiftData is this app;
/// `curio-mcp` only forwards stdio. The socket stays up when agent access is off so a client
/// gets `bad_token` instead of "app not running". Each request still has to pass the gate.
final class AgentSocketListener: @unchecked Sendable {
    static let maxInFlight = 32
    static let maxAuditBytes = 1_000_000

    private let api: LibraryAgentAPI
    private let socketURL: URL
    private let accessEnabled: @Sendable () -> Bool
    private let token: @Sendable () -> String
    private let lock = NSLock()
    private let slotLock = NSLock()
    private let auditLock = NSLock()
    private var fd: Int32 = -1
    private var started = false
    private var inFlight = 0

    init(
        api: LibraryAgentAPI,
        socketURL: URL = AgentSocketPath.fileURL(),
        accessEnabled: @escaping @Sendable () -> Bool = { MacAgentPreferences.accessEnabled() },
        token: @escaping @Sendable () -> String = { MacAgentPreferences.token() }
    ) {
        self.api = api
        self.socketURL = socketURL
        self.accessEnabled = accessEnabled
        self.token = token
    }

    /// Binds the socket. A failed bind leaves the listener stopped so the caller can retry.
    @discardableResult
    func start() -> Bool {
        lock.lock()
        if started {
            let listening = fd >= 0
            lock.unlock()
            return listening
        }
        lock.unlock()

        let server = AgentSocketIO.openServer(at: socketURL)
        guard server >= 0 else { return false }

        lock.lock()
        if started {
            let listening = fd >= 0
            lock.unlock()
            close(server)
            return listening
        }
        fd = server
        started = true
        lock.unlock()

        Task.detached { [weak self] in
            await self?.acceptLoop(server)
        }
        return true
    }

    func stop() {
        lock.lock()
        let current = fd
        fd = -1
        started = false
        lock.unlock()
        if current >= 0 {
            shutdown(current, SHUT_RDWR)
            close(current)
        }
    }

    private func acceptLoop(_ server: Int32) async {
        var failures = 0
        while true {
            let client = accept(server, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                if errno == EBADF || errno == EINVAL || errno == ENOTSOCK { break }
                failures += 1
                if failures > 8 { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
                continue
            }
            failures = 0
            guard acquireSlot() else {
                close(client)
                continue
            }
            Task.detached { [weak self] in
                await self?.handle(client: client)
                close(client)
                self?.releaseSlot()
            }
        }
        finish(server: server)
    }

    /// Synchronous so the lock stays out of the async accept loop.
    private func finish(server: Int32) {
        lock.lock()
        let owned = fd == server
        if owned {
            fd = -1
            started = false
        }
        lock.unlock()
        if owned { close(server) }
    }

    private func handle(client: Int32) async {
        guard let line = AgentSocketIO.readLine(fd: client) else { return }
        guard let request = AgentLine.parseRequest(line) else {
            AgentSocketIO.writeLine(AgentToolResult.failure(.unknownTool, payload: "malformed").jsonText(), fd: client)
            return
        }
        let admitted = AgentRequestGate.admit(
            presented: request.token,
            expected: token(),
            accessEnabled: accessEnabled()
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

    private func acquireSlot() -> Bool {
        slotLock.lock()
        defer { slotLock.unlock() }
        if inFlight >= Self.maxInFlight { return false }
        inFlight += 1
        return true
    }

    private func releaseSlot() {
        slotLock.lock()
        inFlight = max(0, inFlight - 1)
        slotLock.unlock()
    }

    private func appendAudit(_ line: String) {
        auditLock.lock()
        defer { auditLock.unlock() }
        let url = socketURL.deletingLastPathComponent().appendingPathComponent("agent-audit.log")
        let data = Data((line + "\n").utf8)
        if FileManager.default.fileExists(atPath: url.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int, size > Self.maxAuditBytes {
            try? FileManager.default.removeItem(at: url)
        }
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
