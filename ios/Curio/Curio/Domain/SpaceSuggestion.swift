import Foundation

/// An embedding-derived suggestion that `bookmarkId` semantically belongs in Space `spaceId`
/// (`spaceName`) with the given cosine `score`. Port of `SpaceSuggestion.kt`.
struct SpaceSuggestion: Equatable, Sendable, Hashable {
    let bookmarkId: String
    let spaceId: String
    let spaceName: String
    let score: Float
}

/// Outcome of `BookmarkRepository.organizeByEmbedding`. Port of `OrganizeResult.kt`.
struct OrganizeResult: Equatable, Sendable {
    let autoFiled: Int
    let newSpaces: Int
    let suggestions: [SpaceSuggestion]

    var hadChanges: Bool { autoFiled > 0 || newSpaces > 0 }

    /// True when a user-facing toast is worth showing (includes medium-confidence suggestions).
    var hasFeedback: Bool { hadChanges || !suggestions.isEmpty }

    /// Toast copy for the manual "Embed All" / auto-organise announce path; nil when nothing to say.
    func announceMessage() -> String? {
        var parts: [String] = []
        if autoFiled > 0 { parts.append("filed \(autoFiled)") }
        if newSpaces > 0 {
            parts.append("created \(newSpaces) space\(newSpaces == 1 ? "" : "s")")
        }
        if !suggestions.isEmpty {
            parts.append("\(suggestions.count) suggestion\(suggestions.count == 1 ? "" : "s")")
        }
        guard !parts.isEmpty else { return nil }
        return "Auto-organised — \(parts.joined(separator: ", "))"
    }

    static let empty = OrganizeResult(autoFiled: 0, newSpaces: 0, suggestions: [])
}
