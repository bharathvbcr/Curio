import AppKit
import Foundation

/// The one agent socket for this app. Windows come and go; the listener does not, so a second
/// window can never rebind the socket out from under the first.
@MainActor
final class MacAgentHost {
    static let shared = MacAgentHost()

    private var listener: AgentSocketListener?
    private var terminationObserver: NSObjectProtocol?

    private init() {}

    /// Starts listening once. Later calls retry a failed bind and are otherwise free.
    func start(environment: AppEnvironment) {
        if listener == nil {
            listener = AgentSocketListener(api: environment.makeLibraryAgentAPI())
        }
        listener?.start()
        if terminationObserver == nil {
            terminationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { MacAgentHost.shared.stop() }
            }
        }
    }

    func stop() {
        listener?.stop()
    }

    var isListening: Bool { listener?.isListening ?? false }

    var activeConnections: Int { listener?.activeConnections ?? 0 }

    /// The listener's log when it exists, else the same file on disk.
    var auditLog: AgentAuditLog {
        listener?.auditLog ?? AgentAuditLog(
            url: AgentSocketPath.fileURL().deletingLastPathComponent().appendingPathComponent("agent-audit.log")
        )
    }
}
