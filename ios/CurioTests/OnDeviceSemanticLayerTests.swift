import Foundation
import SwiftData
import Testing
@testable import Curio

/// Covers the on-device semantic layer that replaced the Python sidecar: complexity routing, MMR
/// compression, and the response cache (exact + semantic hits, threshold miss, cross-user
/// isolation, feedback-driven eviction). Mirrors `OnDeviceSemanticLayerTest.kt`.
///
/// `.serialized` because the cache threshold lives in the shared `UserDefaults` — parallel tests
/// would race on it. Each test gets a fresh in-memory store via `init()`.
@Suite("OnDeviceSemanticLayer", .serialized)
struct OnDeviceSemanticLayerTests {

    let layer: OnDeviceSemanticLayer

    init() throws {
        let schema = Schema([BookmarkModel.self, SpaceModel.self, SemanticCacheEntry.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        layer = OnDeviceSemanticLayer(cacheStore: SemanticCacheStore(modelContainer: container))
        SemanticPreference.setCacheThreshold(SemanticPreference.thresholdInitial)
    }

    // MARK: - Router

    @Test("Short simple query → fast tier")
    func routerFast() {
        let decision = ComplexityRouter().route("hello there")
        #expect(decision.tier == "fast")
        #expect(decision.reasoningEffort == GrokReasoning.low)
    }

    @Test("Code + multi-step query → deep tier")
    func routerDeep() {
        let decision = ComplexityRouter().route(
            "def solve(): first, analyze the approach then compare and prove why step 1 works here"
        )
        #expect(decision.tier == "deep")
        #expect(decision.reasoningEffort == GrokReasoning.high)
    }

    // MARK: - Compressor

    @Test("Compressor drops chunks irrelevant to the query")
    func compressorDropsIrrelevant() {
        let query: [Float] = [1, 0]
        let scored: [(bookmark: Bookmark, embedding: [Float])] = [
            (bookmark("a"), [1, 0]),   // cosine 1.0
            (bookmark("b"), [0, 1])    // cosine 0.0 < 0.25
        ]
        let kept = RagCompressor().compress(queryEmbedding: query, scored: scored)
        #expect(kept.map { $0.id } == ["a"])
    }

    @Test("Compressor keeps chunks without embeddings")
    func compressorKeepsNoEmbedding() {
        let scored: [(bookmark: Bookmark, embedding: [Float])] = [(bookmark("c"), [])]
        let kept = RagCompressor().compress(queryEmbedding: [1, 0], scored: scored)
        #expect(kept.map { $0.id } == ["c"])
    }

    // MARK: - Cache

    @Test("Exact repeat of a query is served from cache")
    func exactHit() async throws {
        let vec: [Float] = [1, 0]
        _ = await layer.store(query: "what is attention", queryEmbedding: vec, response: "Attention weights inputs.", userId: "user-a", modelTier: "fast")
        let hit = try #require(await layer.lookup(query: "what is attention", queryEmbedding: vec, userId: "user-a"))
        #expect(hit.response == "Attention weights inputs.")
        #expect(abs(hit.similarity - 1) < 1e-4)
    }

    @Test("A semantically similar query hits above threshold")
    func semanticHit() async throws {
        _ = await layer.store(query: "what is self attention", queryEmbedding: [1, 0], response: "It weights inputs.", userId: "user-a", modelTier: "fast")
        // Different text (exact-hash miss) but near-identical vector (cosine ~0.99 >= 0.90).
        let hit = try #require(await layer.lookup(query: "explain self-attention please", queryEmbedding: [0.99, 0.14], userId: "user-a"))
        #expect(hit.similarity >= 0.90)
    }

    @Test("A dissimilar query misses")
    func dissimilarMiss() async {
        _ = await layer.store(query: "what is self attention", queryEmbedding: [1, 0], response: "It weights inputs.", userId: "user-a", modelTier: "fast")
        let miss = await layer.lookup(query: "unrelated cooking question", queryEmbedding: [0.5, 0.87], userId: "user-a")
        #expect(miss == nil)
    }

    @Test("One user's cached answer is never served to another")
    func crossUserIsolation() async {
        let vec: [Float] = [1, 0]
        _ = await layer.store(query: "what is attention", queryEmbedding: vec, response: "A's private answer.", userId: "user-a", modelTier: "fast")
        let crossUser = await layer.lookup(query: "what is attention", queryEmbedding: vec, userId: "user-b")
        #expect(crossUser == nil)
    }

    @Test("Thumbs-down evicts the entry and raises the threshold")
    func feedbackEvicts() async throws {
        let vec: [Float] = [1, 0]
        let entryId = try #require(await layer.store(query: "what is attention", queryEmbedding: vec, response: "A weak answer.", userId: "user-a", modelTier: "fast"))
        await layer.feedback(entryId: entryId, accepted: false, similarity: 0.95)
        let afterEviction = await layer.lookup(query: "what is attention", queryEmbedding: vec, userId: "user-a")
        #expect(afterEviction == nil)
        #expect(SemanticPreference.cacheThreshold() > SemanticPreference.thresholdInitial)
    }

    private func bookmark(_ id: String) -> Bookmark {
        Bookmark(id: id, text: "text for \(id)", createdAt: 0, userId: "user-a", title: "Title \(id)")
    }
}
