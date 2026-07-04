import Foundation
import SwiftData

/// SwiftData `@Model` for the `bookmarks` table. Direct port of `data class BookmarkEntity`
/// (`data/local/BookmarkEntity.kt`).
///
/// Serialization-shape fidelity (CONVENTIONS §6 "SwiftData `@Model` conventions"):
/// - `id` is `@Attribute(.unique)` — a unique-id insert is an upsert (REPLACE semantics).
/// - `tags` stays a single **CSV `String?`** here — it is *not* modelled as `[String]`. The domain
///   `Bookmark` carries `[String]`; the CSV split/join lives in `ModelMappers.swift`.
/// - `entities` / `sourceExtra` stay opaque JSON `String?` payloads (decoded by higher layers).
/// - `createdAt` is Unix epoch **milliseconds** as `Int64` (Kotlin `Long`) and doubles as the
///   manual-reorder sort key.
/// - `embedding` is the little-endian Float32 blob (`Data?`) with `@Attribute(.externalStorage)`.
/// - Kotlin defaults are mirrored exactly (`isOcrScheduled=false`, `isAnalyzed=false`,
///   `referenceCount=1`, `isFavorite=false`, `isSavedForLater=false`).
///
/// `'' vs nil` sentinels are kept distinct: callers/predicates check `summary == nil || summary == ""`
/// and `spaceId == nil || spaceId == ""` — never collapse the two.
///
/// `#Index` mirrors Room's six composite indices verbatim (`BookmarkEntity.kt` `indices`):
/// `[userId, createdAt]`, `[userId, sourceId]`, `[spaceId]`, `[userId, category]`, `[isAnalyzed]`,
/// `[userId, isAnalyzed]`. SwiftData recreates them from the model definition (no raw CREATE INDEX).
///
/// `@Model` is NOT `Sendable`: never pass an instance across actor/context boundaries — the
/// `BookmarkStore` actor converts to/from the `Bookmark` domain `struct` before returning.
@Model
final class BookmarkModel {
    @Attribute(.unique) var id: String
    var text: String
    /// Unix epoch milliseconds. Also the manual-reorder sort key.
    var createdAt: Int64
    var userId: String
    var title: String?
    var url: String?
    var summary: String?
    /// CSV — kept as a single string (NOT `[String]`).
    var tags: String?
    var category: String?
    var imageUrl: String?
    var ocrText: String?
    var isOcrScheduled: Bool
    var isAnalyzed: Bool

    // Phase 8
    var sourceType: String?
    var sourceId: String?
    var sourceTitle: String?
    var sourceAuthors: String?
    var sourceAbstract: String?
    var sourceExtra: String?
    var referenceCount: Int

    // Phase 9
    var entities: String?
    var isDeepAnalyzed: Bool
    var deepSummary: String?

    // Phase 10 — opaque little-endian Float32 blob.
    @Attribute(.externalStorage) var embedding: Data?

    // Phase 12 — personal curation
    var isFavorite: Bool
    var isSavedForLater: Bool

    // Tweet author (joined from includes.users via author_id) + image alt-text from media
    var authorName: String?
    var authorUsername: String?
    var imageAltText: String?

    /// Spaces membership (`nil` = unfiled). Local-only; not cloud-mirrored.
    var spaceId: String?

    /// User's personal note/annotation (`nil` = none). Local-only; not cloud-mirrored.
    var notes: String?

    #Index<BookmarkModel>(
        [\.userId, \.createdAt],
        [\.userId, \.sourceId],
        [\.spaceId],
        [\.userId, \.category],
        [\.isAnalyzed],
        [\.userId, \.isAnalyzed]
    )

    /// Memberwise initializer mirroring the Kotlin constructor defaults exactly.
    init(
        id: String,
        text: String,
        createdAt: Int64,
        userId: String,
        title: String? = nil,
        url: String? = nil,
        summary: String? = nil,
        tags: String? = nil,
        category: String? = nil,
        imageUrl: String? = nil,
        ocrText: String? = nil,
        isOcrScheduled: Bool = false,
        isAnalyzed: Bool = false,
        sourceType: String? = nil,
        sourceId: String? = nil,
        sourceTitle: String? = nil,
        sourceAuthors: String? = nil,
        sourceAbstract: String? = nil,
        sourceExtra: String? = nil,
        referenceCount: Int = 1,
        entities: String? = nil,
        isDeepAnalyzed: Bool = false,
        deepSummary: String? = nil,
        embedding: Data? = nil,
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
        self.embedding = embedding
        self.isFavorite = isFavorite
        self.isSavedForLater = isSavedForLater
        self.authorName = authorName
        self.authorUsername = authorUsername
        self.imageAltText = imageAltText
        self.spaceId = spaceId
        self.notes = notes
    }
}
