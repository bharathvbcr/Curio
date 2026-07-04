import Foundation
import Testing
@testable import Curio

/// Pure tests for the RAG vector math + float<->byte codec.
///
/// Port of `app/src/test/java/com/example/VectorSearchTest.kt` (pure-JVM JUnit). Implementation
/// under test: `Curio/Intelligence/VectorSearch.swift`.
///
/// Naming note: the Kotlin `FloatArray.toByteArray()` / `ByteArray.toFloatArray()` extensions are
/// `VectorSearch.floatArrayToData(_:)` / `VectorSearch.dataToFloatArray(_:)` on iOS (little-endian
/// Float32 either way).
@Suite("VectorSearch (mirrors VectorSearchTest.kt)")
struct VectorSearchTests {

    /// Kotlin: `cosine similarity is 1 for identical vectors`.
    @Test("cosine similarity is 1 for identical vectors")
    func cosineSimilarityIsOneForIdenticalVectors() {
        let v: [Float] = [1, 2, 3]
        #expect(abs(VectorSearch.cosineSimilarity(v, v) - 1) <= 1e-5)
    }

    /// Kotlin: `cosine similarity is 0 for orthogonal vectors`.
    @Test("cosine similarity is 0 for orthogonal vectors")
    func cosineSimilarityIsZeroForOrthogonalVectors() {
        #expect(abs(VectorSearch.cosineSimilarity([1, 0], [0, 1])) <= 1e-5)
    }

    /// Kotlin: `cosine similarity is 0 for mismatched dimensions`.
    @Test("cosine similarity is 0 for mismatched dimensions")
    func cosineSimilarityIsZeroForMismatchedDimensions() {
        // Guards against mixing cloud and on-device embeddings of different sizes.
        // Kotlin used delta 0f — the mismatch short-circuit must return exactly 0.
        #expect(VectorSearch.cosineSimilarity([1, 2], [1, 2, 3]) == 0)
    }

    /// Kotlin: `topK orders by similarity and respects k`.
    @Test("topK orders by similarity and respects k")
    func topKOrdersBySimilarityAndRespectsK() {
        let query: [Float] = [1, 0]
        let candidates: [(String, [Float])] = [
            ("a", [1, 0]),        // identical -> 1.0
            ("b", [0.7, 0.7]),    // ~0.707
            ("c", [0, 1])         // orthogonal -> 0 (filtered by default threshold)
        ]
        let top = VectorSearch.topK(query: query, candidates: candidates, k: 2)
        #expect(top == ["a", "b"])
    }

    /// Kotlin: `topK drops candidates below the similarity threshold`.
    @Test("topK drops candidates below the similarity threshold")
    func topKDropsCandidatesBelowThreshold() {
        let query: [Float] = [1, 0]
        let candidates: [(String, [Float])] = [("orthogonal", [0, 1])]
        // Default threshold filters the irrelevant match instead of always returning k items.
        #expect(VectorSearch.topK(query: query, candidates: candidates, k: 5).isEmpty)
    }

    /// Kotlin: `topKScored returns scores in descending order`.
    @Test("topKScored returns scores in descending order")
    func topKScoredReturnsScoresInDescendingOrder() throws {
        let query: [Float] = [1, 0]
        let candidates: [(String, [Float])] = [("a", [1, 0]), ("b", [0.6, 0.8])]
        let scored = VectorSearch.topKScored(query: query, candidates: candidates, k: 2, minSimilarity: 0)
        try #require(scored.count == 2)
        #expect(scored[0].0 == "a")
        #expect(scored[0].1 >= scored[1].1)
    }

    /// Kotlin: `float-byte codec round-trips`.
    @Test("float-byte codec round-trips")
    func floatByteCodecRoundTrips() throws {
        let original: [Float] = [-1.5, 0, 3.14159, 42]
        let restored = VectorSearch.dataToFloatArray(VectorSearch.floatArrayToData(original))
        try #require(restored.count == original.count)
        for i in original.indices {
            #expect(abs(original[i] - restored[i]) <= 1e-6)
        }
    }
}
