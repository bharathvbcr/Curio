import Foundation
import SwiftData

/// SwiftData `@Model` for the `spaces` table. Direct port of `data class SpaceEntity`
/// (`data/local/SpaceEntity.kt`).
///
/// A user-created Space — a named collection that bookmarks can be filed into, distinct from the
/// AI-assigned `BookmarkModel.category`.
///
/// Fidelity notes (CONVENTIONS §6):
/// - `id` is `@Attribute(.unique)` (REPLACE-semantics upsert).
/// - `colorValue` is a **packed ARGB** value kept as `Int64` (Kotlin `Long`) all the way through
///   persistence; it is unpacked to a `Color` only at the SwiftUI boundary.
/// - `iconKey` is a stable string resolved to an SF Symbol at the UI boundary.
/// - `rulesJson` is the **empty-string-sentinel** `String = ""` (NOT optional) — an empty string
///   means "plain manual collection". The `'' vs nil` distinction is load-bearing; do not make it
///   optional.
/// - `description = ""`, `isPinned = false`, `sortIndex = 0` mirror the Kotlin defaults (added in the
///   v8→v9 migration with the same defaults).
///
/// `#Index` mirrors Room's single `[userId]` index (`SpaceEntity.kt` `indices`).
///
/// `@Model` is NOT `Sendable`: the `SpaceStore` actor converts to/from the `Space` domain `struct`.
@Model
final class SpaceModel {
    @Attribute(.unique) var id: String
    var userId: String
    var name: String
    /// Packed ARGB. Kept exact as `Int64`.
    var colorValue: Int64
    var iconKey: String
    var createdAt: Int64
    var spaceDescription: String
    var isPinned: Bool
    var sortIndex: Int
    /// Serialized `SpaceRules`; `""` = plain manual collection (empty-string sentinel, NOT optional).
    var rulesJson: String

    #Index<SpaceModel>([\.userId])

    /// Memberwise initializer mirroring the Kotlin constructor defaults exactly.
    init(
        id: String,
        userId: String,
        name: String,
        colorValue: Int64,
        iconKey: String,
        createdAt: Int64,
        spaceDescription: String = "",
        isPinned: Bool = false,
        sortIndex: Int = 0,
        rulesJson: String = ""
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.colorValue = colorValue
        self.iconKey = iconKey
        self.createdAt = createdAt
        self.spaceDescription = spaceDescription
        self.isPinned = isPinned
        self.sortIndex = sortIndex
        self.rulesJson = rulesJson
    }
}
