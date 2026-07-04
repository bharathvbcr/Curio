import Foundation
import SwiftData

/// `@Model` ↔ domain `struct` mappers (CONVENTIONS §6, §7). Kept next to the persistence layer; the
/// stores call these to convert before crossing an actor boundary (a `@Model` is NOT `Sendable`).
///
/// Two shape conversions are load-bearing:
/// - **tags CSV ↔ `[String]`**: `BookmarkModel.tags` is a single CSV string; `Bookmark.tags` is a
///   real `[String]`. Split on `,`, trim each element, drop empties. Join with `,` on the way back;
///   an empty array serializes to `nil` (not `""`) so an unset CSV stays unset.
/// - **`sourceType` String ↔ `SourceType`**: guarded `SourceType(rawValue:)` — an unknown raw value
///   maps to `nil` (never crashes).
/// - **rulesJson ↔ `SpaceRules`**: via the tolerant `SpaceRules.fromJson` / `toJson` (Domain).
///
/// `Space.count` is a derived/transient field — it is NOT persisted on `SpaceModel`; the stores fill
/// it via a query (default `0` when mapping straight from a model).

// MARK: - Tags CSV helpers

enum TagsCsv {
    /// CSV → `[String]`: split on `,`, trim whitespace, drop blanks. Mirrors the Kotlin
    /// `split(",").map { it.trim() }.filter { it.isNotBlank() }`.
    static func decode(_ csv: String?) -> [String] {
        guard let csv, !csv.isEmpty else { return [] }
        return csv
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// `[String]` → CSV: join non-blank, trimmed tags with `,`. An empty result becomes `nil` (an
    /// unset CSV stays unset — the `'' vs nil` distinction is preserved by never emitting `""`).
    static func encode(_ tags: [String]) -> String? {
        let cleaned = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? nil : cleaned.joined(separator: ",")
    }
}

// MARK: - BookmarkModel ↔ Bookmark

extension BookmarkModel {
    /// Maps this persistence model to the domain `Bookmark` value. Safe to call inside the owning
    /// actor; the returned `struct` is `Sendable` and may cross boundaries.
    func toDomain() -> Bookmark {
        Bookmark(
            id: id,
            text: text,
            createdAt: createdAt,
            userId: userId,
            title: title,
            url: url,
            summary: summary,
            tags: TagsCsv.decode(tags),
            category: category,
            imageUrl: imageUrl,
            ocrText: ocrText,
            isOcrScheduled: isOcrScheduled,
            isAnalyzed: isAnalyzed,
            sourceType: sourceType.flatMap { SourceType(rawValue: $0) },
            sourceId: sourceId,
            sourceTitle: sourceTitle,
            sourceAuthors: sourceAuthors,
            sourceAbstract: sourceAbstract,
            sourceExtra: sourceExtra,
            referenceCount: referenceCount,
            entities: entities,
            isDeepAnalyzed: isDeepAnalyzed,
            deepSummary: deepSummary,
            isFavorite: isFavorite,
            isSavedForLater: isSavedForLater,
            authorName: authorName,
            authorUsername: authorUsername,
            imageAltText: imageAltText,
            spaceId: spaceId,
            notes: notes
        )
    }

