import Foundation
import CryptoKit

/// A cache hit ready to be shown to the user without an xAI call.
struct CachedAnswer: Sendable {
    let entryId: String
    let response: String
    let similarity: Float
    let modelTier: String
}

/// On-device semantic layer: response cache + RAG compression + complexity routing. Fully local and
/// single-user, this replaces the old Python HTTP sidecar (`SemanticSidecarClient`). The caller
/// embeds the query once (on-device EmbeddingGemma) and threads the vector through
/// lookup / compress / store so nothing is embedded more than necessary.
///
/// Caching is only appropriate for answers that don't depend on Live Search (those are
/// time-sensitive); the caller gates `lookup`/`store` on that.
final class OnDeviceSemanticLayer: Sendable {
    private let cacheStore: SemanticCacheStore
    private let router: ComplexityRouter
    private let compressor: RagCompressor
    private let ttlMillis: Int64
    private let maxEntriesPerUser: Int

    init(
        cacheStore: SemanticCacheStore,
        router: ComplexityRouter = ComplexityRouter(),
        compressor: RagCompressor = RagCompressor(),
        ttlMillis: Int64 = 24 * 60 * 60 * 1000,
        maxEntriesPerUser: Int = 500
    ) {
        self.cacheStore = cacheStore
        self.router = router
        self.compressor = compressor
        self.ttlMillis = ttlMillis
        self.maxEntriesPerUser = maxEntriesPerUser
    }

    func isEnabled() -> Bool { SemanticPreference.isEnabled() }
    func setEnabled(_ enabled: Bool) { SemanticPreference.setEnabled(enabled) }

    /// Complexity → xAI reasoning effort + display tier.
    func route(_ query: String) -> RouteDecision { router.route(query) }

    /// MMR-compress retrieved RAG context. No-op passthrough when the query wasn't embedded.
    func compress(queryEmbedding: [Float]?, scored: [(bookmark: Bookmark, embedding: [Float])]) -> [Bookmark] {
        guard let q = queryEmbedding, !q.isEmpty else { return scored.map { $0.bookmark } }
        return compressor.compress(queryEmbedding: q, scored: scored)
    }

    /// Returns a cached answer for a semantically-equivalent past query, or nil.
    func lookup(query: String, queryEmbedding: [Float]?, userId: String?) async -> CachedAnswer? {
        let uid = userId ?? ""
        let now = Self.nowMillis()
        await cacheStore.deleteExpired(now: now)

        // 1. Exact-hash fast path (verbatim repeat of the same query).
        let hash = Self.hashQuery(query, userId: uid)
        if let hit = await cacheStore.exactHit(userId: uid, hash: hash, now: now) {
            return CachedAnswer(entryId: hit.id, response: hit.response, similarity: 1, modelTier: hit.modelTier)
        }

        // 2. Semantic match over this user's cached queries.
        guard let q = queryEmbedding, !q.isEmpty else { return nil }
        let candidates: [(String, [Float])] = await cacheStore.vectors(userId: uid, now: now)
            .compactMap { row in
                guard let data = row.embedding else { return nil }
                return (row.id, VectorSearch.dataToFloatArray(data))
            }
        if candidates.isEmpty { return nil }
        guard let best = VectorSearch.topKScored(query: q, candidates: candidates, k: 1, minSimilarity: 0).first
        else { return nil }
        if best.1 < SemanticPreference.cacheThreshold() { return nil }
        guard let hit = await cacheStore.hitById(id: best.0, now: now) else { return nil }
        return CachedAnswer(entryId: hit.id, response: hit.response, similarity: best.1, modelTier: hit.modelTier)
    }

    /// Write-through store after a fresh xAI answer. Upserts by hash to avoid duplicates.
    func store(query: String, queryEmbedding: [Float]?, response: String, userId: String?, modelTier: String) async -> String? {
        if response.isEmpty { return nil }
        let uid = userId ?? ""
        let now = Self.nowMillis()
        let hash = Self.hashQuery(query, userId: uid)
        let data: Data? = {
            guard let q = queryEmbedding, !q.isEmpty else { return nil }
            return VectorSearch.floatArrayToData(q)
        }()
        return await cacheStore.upsert(
            userId: uid,
            queryText: query,
            queryHash: hash,
            embedding: data,
            response: response,
            modelTier: modelTier,
            now: now,
            ttlMillis: ttlMillis,
            maxEntries: maxEntriesPerUser
        )
    }

    /// Feedback on a served cache hit. Thumbs-down evicts the offending entry and nudges the hit
    /// threshold up toward the rejected similarity so the bad match isn't repeated.
    func feedback(entryId: String, accepted: Bool, similarity: Float) async {
        if accepted { return }
        await cacheStore.deleteById(entryId)
        if similarity > 0 {
            let current = SemanticPreference.cacheThreshold()
            let target = similarity + 0.02
            let next = current + 0.30 * (target - current)
            if next > current { SemanticPreference.setCacheThreshold(next) }
        }
    }

    private static func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private static func hashQuery(_ query: String, userId: String) -> String {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digest = SHA256.hash(data: Data("\(normalized)|\(userId)".utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }
}
