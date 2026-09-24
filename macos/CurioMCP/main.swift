import AppKit
import Foundation

struct SocketTransport: AgentTransport {
    let token: String

    func perform(tool: String, argumentsJSON: String) async -> String {
        if let line = exchange(tool: tool, argumentsJSON: argumentsJSON) { return line }
        launchApp()
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if let line = exchange(tool: tool, argumentsJSON: argumentsJSON) { return line }
        }
        return AgentToolResult.failure(.appUnavailable, payload: "Curio is not running.").jsonText()
    }

    private func exchange(tool: String, argumentsJSON: String) -> String? {
        let fd = AgentSocketIO.openClient()
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        let request = AgentLine.request(token: token, tool: tool, argumentsJSON: argumentsJSON)
        AgentSocketIO.writeLine(request, fd: fd)
        return AgentSocketIO.readLine(fd: fd)
    }

    private func launchApp() {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let app = executable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard app.pathExtension == "app" else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: app, configuration: config) { _, _ in }
    }
}

let token = ProcessInfo.processInfo.environment["CURIO_AGENT_TOKEN"] ?? ""
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
