import Foundation

// ---------------------------------------------------------------------------
// X (Twitter) v2 bookmarks DTOs — direct port of `data/remote/XBookmarksApi.kt`.
// CodingKeys carry the snake_case wire names. These are read-only response shapes (no encoding),
// so `encodeIfPresent` is not required, but all are `Sendable` value types.
// ---------------------------------------------------------------------------

/// Tweet media attachment keys. Port of `TweetAttachmentsDto`.
struct TweetAttachmentsDto: Codable, Sendable {
    let mediaKeys: [String]?

    enum CodingKeys: String, CodingKey {
        case mediaKeys = "media_keys"
    }
}

/// Long-form tweet body (>280 chars). Prefer this over `text` when present. Port of `NoteTweetDto`.
struct NoteTweetDto: Codable, Sendable {
    let text: String?
}

/// A single expanded URL entity (t.co → real link). Port of `UrlEntityDto`.
struct UrlEntityDto: Codable, Sendable {
    let url: String?
    let expandedUrl: String?
    let displayUrl: String?

    enum CodingKeys: String, CodingKey {
        case url
        case expandedUrl = "expanded_url"
        case displayUrl = "display_url"
    }
}

/// Tweet entities (URL list). Port of `TweetEntitiesDto`.
struct TweetEntitiesDto: Codable, Sendable {
    let urls: [UrlEntityDto]?
}

/// A single bookmarked tweet. Port of `BookmarkDto`. `id`/`text` are required.
struct BookmarkDto: Codable, Sendable {
    let id: String
    let text: String
    let createdAt: String?
    let authorId: String?
    let noteTweet: NoteTweetDto?
    let entities: TweetEntitiesDto?
    let attachments: TweetAttachmentsDto?

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case createdAt = "created_at"
        case authorId = "author_id"
        case noteTweet = "note_tweet"
        case entities
        case attachments
    }
}

/// Media item from `includes.media`, joined by media_key. Port of `MediaDto`.
struct MediaDto: Codable, Sendable {
    let mediaKey: String
    let type: String?
    let url: String?
    let previewImageUrl: String?
    let altText: String?

    enum CodingKeys: String, CodingKey {
        case mediaKey = "media_key"
        case type
        case url
        case previewImageUrl = "preview_image_url"
        case altText = "alt_text"
    }
}

/// Expanded author from `includes.users`, joined by author_id. Port of `UserDto`.
struct UserDto: Codable, Sendable {
    let id: String
    let name: String?
    let username: String?
}

/// The `includes` block (expanded media + users). Port of `BookmarksIncludesDto`.
struct BookmarksIncludesDto: Codable, Sendable {
    let media: [MediaDto]?
    let users: [UserDto]?
}

/// Pagination metadata. Port of `BookmarksMetaDto`.
struct BookmarksMetaDto: Codable, Sendable {
    let nextToken: String?

    enum CodingKeys: String, CodingKey {
        case nextToken = "next_token"
    }
}

/// The bookmarks page response. Port of `BookmarksResponse`.
struct BookmarksResponse: Codable, Sendable {
    let data: [BookmarkDto]?
    let includes: BookmarksIncludesDto?
    let meta: BookmarksMetaDto?
}
