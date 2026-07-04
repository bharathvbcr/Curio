//
//  CurioToastOverlay.swift
//  Curio
//
//  Shared transient snackbar overlay used by BookmarkApp (global) and optionally by individual screens.
//

import SwiftUI

/// A bottom-aligned capsule toast matching the Android `SnackbarHost` / settings toast styling.
struct CurioToastOverlay: View {
    let message: String?
    @Environment(\.curioColors) private var colors

    var body: some View {
        if let message {
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colors.inverseOnSurface)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    colors.inverseSurface.opacity(0.92),
                    in: Capsule()
                )
                .shadow(radius: 8, y: 2)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .accessibilityIdentifier("curio_toast")
        }
    }
}
