import Foundation

/// Default Space appearance for an AI-assigned category. Ports `data class CategorySpaceMeta` from
/// `domain/model/CategorySpaces.kt`. `color` is a packed ARGB `Int64` (Kotlin `Long`); `icon` is a
/// stable key the UI resolves to a glyph at the SwiftUI boundary.
struct CategorySpaceMeta: Hashable, Sendable {
    let name: String
    let color: Int64
    let icon: String

    init(name: String, color: Int64, icon: String) {
        self.name = name
        self.color = color
        self.icon = icon
    }
}

/// The bridge that lets AI categories *seed* Spaces. Ports `object CategorySpaces`.
///
/// Each category in the curator taxonomy maps to a canonical default Space (name + colour + icon).
/// When a bookmark is analysed the repository ensures the matching Space exists and files the
/// bookmark into it — so the user gets an auto-organised library of Spaces without the parallel
/// "category" concept ever surfacing in the UI. Custom/unknown categories fall back to a title-cased
/// generic Space.
///
/// Caseless namespace (CONVENTIONS §1) — never instantiated.
enum CategorySpaces {
    /// Prefix for auto-created category Spaces (`space_cat_{userId}_{category}`).
    static let spaceIdPrefix = "space_cat_"

    /// True when `spaceId` points at an AI-seeded category Space (not a user Smart/manual Space).
    static func isCategorySpaceId(_ spaceId: String?) -> Bool {
        guard let spaceId, !spaceId.isEmpty else { return false }
        return spaceId.hasPrefix(spaceIdPrefix)
    }

    /// Bookmarks Smart-Space rules may file: still unfiled, or sitting in an AI category Space.
    /// User-assigned Spaces (manual or prior rule filing into a custom Space) are never overridden.
    static func bookmarkEligibleForRuleFiling(_ spaceId: String?) -> Bool {
        guard let spaceId, !spaceId.isEmpty else { return true }
        return isCategorySpaceId(spaceId)
    }

    /// ARGB constants are written `0xFF……` as Kotlin `Long` literals; they fit in `Int64` positive
    /// range (top byte `0xFF` keeps the value below `0x1_0000_0000`).
    static let defaults: [String: CategorySpaceMeta] = [
        "architectures": CategorySpaceMeta(name: "Architectures", color: 0xFF1E88E5, icon: "hub"),
        "training": CategorySpaceMeta(name: "Training", color: 0xFFFF9800, icon: "bolt"),
        "inference-opt": CategorySpaceMeta(name: "Inference & Opt", color: 0xFFFF5722, icon: "rocket"),
        "datasets": CategorySpaceMeta(name: "Datasets", color: 0xFF43A047, icon: "folder"),
        "evals": CategorySpaceMeta(name: "Evals", color: 0xFF3F51B5, icon: "label"),
        "agents": CategorySpaceMeta(name: "Agents", color: 0xFF8E24AA, icon: "workspaces"),
        "multimodal": CategorySpaceMeta(name: "Multimodal", color: 0xFF00BCD4, icon: "star"),
        "theory": CategorySpaceMeta(name: "Theory", color: 0xFF673AB7, icon: "science"),
        "systems": CategorySpaceMeta(name: "Systems", color: 0xFF607D8B, icon: "code"),
        "other": CategorySpaceMeta(name: "Other", color: 0xFF9E9E9E, icon: "label")
    ]

    /// Canonical default Space for `category`; falls back to a title-cased generic for custom values.
    ///
    /// Replicates the Kotlin fallback exactly:
    /// `key.split(' ', '-', '_').filter { it.isNotBlank() }`
    /// `.joinToString(" ") { it.replaceFirstChar { c -> c.uppercase() } }`
    /// `.ifBlank { "Uncategorized" }`, color `0xFF607D8B`, icon `label`.
    static func forCategory(_ category: String) -> CategorySpaceMeta {
        let key = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let meta = defaults[key] {
            return meta
        }
        let words = key.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { titleCaseFirstChar($0) }
        let joined = words.joined(separator: " ")
        let name = joined.isEmpty ? "Uncategorized" : joined
        return CategorySpaceMeta(name: name, color: 0xFF607D8B, icon: "label")
    }

    /// Mirrors Kotlin `String.replaceFirstChar { it.uppercase() }`: uppercases only the first
    /// character and leaves the remainder untouched. (Since `key` is already lowercased upstream this
    /// produces simple title-casing; matching Kotlin's behaviour of operating per-word.)
    private static func titleCaseFirstChar(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst()
    }
}
