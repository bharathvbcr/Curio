import SwiftUI

/// Menu actions for the focused desk window. The login screen publishes nothing,
/// so Library commands stay disabled until someone is signed in.
struct MacDeskCommands {
    var canOpen: Bool
    var canCurate: Bool
    var canDelete: Bool
    var canExport: Bool
    var sync: @MainActor () -> Void
    var openLink: @MainActor () -> Void
    var toggleFavorite: @MainActor () -> Void
    var toggleLater: @MainActor () -> Void
    var deleteBookmark: @MainActor () -> Void
    var copyBibtex: @MainActor () -> Void
    var newSpace: @MainActor () -> Void
    var research: @MainActor () -> Void
    var signOut: @MainActor () -> Void
}

private struct MacDeskCommandsKey: FocusedValueKey {
    typealias Value = MacDeskCommands
}

extension FocusedValues {
    var macDeskCommands: MacDeskCommands? {
        get { self[MacDeskCommandsKey.self] }
        set { self[MacDeskCommandsKey.self] = newValue }
    }
}

struct MacDeskMenuCommands: Commands {
    @FocusedValue(\.macDeskCommands) private var desk

    var body: some Commands {
        CommandMenu("Library") {
            Button("Sync from X") { desk?.sync() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(desk == nil)
            Button("Open Link") { desk?.openLink() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(desk?.canOpen != true)
            Divider()
            Button("New Space…") { desk?.newSpace() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(desk == nil)
            Divider()
            Button("Star") { desk?.toggleFavorite() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(desk?.canCurate != true)
            Button("Read Later") { desk?.toggleLater() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(desk?.canCurate != true)
            Button("Copy BibTeX Citation") { desk?.copyBibtex() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(desk?.canExport != true)
            Button("Delete Bookmark", role: .destructive) { desk?.deleteBookmark() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(desk?.canDelete != true)
            Divider()
            Button("Research") { desk?.research() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(desk == nil)
            Divider()
            Button("Sign Out") { desk?.signOut() }
                .disabled(desk == nil)
        }
    }
}
