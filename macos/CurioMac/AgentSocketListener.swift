import Darwin
import Foundation

/// Accepts agent connections on the local socket. The process that owns SwiftData is this app;
/// `curio-mcp` only forwards stdio. The socket stays up when agent access is off so a client
/// gets `bad_token` instead of "app not running". Each request still has to pass the gate.
///
/// Blocking socket calls run on a dedicated accept thread and one short-lived thread per
/// connection (at most `maxInFlight`), never on the Swift concurrency pool, so a slow or silent
/// client cannot starve the app's actors. Only the tool call itself runs as a task.
final class AgentSocketListener: @unchecked Sendable {
    static let maxInFlight = 32
    static let maxRequestBytes = 1_000_000
    static let requestReadTimeout: TimeInterval = 5
    static let responseWriteTimeout: TimeInterval = 10
    static let acceptPollMillis: Int32 = 200

    private let api: LibraryAgentAPI
    private let socketURL: URL
    private let accessEnabled: @Sendable () -> Bool
    private let token: @Sendable () -> String
    let auditLog: AgentAuditLog
    private let readTimeout: TimeInterval
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var generation = 0
    private var socketIdentity: (dev: UInt64, ino: UInt64)?
    private var inFlight = 0

    init(
        api: LibraryAgentAPI,
        socketURL: URL = AgentSocketPath.fileURL(),
        accessEnabled: @escaping @Sendable () -> Bool = { MacAgentPreferences.accessEnabled() },
        token: @escaping @Sendable () -> String = { MacAgentPreferences.token() },
        auditLog: AgentAuditLog? = nil,
        readTimeout: TimeInterval = AgentSocketListener.requestReadTimeout
    ) {
        self.readTimeout = readTimeout
        self.api = api
        self.socketURL = socketURL
        self.accessEnabled = accessEnabled
        self.token = token
        self.auditLog = auditLog ?? AgentAuditLog(
            url: socketURL.deletingLastPathComponent().appendingPathComponent("agent-audit.log")
        )
    }

