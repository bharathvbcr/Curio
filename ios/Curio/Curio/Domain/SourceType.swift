import Foundation

/// Resolved primary-source type for a `Bookmark`.
///
/// The raw value is the **exact uppercase Kotlin `.name`** and is written to storage / Firestore /
/// JSON wire formats — it is a persistence key and must never be renamed (see CONVENTIONS
/// §"Persistence-key stability"). Ports `SourceType` from `domain/model/Bookmark.kt`.
enum SourceType: String, Codable, Sendable, CaseIterable, Hashable {
    case ARXIV
    case GITHUB
    case HUGGING_FACE
    case TWEET
    case DOI
}
