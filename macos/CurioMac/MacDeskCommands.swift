import SwiftUI

/// Menu actions for the focused desk window. The login screen publishes nothing,
/// so Library commands stay disabled until someone is signed in.
struct MacDeskCommands {
    var selectionCount: Int
    var canOpen: Bool
    var canExport: Bool
    var isSyncing: Bool
    var sort: DeskSort
    var sync: @MainActor () -> Void
    var loadOlder: @MainActor () -> Void
    var newBookmark: @MainActor () -> Void
    var openLink: @MainActor () -> Void
    var toggleFavorite: @MainActor () -> Void
    var toggleLater: @MainActor () -> Void
    var deleteBookmark: @MainActor () -> Void
    var copyBibtex: @MainActor () -> Void
    var copyLinks: @MainActor () -> Void
    var export: @MainActor (DeskExportFormat) -> Void
    var setSort: @MainActor (DeskSort) -> Void
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

    private var hasSelection: Bool { (desk?.selectionCount ?? 0) > 0 }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Bookmark…") { desk?.newBookmark() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(desk == nil)
            Button("New Space…") { desk?.newSpace() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(desk == nil)
        }

        CommandGroup(after: .importExport) {
            Menu("Export") {
                ForEach(DeskExportFormat.allCases) { format in
                    Button(format.label + "…") { desk?.export(format) }
                }
            }
            .disabled(desk?.canExport != true)
        }

        CommandGroup(after: .toolbar) {
            Menu("Sort By") {
                ForEach(DeskSort.allCases) { sort in
                    Button {
                        desk?.setSort(sort)
                    } label: {
                        if desk?.sort == sort {
                            Label(sort.label, systemImage: "checkmark")
                        } else {
                            Text(sort.label)
                        }
                    }
                }
            }
            .disabled(desk == nil)
        }

        CommandMenu("Library") {
            Button("Sync from X") { desk?.sync() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(desk == nil || desk?.isSyncing == true)
            Button("Load Older from X") { desk?.loadOlder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(desk == nil || desk?.isSyncing == true)
            Divider()
            Button("Open Link") { desk?.openLink() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(desk?.canOpen != true)
            Button("Copy Links") { desk?.copyLinks() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(!hasSelection)
            Button("Copy BibTeX Citation") { desk?.copyBibtex() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!hasSelection)
            Divider()
            Button("Star") { desk?.toggleFavorite() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!hasSelection)
            Button("Read Later") { desk?.toggleLater() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(!hasSelection)
            Button((desk?.selectionCount ?? 0) > 1 ? "Delete Bookmarks…" : "Delete Bookmark…", role: .destructive) {
                desk?.deleteBookmark()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(!hasSelection)
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
