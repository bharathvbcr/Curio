import AppKit
import SwiftUI

/// Agent access for this Mac. The same defaults drive the desk's socket listener.
struct MacAgentSettings: View {
    @AppStorage(MacAgentPreferences.accessKey) private var agentAccess = false
    @AppStorage(MacAgentPreferences.writesKey) private var agentWrites = false
    @AppStorage(MacAgentPreferences.liveKey) private var liveResearch = false
    @AppStorage(MacAgentPreferences.tokenKey) private var agentToken = ""
    @State private var copied = false
    @State private var confirmingRegenerate = false
    @State private var confirmingClear = false
    @State private var activity: [AgentAuditEntry] = []
    @State private var listening = false

    @Environment(\.curioColors) private var colors

    var body: some View {
        Form {
            Section {
                Toggle("Let agents read this library", isOn: $agentAccess)
                Toggle("Let agents change bookmarks", isOn: $agentWrites)
                    .disabled(!agentAccess)
                Toggle("Let research use the live web", isOn: $liveResearch)
            } header: {
                Text("Access")
            } footer: {
                Text("Read tools stay on this Mac unless live research is on. The xAI key and the X tokens stay in the Keychain and are never handed back to an agent. Turning access off pauses agents and keeps the same token.")
            }

            if agentAccess {
                Section {
                    ScrollView {
                        Text(snippet)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                    HStack {
                        Button(copied ? "Copied" : "Copy Configuration") {
                            copied = CurioFormat.copyToClipboard(snippet, label: "Curio MCP")
                        }
                        Spacer()
                        Button("Regenerate Token…", role: .destructive) {
                            confirmingRegenerate = true
                        }
                    }
                    LabeledContent("Status") {
                        Text(listening ? "Listening on this Mac" : "Not listening — open a Curio window")
                            .foregroundStyle(listening ? colors.onSurfaceVariant : colors.error)
                    }
                } header: {
                    Text("Client configuration")
                } footer: {
                    Text("Point an agent at the helper inside this app. The token is the only credential the helper accepts. Regenerating it disconnects every agent until you paste the new configuration.")
                }
            }

            Section {
                if activity.isEmpty {
                    Text("No agent has called Curio yet.")
                        .foregroundStyle(colors.onSurfaceVariant)
                } else {
                    ForEach(activity) { entry in
                        activityRow(entry)
                    }
                }
                HStack {
                    Button("Refresh") { refresh() }
                    Button("Show in Finder") {
                        let log = MacAgentHost.shared.auditLog.url
                        NSWorkspace.shared.activateFileViewerSelecting([log])
                    }
                    .disabled(activity.isEmpty)
                    Spacer()
                    Button("Clear History…", role: .destructive) { confirmingClear = true }
                        .disabled(activity.isEmpty)
                }
            } header: {
                Text("Recent agent activity")
            } footer: {
                Text("Curio records which tool ran and whether it was allowed. Arguments are stored only as a hash.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 580)
        .frame(minHeight: 520)
        .padding(.vertical, 8)
        .onAppear { refresh() }
        .onChange(of: agentAccess) { _, enabled in
            guard enabled else { return }
            agentToken = MacAgentPreferences.enableAccess()
            copied = false
        }
        .confirmationDialog("Regenerate the agent token?", isPresented: $confirmingRegenerate, titleVisibility: .visible) {
            Button("Regenerate", role: .destructive) {
                agentToken = MacAgentPreferences.regenerateToken()
                copied = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Agents using the current configuration will be refused until you give them the new one.")
        }
        .confirmationDialog("Clear agent history?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) {
                MacAgentHost.shared.auditLog.clear()
                refresh()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func activityRow(_ entry: AgentAuditEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: entry.succeeded ? "checkmark.circle" : "xmark.octagon")
                .foregroundStyle(entry.succeeded ? colors.primary : colors.error)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(AgentActivityFormat.toolLabel(entry.tool))
                Text(AgentActivityFormat.outcomeLabel(entry.outcome))
                    .font(.caption)
                    .foregroundStyle(colors.onSurfaceVariant)
            }
            Spacer()
            if let date = entry.date {
                Text(date, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(colors.onSurfaceVariant)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func refresh() {
        activity = MacAgentHost.shared.auditLog.recent(limit: 50)
        listening = MacAgentHost.shared.isListening
    }

    private var snippet: String {
        let stored = MacAgentPreferences.token()
        let token = stored.isEmpty ? agentToken : stored
        return MacAgentInstall.configuration(bundleURL: Bundle.main.bundleURL, token: token)
    }
}
