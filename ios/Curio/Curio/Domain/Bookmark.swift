import Foundation

/// Central aggregate value model for a saved item (an X bookmark, a manually-added link, etc.).
///
/// Direct port of `data class Bookmark` in `domain/model/Bookmark.kt`. Field names, nullability and
/// Kotlin default values are carried over **exactly** — every default in the memberwise `init`
/// mirrors the Kotlin parameter default so call sites can omit the same arguments.
///
/// Notes on the type mapping (see CONVENTIONS §6 / §10):
/// - `createdAt` is Unix epoch **milliseconds** as `Int64`; it doubles as the manual-reorder sort
///   key (`swapCreatedAt`). Kotlin `Long` → Swift `Int64`.
/// - `tags` is a real `[String]` here in the domain layer (default `[]`). The persistence layer
///   stores it as a single CSV `String?`; the wire/DTO layers split/join — domain never sees CSV.
/// - `entities`, `sourceExtra`, `deepSummary` are **opaque JSON `String?`** payloads decoded by
///   higher layers; the domain model keeps them as raw strings.
/// - `referenceCount` defaults to `1` (tweets pointing at the same resolved source).
///
/// UI INVARIANT: `category` is the AI-assigned taxonomy bucket used only to seed Spaces — it must
/// **never** be displayed in the UI (it is intentionally surfaced through Spaces instead).
struct Bookmark: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let text: String
    /// Unix epoch milliseconds. Also the manual-reorder sort key.
    let createdAt: Int64
    let userId: String
    let title: String?
    let url: String?
    let summary: String?
    let tags: [String]
    /// AI-assigned category. NEVER displayed in the UI — only used to seed Spaces.
    let category: String?
    /// Primary attached media (tweet photo / preview).
    let imageUrl: String?
    let ocrText: String?
    let isOcrScheduled: Bool
    let isAnalyzed: Bool

    // Phase 8: primary-source resolution
    let sourceType: SourceType?
    let sourceId: String?
    let sourceTitle: String?
    /// Comma-separated.
    let sourceAuthors: String?
    let sourceAbstract: String?
    /// JSON: published date, stars, etc.
    let sourceExtra: String?
    /// Tweets pointing to the same source.
    let referenceCount: Int

    // Phase 9: research taxonomy + entities
    /// JSON: {models:[], methods:[], datasets:[], metrics:[]}
    let entities: String?
    let isDeepAnalyzed: Bool
    /// Structured contribution/significance/caveats.
    let deepSummary: String?

    // Phase 12: personal curation
    /// Starred / loved.
    let isFavorite: Bool
    /// Marked to read later.
    let isSavedForLater: Bool

    // Tweet author (joined from includes.users) + image alt-text
    let authorName: String?
    let authorUsername: String?
    let imageAltText: String?

    /// Spaces: user-created collection membership (`nil` = unfiled).
    let spaceId: String?

    /// User's personal note/annotation on this entry (`nil` = none).
    let notes: String?

    /// Explicit memberwise initializer mirroring the Kotlin constructor defaults exactly.
    init(
        id: String,
        text: String,
        createdAt: Int64,
        userId: String,
        title: String? = nil,
        url: String? = nil,
        summary: String? = nil,
        tags: [String] = [],
        category: String? = nil,
        imageUrl: String? = nil,
        ocrText: String? = nil,
        isOcrScheduled: Bool = false,
        isAnalyzed: Bool = false,
        sourceType: SourceType? = nil,
        sourceId: String? = nil,
        sourceTitle: String? = nil,
        sourceAuthors: String? = nil,
        sourceAbstract: String? = nil,
        sourceExtra: String? = nil,
        referenceCount: Int = 1,
        entities: String? = nil,
        isDeepAnalyzed: Bool = false,
        deepSummary: String? = nil,
        isFavorite: Bool = false,
        isSavedForLater: Bool = false,
        authorName: String? = nil,
        authorUsername: String? = nil,
        imageAltText: String? = nil,
        spaceId: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.userId = userId
        self.title = title
        self.url = url
        self.summary = summary
        self.tags = tags
        self.category = category
        self.imageUrl = imageUrl
        self.ocrText = ocrText
        self.isOcrScheduled = isOcrScheduled
        self.isAnalyzed = isAnalyzed
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.sourceTitle = sourceTitle
        self.sourceAuthors = sourceAuthors
        self.sourceAbstract = sourceAbstract
        self.sourceExtra = sourceExtra
        self.referenceCount = referenceCount
        self.entities = entities
        self.isDeepAnalyzed = isDeepAnalyzed
        self.deepSummary = deepSummary
        self.isFavorite = isFavorite
        self.isSavedForLater = isSavedForLater
        self.authorName = authorName
        self.authorUsername = authorUsername
        self.imageAltText = imageAltText
        self.spaceId = spaceId
        self.notes = notes
    }
}
