//
//  CurioNotifier.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/CurioNotifier.kt
//
//  App-wide transient feedback channel. `BookmarkApp` registers `showMessage` so copy/share/settings
//  actions surface a glass-style toast instead of silent no-ops when the shell is active.
//

import Foundation

@MainActor
enum CurioNotifier {
    /// When set by the app shell, all `notify` calls route here instead of being dropped.
    static var showMessage: ((String) -> Void)?

    static func notify(_ message: String) {
        showMessage?(message)
    }
}
