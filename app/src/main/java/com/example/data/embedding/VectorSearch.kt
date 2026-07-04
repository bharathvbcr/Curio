package com.example.data.embedding

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.sqrt

object VectorSearch {

    fun cosineSimilarity(a: FloatArray, b: FloatArray): Float {
        if (a.size != b.size) return 0f
        var dot = 0f; var normA = 0f; var normB = 0f
        for (i in a.indices) {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        val denom = sqrt(normA) * sqrt(normB)
        return if (denom < 1e-10f) 0f else dot / denom
    }

    /** Dot product for same-dimension vectors (used after L2 normalization → cosine). */
    fun dotProduct(a: FloatArray, b: FloatArray): Float {
        if (a.size != b.size) return 0f
        var dot = 0f
        for (i in a.indices) dot += a[i] * b[i]
        return dot
    }

    /** L2-normalised copy; null when the vector is empty or near-zero. */
    fun normalizeL2(v: FloatArray): FloatArray? {
        if (v.isEmpty()) return null
        var norm = 0f
        for (x in v) norm += x * x
        val d = sqrt(norm)
        if (d < 1e-10f) return null
        return FloatArray(v.size) { i -> v[i] / d }
    }

    /** Default cosine floor below which a candidate is considered irrelevant to the query. */
    const val DEFAULT_MIN_SIMILARITY = 0.30f

    /**
     * Top-k most similar candidate ids. [minSimilarity] drops irrelevant matches so an
     * empty/off-topic query no longer always returns [k] items. Candidates whose vector
     * dimension differs from [query] score 0 (see [cosineSimilarity]) and are filtered out,
     * which also guards against mixing cloud and on-device embeddings of different sizes.
     */
    fun topK(
        query: FloatArray,
        candidates: List<Pair<String, FloatArray>>,
        k: Int = 15,
        minSimilarity: Float = DEFAULT_MIN_SIMILARITY
    ): List<String> = topKScored(query, candidates, k, minSimilarity).map { it.first }

    /** Same as [topK] but keeps the similarity score for each id (e.g. for ranking/citations). */
    fun topKScored(
        query: FloatArray,
        candidates: List<Pair<String, FloatArray>>,
        k: Int = 15,
        minSimilarity: Float = DEFAULT_MIN_SIMILARITY
    ): List<Pair<String, Float>> {
        val heap = java.util.PriorityQueue<Pair<String, Float>>(maxOf(k + 1, 1), compareBy { it.second })
        for ((id, emb) in candidates) {
            val score = cosineSimilarity(query, emb)
            if (score < minSimilarity) continue
            if (heap.size < k || score > (heap.peek()?.second ?: Float.MIN_VALUE)) {
                heap.offer(Pair(id, score))
                if (heap.size > k) heap.poll()
            }
        }
        return heap.sortedByDescending { it.second }
    }

    fun FloatArray.toByteArray(): ByteArray {
        val buf = ByteBuffer.allocate(size * 4).order(ByteOrder.LITTLE_ENDIAN)
        forEach { buf.putFloat(it) }
        return buf.array()
    }

    fun ByteArray.toFloatArray(): FloatArray {
        val buf = ByteBuffer.wrap(this).order(ByteOrder.LITTLE_ENDIAN)
        return FloatArray(size / 4) { buf.getFloat() }
    }
}
