import AppKit
import Foundation

/// Outcome of one socket round trip. Once a request has been written the app may act on it,
/// so only `unreachable` is safe to retry.
enum SocketExchange {
    case unreachable
    case answered(String)
    case noAnswer
}

struct SocketTransport: AgentTransport {
    let token: String
    /// Research through a model can take minutes; everything else answers in milliseconds.
    static let answerTimeout: TimeInterval = 300
    static let sendTimeout: TimeInterval = 10
    static let launchAttempts = 40

    func perform(tool: String, argumentsJSON: String) async -> String {
        switch exchange(tool: tool, argumentsJSON: argumentsJSON) {
        case .answered(let line): return line
        case .noAnswer: return Self.noAnswer
        case .unreachable: break
        }
        launchApp()
        for _ in 0..<Self.launchAttempts {
            try? await Task.sleep(nanoseconds: 250_000_000)
            switch exchange(tool: tool, argumentsJSON: argumentsJSON) {
            case .answered(let line): return line
            case .noAnswer: return Self.noAnswer
            case .unreachable: continue
            }
        }
        return AgentToolResult.failure(.appUnavailable, payload: "Curio is not running.").jsonText()
    }

    private static var noAnswer: String {
        AgentToolResult.failure(.appUnavailable, payload: "Curio did not answer in time. The request may still have run.").jsonText()
    }

    private func exchange(tool: String, argumentsJSON: String) -> SocketExchange {
        let fd = AgentSocketIO.openClient()
        guard fd >= 0 else { return .unreachable }
        defer { close(fd) }
        AgentSocketIO.setTimeouts(fd, read: Self.answerTimeout, write: Self.sendTimeout)
        let request = AgentLine.request(token: token, tool: tool, argumentsJSON: argumentsJSON)
        guard AgentSocketIO.writeLine(request, fd: fd) else { return .unreachable }
        guard let line = AgentSocketIO.readLine(fd: fd) else { return .noAnswer }
        return .answered(line)
    }

    private func launchApp() {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        guard let app = AgentAppLocator.appBundle(containing: executable) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: app, configuration: config) { _, _ in }
    }
}

let token = (ProcessInfo.processInfo.environment["CURIO_AGENT_TOKEN"] ?? "")
    .trimmingCharacters(in: .whitespacesAndNewlines)
let dispatcher = MCPDispatcher(
    gate: { !token.isEmpty },
    transport: SocketTransport(token: token)
)

while let line = readLine(strippingNewline: true) {
    let response = await dispatcher.handle(line)
    if let response {
        print(response)
        fflush(stdout)
    }
}