    var isListening: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fd >= 0
    }

    var activeConnections: Int {
        lock.lock()
        defer { lock.unlock() }
        return inFlight
    }

    /// Binds the socket. A failed bind leaves the listener stopped so the caller can retry.
    @discardableResult
    func start() -> Bool {
        lock.lock()
        if fd >= 0 {
            lock.unlock()
            return true
        }
        let server = AgentSocketIO.openServer(at: socketURL)
        guard server >= 0 else {
            lock.unlock()
            return false
        }
        fd = server
        generation += 1
        let ticket = generation
        socketIdentity = Self.identity(of: socketURL.path)
        lock.unlock()

        let thread = Thread { [weak self] in
            self?.acceptLoop(server, ticket: ticket)
        }
        thread.name = "com.curio.agent.accept"
        thread.qualityOfService = .utility
        thread.start()
        return true
    }

    /// Stops accepting. The accept thread closes its own descriptor, so the number cannot be
    /// reused under it. The socket file is removed only while it is still the one this bound.
    func stop() {
        lock.lock()
        let server = fd
        let identity = socketIdentity
        fd = -1
        generation += 1
        socketIdentity = nil
        lock.unlock()
        guard server >= 0 else { return }
        shutdown(server, Int32(SHUT_RDWR))
        if let identity, let current = Self.identity(of: socketURL.path),
           current.dev == identity.dev, current.ino == identity.ino {
            unlink(socketURL.path)
        }
    }

    private func isCurrent(_ ticket: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == ticket
    }

    private func acceptLoop(_ server: Int32, ticket: Int) {
        var failures = 0
        while isCurrent(ticket) {
            var poller = pollfd(fd: server, events: Int16(POLLIN), revents: 0)
            let ready = poll(&poller, 1, Self.acceptPollMillis)
            if ready < 0 {
                if errno == EINTR { continue }
                break
            }
            if ready == 0 { continue }
            guard isCurrent(ticket) else { break }
            if poller.revents & Int16(POLLNVAL | POLLERR | POLLHUP) != 0 && poller.revents & Int16(POLLIN) == 0 {
                break
            }
            let client = accept(server, nil, nil)
            if client < 0 {
                if errno == EINTR || errno == EAGAIN || errno == ECONNABORTED { continue }
                if errno == EBADF || errno == EINVAL || errno == ENOTSOCK { break }
                failures += 1
                if failures > 8 { break }
                usleep(50_000)
                continue
            }
            failures = 0
            AgentSocketIO.prepareAccepted(client)
            guard acquireSlot() else {
                AgentSocketIO.setTimeouts(client, read: 0, write: 0.2)
                AgentSocketIO.writeLine(AgentToolResult.failure(.appUnavailable, payload: "busy").jsonText(), fd: client)
                close(client)
                continue
            }
            AgentSocketIO.setTimeouts(client, read: readTimeout, write: Self.responseWriteTimeout)
            let worker = Thread { [self] in serve(client) }
            worker.name = "com.curio.agent.connection"
            worker.stackSize = 512 * 1024
            worker.start()
        }
        lock.lock()
        if fd == server { fd = -1 }
        lock.unlock()
        close(server)
    }

    /// Runs on the connection's own thread: read (bounded by the read timeout), wait for the
    /// tool task, write (bounded by the write timeout), close.
    private func serve(_ client: Int32) {
        defer { finish(client) }
        let deadline = Date().addingTimeInterval(readTimeout)
        guard let line = AgentSocketIO.readLine(fd: client, maxBytes: Self.maxRequestBytes, deadline: deadline) else { return }
        let reply = ReplyBox()
        let done = DispatchSemaphore(value: 0)
        Task.detached { [self] in
            reply.value = await respond(to: line)
            done.signal()
        }
        done.wait()
        AgentSocketIO.writeLine(reply.value, fd: client)
    }

    private func finish(_ client: Int32) {
        close(client)
        releaseSlot()
    }

    /// Everything a request line turns into, without touching the socket.
    func respond(to line: String) async -> String {
        guard let request = AgentLine.parseRequest(line) else {
            audit(tool: "(malformed)", arguments: "", tier: "", outcome: "malformed")
            return AgentToolResult.failure(.unknownTool, payload: "malformed").jsonText()
        }
        let admitted = AgentRequestGate.admit(
            presented: request.token,
            expected: token(),
            accessEnabled: accessEnabled()
        )
        guard admitted else {
            audit(tool: request.tool, arguments: request.argumentsJSON, tier: "", outcome: AgentFailure.badToken.rawValue)
            return AgentToolResult.failure(.badToken).jsonText()
        }
        let payload = await api.call(tool: request.tool, argumentsJSON: request.argumentsJSON)
        let object = payload.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let tier = object?["tier"] as? String ?? ""
        let ok = object?["ok"] as? Bool ?? false
        let code = object?["code"] as? String ?? ""
        audit(tool: request.tool, arguments: request.argumentsJSON, tier: tier, outcome: ok ? "ok" : (code.isEmpty ? "failed" : code))
        return payload
    }

    private func audit(tool: String, arguments: String, tier: String, outcome: String) {
        auditLog.append(AgentAudit.line(
            client: "mcp",
            tool: AgentActivityFormat.sanitizedTool(tool),
            argumentHash: AgentAudit.argumentHash(arguments),
            tier: AgentActivityFormat.sanitizedTool(tier),
            outcome: outcome
        ))
    }

    private func acquireSlot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if inFlight >= Self.maxInFlight { return false }
        inFlight += 1
        return true
    }

    private func releaseSlot() {
        lock.lock()
        inFlight = max(0, inFlight - 1)
        lock.unlock()
    }

    private static func identity(of path: String) -> (dev: UInt64, ino: UInt64)? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return (UInt64(bitPattern: Int64(info.st_dev)), UInt64(info.st_ino))
    }
}

/// Hands the task's answer back to the waiting connection thread. The semaphore orders the
/// write before the read.
private final class ReplyBox: @unchecked Sendable {
    var value = ""
}
