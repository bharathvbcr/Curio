import Foundation
import Accelerate

/// Cosine-similarity vector search + little-endian Float32 ⇄ `Data` blob serialization.
///
/// Ports `object VectorSearch` from `data/embedding/VectorSearch.kt`. Caseless namespace enum
/// (CONVENTIONS §1). Determinism rules (CONVENTIONS §10):
/// - cosine on L2-normalised vectors; differing-dimension vectors score `0` (also guards against
///   mixing cloud and on-device embeddings of different sizes);
/// - `denom < 1e-10` → `0`;
/// - `[Float] ⇄ Data` is **explicit little-endian** (`UInt32(bitPattern:).littleEndian`), byte-stable
///   and consistent across read/write.
///
/// `topKScored` reproduces the Kotlin `PriorityQueue` min-heap behaviour: keep at most `k` items with
/// score `>= minSimilarity`, evicting the smallest when full, then return sorted descending by score.
enum VectorSearch {

    /// Cosine similarity. Returns `0` for differing dimensions or a near-zero denominator.
    /// Port of `cosineSimilarity(a:b:)`.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        if a.count != b.count { return 0 }
        if a.isEmpty { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        // vDSP for dot/norm (Accelerate). Equivalent to the Kotlin element-wise loop.
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))
        let denom = sqrt(normA) * sqrt(normB)
        return denom < 1e-10 ? 0 : dot / denom
    }

    /// Dot product for same-dimension vectors (used after L2 normalization → cosine).
    static func dotProduct(_ a: [Float], _ b: [Float]) -> Float {
        if a.count != b.count { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return dot
    }

    /// L2-normalised copy; nil when the vector is empty or near-zero.
    static func normalizeL2(_ v: [Float]) -> [Float]? {
        if v.isEmpty { return nil }
        var norm: Float = 0
        vDSP_svesq(v, 1, &norm, vDSP_Length(v.count))
        let d = sqrt(norm)
        if d < 1e-10 { return nil }
        return v.map { $0 / d }
    }

    /// Default cosine floor below which a candidate is considered irrelevant to the query.
    /// Port of `const val DEFAULT_MIN_SIMILARITY = 0.30f`.
    static let DEFAULT_MIN_SIMILARITY: Float = 0.30

    /// Top-k most similar candidate ids. `minSimilarity` drops irrelevant matches so an empty /
    /// off-topic query no longer always returns `k` items. Candidates whose vector dimension differs
    /// from `query` score `0` and are filtered out. Port of `topK(...)`.
    static func topK(
        query: [Float],
        candidates: [(String, [Float])],
        k: Int = 15,
        minSimilarity: Float = DEFAULT_MIN_SIMILARITY
    ) -> [String] {
        topKScored(query: query, candidates: candidates, k: k, minSimilarity: minSimilarity).map { $0.0 }
    }

    /// Same as `topK` but keeps the similarity score for each id (e.g. for ranking / citations).
    /// Port of `topKScored(...)`. Mirrors the Kotlin `PriorityQueue` min-heap semantics: offer when
    /// the heap has room or the score beats the current minimum, then poll if over capacity.
    static func topKScored(
        query: [Float],
        candidates: [(String, [Float])],
        k: Int = 15,
        minSimilarity: Float = DEFAULT_MIN_SIMILARITY
    ) -> [(String, Float)] {
        var heap = MinScoreHeap(capacity: max(k + 1, 1))
        for (id, emb) in candidates {
            let score = cosineSimilarity(query, emb)
            if score < minSimilarity { continue }
            // Kotlin: `heap.size < k || score > (heap.peek()?.second ?: Float.MIN_VALUE)`.
            // Float.MIN_VALUE in Kotlin is the smallest POSITIVE float, not -inf; reproduce exactly.
            let threshold = heap.peek()?.score ?? Float.leastNormalMagnitude
            if heap.count < k || score > threshold {
                heap.offer((id, score))
                if heap.count > k { _ = heap.poll() }
            }
        }
        return heap.elements.sorted { $0.score > $1.score }.map { ($0.id, $0.score) }
    }

    // MARK: - Little-endian Float32 blob

    /// Serializes `[Float]` to a little-endian Float32 `Data` blob. Port of `FloatArray.toByteArray()`.
    static func floatArrayToData(_ values: [Float]) -> Data {
        var data = Data(capacity: values.count * 4)
        for v in values {
            let bits = v.bitPattern.littleEndian
            withUnsafeBytes(of: bits) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// Deserializes a little-endian Float32 `Data` blob to `[Float]`. Port of `ByteArray.toFloatArray()`.
    static func dataToFloatArray(_ data: Data) -> [Float] {
        let count = data.count / 4
        var result = [Float]()
        result.reserveCapacity(count)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0..<count {
                // Read 4 bytes at offset i*4 as a little-endian UInt32, then reinterpret as Float.
                let bits = raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)
                result.append(Float(bitPattern: UInt32(littleEndian: bits)))
            }
        }
        return result
    }
}

/// A small fixed-capacity min-heap on score, reproducing the subset of `java.util.PriorityQueue`
/// behaviour used by `VectorSearch.topKScored` (`peek`/`offer`/`poll`, ordered by ascending score).
private struct MinScoreHeap {
    struct Entry { let id: String; let score: Float }

    private(set) var storage: [Entry] = []
    private let capacityHint: Int

    init(capacity: Int) {
        capacityHint = max(capacity, 1)
        storage.reserveCapacity(capacityHint)
    }

    var count: Int { storage.count }
    var elements: [Entry] { storage }

    /// Smallest-score element (the eviction candidate), or nil when empty.
    func peek() -> Entry? { storage.first }

    mutating func offer(_ value: (String, Float)) {
        storage.append(Entry(id: value.0, score: value.1))
        siftUp(from: storage.count - 1)
    }

    @discardableResult
    mutating func poll() -> Entry? {
        guard !storage.isEmpty else { return nil }
        let root = storage[0]
        let last = storage.removeLast()
        if !storage.isEmpty {
            storage[0] = last
            siftDown(from: 0)
        }
        return root
    }

    private mutating func siftUp(from index: Int) {
        var child = index
        var parent = (child - 1) / 2
        while child > 0 && storage[child].score < storage[parent].score {
            storage.swapAt(child, parent)
            child = parent
            parent = (child - 1) / 2
        }
    }

    private mutating func siftDown(from index: Int) {
        var parent = index
        let n = storage.count
        while true {
            let left = 2 * parent + 1
            let right = 2 * parent + 2
            var smallest = parent
            if left < n && storage[left].score < storage[smallest].score { smallest = left }
            if right < n && storage[right].score < storage[smallest].score { smallest = right }
            if smallest == parent { break }
            storage.swapAt(parent, smallest)
            parent = smallest
        }
    }
}
