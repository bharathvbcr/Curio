import Foundation

/// A user-created collection that bookmarks can be filed into. Direct port of `data class Space`
/// in `domain/model/Space.kt`.
///
/// - `color` is a **packed ARGB** value kept as `Int64` (Kotlin `Long`) all the way through domain
///   and persistence; it is unpacked to a SwiftUI `Color` only at the UI boundary (CONVENTIONS §8).
/// - `icon` is a stable key resolved to an SF Symbol at the UI boundary.
/// - `count` is the number of bookmarks currently filed here; it is **computed at read time** (not
///   persisted) — the persistence/repository layer fills it via a query (default `0`).
/// - `description` is an optional one-line note (empty-string default, NOT `nil` — the `'' vs nil`
///   sentinel distinction is load-bearing).
/// - `isPinned` floats the Space to the top; `sortIndex` gives manual ordering within each group.
/// - `rules` is the auto-filing configuration that turns a Space into a "Smart Space"; an empty
///   rule set (`.empty`) means a plain manual collection.
struct Space: Identifiable, Hashable, Sendable {
    let id: String
    let userId: String
    let name: String
    /// Packed ARGB. Kept as `Int64` until the SwiftUI boundary.
    let color: Int64
    let icon: String
    let createdAt: Int64
    /// Number of bookmarks filed here — derived/transient, not persisted.
    let count: Int
    let description: String
    let isPinned: Bool
    let sortIndex: Int
    let rules: SpaceRules

    /// True when this Space auto-files bookmarks via [rules] — surfaced as a "Smart" badge.
    var isSmart: Bool { rules.isActive }

    init(
        id: String,
        userId: String,
        name: String,
        color: Int64,
        icon: String,
        createdAt: Int64,
        count: Int = 0,
        description: String = "",
        isPinned: Bool = false,
        sortIndex: Int = 0,
        rules: SpaceRules = .empty
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.color = color
        self.icon = icon
        self.createdAt = createdAt
        self.count = count
        self.description = description
        self.isPinned = isPinned
        self.sortIndex = sortIndex
        self.rules = rules
    }
}
