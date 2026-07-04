//
//  CurioDestination.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/CurioDestination.kt (CurioDestination + companion).
//
//  DESIGN §10 (Screens): `enum CurioDestination: String, CaseIterable { case bookmarks="bookmarks",
//  spaces, insights, chat="chatbot", settings; var title }`; `init(rawValue:) ?? .bookmarks`.
//
//  Type-safe top-level destinations. The Kotlin enum carried both an `id` (the route string used at
//  the app-agnostic `GlassBottomBar` boundary) and a `title`. Here the `rawValue` IS the route id —
//  it carries the exact Kotlin `id` strings as the persistence/selection key (CONVENTIONS §1
//  "Persistence-key stability"): `bookmarks`, `spaces`, `insights`, `chatbot`, `settings`. Cases
//  whose lowercase name already equals the route get an implicit rawValue; `chat` overrides to
//  `"chatbot"` to match the Android route string exactly. The `title` is the user-facing screen
//  title surfaced in the top bar (CONVENTIONS §4 "exact user-facing strings").
//
//  The Kotlin `companion.fromId(id)` (`entries.firstOrNull { it.id == id } ?: Bookmarks`) maps to
//  Swift's failable `init(rawValue:)` with a `.bookmarks` fallback — identical semantics: an unknown
//  route resolves to the Bookmarks tab.
//

import Foundation

/// Type-safe top-level navigation destinations. The `rawValue` is the route id compared at the
/// reusable `GlassBottomBar` boundary (which stays route-string based so it remains app-agnostic);
/// `title` is the user-facing screen title.
enum CurioDestination: String, CaseIterable, Sendable, Hashable {
    case bookmarks = "bookmarks"
    case spaces = "spaces"
    case insights = "insights"
    case chat = "chatbot"
    case settings = "settings"

    /// User-facing screen title (verbatim from `CurioDestination.kt`). Carried exactly
    /// (CONVENTIONS §4): "My Bookmarks", "Spaces", "Curio Insights", "Curio AI Chat", "Settings Hub".
    var title: String {
        switch self {
        case .bookmarks: return "My Bookmarks"
        case .spaces: return "Spaces"
        case .insights: return "Curio Insights"
        case .chat: return "Curio AI Chat"
        case .settings: return "Settings Hub"
        }
    }

    /// The route id (the Android `id` field). Equals `rawValue` — kept as a named accessor so call
    /// sites reading `destination.id` mirror the Kotlin source one-for-one.
    var id: String { rawValue }

    /// Resolves a route id to a destination, falling back to `.bookmarks` for any unknown id.
    /// Direct port of `CurioDestination.fromId(id)`
    /// (`entries.firstOrNull { it.id == id } ?: Bookmarks`).
    static func fromId(_ id: String) -> CurioDestination {
        CurioDestination(rawValue: id) ?? .bookmarks
    }
}
