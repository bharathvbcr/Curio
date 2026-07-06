import Foundation
import SwiftData

/// SwiftData `@Model` for the on-device semantic response cache (`semantic_cache`). Direct port of
/// `SemanticCacheEntity` (`data/local/SemanticCacheEntity.kt`). Stores `(query embedding → past AI
/// answer)` so a semantically-equivalent question can skip the xAI round-trip. Fully local and
/// single-user (rows scoped by `userId`), so there is no cross-user exposure.
///
/// `embedding` is the EmbeddingGemma query vector as a little-endian Float32 blob
/// (`VectorSearch.floatArrayToData`), matching the format used for bookmark embeddings.
@Model
final class SemanticCacheEntry {
    @Attribute(.unique) var id: String
    /// "" for the anonymous/no-account case (predicates use `==`, which never matches nil).
    var userId: String
    var queryText: String
    var queryHash: String
    @Attribute(.externalStorage) var embedding: Data?
    var response: String
    var modelTier: String
    /// Unix epoch milliseconds (matches Android `System.currentTimeMillis()`).
    var createdAt: Int64
    var lastAccessAt: Int64
    var expiresAt: Int64
    var hitCount: Int

    #Index<SemanticCacheEntry>(
        [\.userId, \.queryHash],
        [\.userId],
        [\.expiresAt]
    )

    init(
        id: String,
        userId: String,
        queryText: String,
        queryHash: String,
        embedding: Data? = nil,
        response: String,
        modelTier: String = "",
        createdAt: Int64,
        lastAccessAt: Int64,
        expiresAt: Int64,
        hitCount: Int = 0
    ) {
        self.id = id
        self.userId = userId
        self.queryText = queryText
        self.queryHash = queryHash
        self.embedding = embedding
        self.response = response
        self.modelTier = modelTier
        self.createdAt = createdAt
        self.lastAccessAt = lastAccessAt
        self.expiresAt = expiresAt
        self.hitCount = hitCount
    }
}
