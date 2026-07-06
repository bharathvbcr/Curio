import Foundation
import SwiftData

/// A cache hit projection, safe to cross the actor boundary (never a `@Model`).
struct CachedEntry: Sendable {
    let id: String
    let response: String
    let modelTier: String
}

/// `(id, embedding)` projection for the cosine scan.
struct CacheVectorRow: Sendable {
    let id: String
    let embedding: Data?
}

/// Background-serialized SwiftData store for the `semantic_cache` table. Port of the Room
/// `SemanticCacheDao`; `@ModelActor` runs it off the main actor with its own `ModelContext`.
@ModelActor
actor SemanticCacheStore {

    /// Exact-hash lookup for a non-expired entry; touches it (recency + hit count) on a hit.
    func exactHit(userId: String, hash: String, now: Int64) -> CachedEntry? {
        var d = FetchDescriptor<SemanticCacheEntry>(
            predicate: #Predicate { $0.userId == userId && $0.queryHash == hash && $0.expiresAt > now }
        )
        d.fetchLimit = 1
        d.includePendingChanges = true
        guard let entry = (try? modelContext.fetch(d))?.first else { return nil }
        entry.lastAccessAt = now
        entry.hitCount += 1
        try? modelContext.save()
        return CachedEntry(id: entry.id, response: entry.response, modelTier: entry.modelTier)
    }

    /// `(id, embedding)` rows for this user's non-expired entries (input to the cosine scan).
    func vectors(userId: String, now: Int64) -> [CacheVectorRow] {
        var d = FetchDescriptor<SemanticCacheEntry>(
            predicate: #Predicate { $0.userId == userId && $0.expiresAt > now }
        )
        d.includePendingChanges = true
        let rows = (try? modelContext.fetch(d)) ?? []
        return rows.map { CacheVectorRow(id: $0.id, embedding: $0.embedding) }
    }

    /// Fetch a non-expired entry by id and touch it (used after a semantic match).
    func hitById(id: String, now: Int64) -> CachedEntry? {
        var d = FetchDescriptor<SemanticCacheEntry>(
            predicate: #Predicate { $0.id == id && $0.expiresAt > now }
        )
        d.fetchLimit = 1
        d.includePendingChanges = true
        guard let entry = (try? modelContext.fetch(d))?.first else { return nil }
        entry.lastAccessAt = now
        entry.hitCount += 1
        try? modelContext.save()
        return CachedEntry(id: entry.id, response: entry.response, modelTier: entry.modelTier)
    }

    /// Upsert by `(userId, queryHash)`; returns the entry id, then enforces the LRU cap.
    func upsert(
        userId: String,
        queryText: String,
        queryHash: String,
        embedding: Data?,
        response: String,
        modelTier: String,
        now: Int64,
        ttlMillis: Int64,
        maxEntries: Int
    ) -> String {
        var d = FetchDescriptor<SemanticCacheEntry>(
            predicate: #Predicate { $0.userId == userId && $0.queryHash == queryHash }
        )
        d.fetchLimit = 1
        d.includePendingChanges = true
        let id: String
        if let entry = (try? modelContext.fetch(d))?.first {
            entry.queryText = queryText
            entry.embedding = embedding
            entry.response = response
            entry.modelTier = modelTier
            entry.createdAt = now
            entry.lastAccessAt = now
            entry.expiresAt = now + ttlMillis
            id = entry.id
        } else {
            let newId = UUID().uuidString
            modelContext.insert(
                SemanticCacheEntry(
                    id: newId,
                    userId: userId,
                    queryText: queryText,
                    queryHash: queryHash,
                    embedding: embedding,
                    response: response,
                    modelTier: modelTier,
                    createdAt: now,
                    lastAccessAt: now,
                    expiresAt: now + ttlMillis,
                    hitCount: 0
                )
            )
            id = newId
        }
        try? modelContext.save()
        enforceCap(userId: userId, maxEntries: maxEntries)
        return id
    }

    func deleteById(_ id: String) {
        var d = FetchDescriptor<SemanticCacheEntry>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        if let entry = (try? modelContext.fetch(d))?.first {
            modelContext.delete(entry)
            try? modelContext.save()
        }
    }

    func deleteExpired(now: Int64) {
        let d = FetchDescriptor<SemanticCacheEntry>(predicate: #Predicate { $0.expiresAt <= now })
        guard let expired = try? modelContext.fetch(d), !expired.isEmpty else { return }
        for entry in expired { modelContext.delete(entry) }
        try? modelContext.save()
    }

    /// Drop the least-recently-used overflow for this user.
    private func enforceCap(userId: String, maxEntries: Int) {
        var d = FetchDescriptor<SemanticCacheEntry>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.lastAccessAt, order: .forward)]
        )
        d.includePendingChanges = true
        guard let all = try? modelContext.fetch(d), all.count > maxEntries else { return }
        for entry in all.prefix(all.count - maxEntries) { modelContext.delete(entry) }
        try? modelContext.save()
    }
}
