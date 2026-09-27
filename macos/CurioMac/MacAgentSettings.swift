import SwiftUI

/// Agent access for this Mac. The same defaults drive the desk's socket listener.
struct MacAgentSettings: View {
    @AppStorage(MacAgentPreferences.accessKey) private var agentAccess = false
    @AppStorage(MacAgentPreferences.writesKey) private var agentWrites = false
    @AppStorage(MacAgentPreferences.liveKey) private var liveResearch = false
    @AppStorage(MacAgentPreferences.tokenKey) private var agentToken = ""
    @State private var copied = false

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
                    Button(copied ? "Copied" : "Copy Configuration") {
                        copied = CurioFormat.copyToClipboard(snippet, label: "Curio MCP")
                    }
                } header: {
                    Text("Client configuration")
                } footer: {
                    Text("Point an agent at the helper inside this app. The token is the only credential the helper accepts.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .padding(.vertical, 8)
        .onChange(of: agentAccess) { _, enabled in
            guard enabled else { return }
            agentToken = MacAgentPreferences.enableAccess()
            copied = false
        }
    }

    private var snippet: String {
        let stored = MacAgentPreferences.token()
        let token = stored.isEmpty ? agentToken : stored
        return MacAgentInstall.configuration(bundleURL: Bundle.main.bundleURL, token: token)
    }
}