    /// Overwrites this model's columns from a domain `Bookmark` (whole-row REPLACE semantics, matching
    /// Room `OnConflictStrategy.REPLACE`). `id` is the identity and is left untouched.
    func apply(_ b: Bookmark) {
        text = b.text
        createdAt = b.createdAt
        userId = b.userId
        title = b.title
        url = b.url
        summary = b.summary
        tags = TagsCsv.encode(b.tags)
        category = b.category
        imageUrl = b.imageUrl
        ocrText = b.ocrText
        isOcrScheduled = b.isOcrScheduled
        isAnalyzed = b.isAnalyzed
        sourceType = b.sourceType?.rawValue
        sourceId = b.sourceId
        sourceTitle = b.sourceTitle
        sourceAuthors = b.sourceAuthors
        sourceAbstract = b.sourceAbstract
        sourceExtra = b.sourceExtra
        referenceCount = b.referenceCount
        entities = b.entities
        isDeepAnalyzed = b.isDeepAnalyzed
        deepSummary = b.deepSummary
        // NOTE: `embedding` is intentionally NOT touched here. Embeddings are written via the
        // dedicated `updateEmbedding(s)` paths; a whole-row upsert from a domain `Bookmark` (which
        // carries no embedding field) must never clobber a stored vector.
        isFavorite = b.isFavorite
        isSavedForLater = b.isSavedForLater
        authorName = b.authorName
        authorUsername = b.authorUsername
        imageAltText = b.imageAltText
        spaceId = b.spaceId
        notes = b.notes
    }

    /// Builds a fresh persistence model from a domain `Bookmark`. Used by upsert when no existing row
    /// matches the unique `id`.
    static func from(_ b: Bookmark) -> BookmarkModel {
        BookmarkModel(
            id: b.id,
            text: b.text,
            createdAt: b.createdAt,
            userId: b.userId,
            title: b.title,
            url: b.url,
            summary: b.summary,
            tags: TagsCsv.encode(b.tags),
            category: b.category,
            imageUrl: b.imageUrl,
            ocrText: b.ocrText,
            isOcrScheduled: b.isOcrScheduled,
            isAnalyzed: b.isAnalyzed,
            sourceType: b.sourceType?.rawValue,
            sourceId: b.sourceId,
            sourceTitle: b.sourceTitle,
            sourceAuthors: b.sourceAuthors,
            sourceAbstract: b.sourceAbstract,
            sourceExtra: b.sourceExtra,
            referenceCount: b.referenceCount,
            entities: b.entities,
            isDeepAnalyzed: b.isDeepAnalyzed,
            deepSummary: b.deepSummary,
            embedding: nil,
            isFavorite: b.isFavorite,
            isSavedForLater: b.isSavedForLater,
            authorName: b.authorName,
            authorUsername: b.authorUsername,
            imageAltText: b.imageAltText,
            spaceId: b.spaceId,
            notes: b.notes
        )
    }
}

// MARK: - SpaceModel ↔ Space

extension SpaceModel {
    /// Decodes the persisted rules blob via the tolerant Domain parser.
    func rules() -> SpaceRules {
        SpaceRules.fromJson(rulesJson)
    }

    /// Maps to the domain `Space`. `count` defaults to `0` — the stores/repository fill it via a
    /// membership query (it is a derived/transient field, never persisted).
    func toDomain(count: Int = 0) -> Space {
        Space(
            id: id,
            userId: userId,
            name: name,
            color: colorValue,
            icon: iconKey,
            createdAt: createdAt,
            count: count,
            description: spaceDescription,
            isPinned: isPinned,
            sortIndex: sortIndex,
            rules: rules()
        )
    }

    /// Overwrites this model from a domain `Space` (REPLACE semantics). `id` is identity; `count` is
    /// transient and never written back.
    func apply(_ s: Space) {
        userId = s.userId
        name = s.name
        colorValue = s.color
        iconKey = s.icon
        createdAt = s.createdAt
        spaceDescription = s.description
        isPinned = s.isPinned
        sortIndex = s.sortIndex
        rulesJson = s.rules.toJson()
    }

    /// Builds a fresh persistence model from a domain `Space`.
    static func from(_ s: Space) -> SpaceModel {
        SpaceModel(
            id: s.id,
            userId: s.userId,
            name: s.name,
            colorValue: s.color,
            iconKey: s.icon,
            createdAt: s.createdAt,
            spaceDescription: s.description,
            isPinned: s.isPinned,
            sortIndex: s.sortIndex,
            rulesJson: s.rules.toJson()
        )
    }
}
