package com.example

import com.example.data.embedding.VectorSearch
import com.example.data.embedding.VectorSearch.toByteArray
import com.example.data.embedding.VectorSearch.toFloatArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Pure-JVM tests for the RAG vector math + float<->byte codec. */
class VectorSearchTest {

    @Test
    fun `cosine similarity is 1 for identical vectors`() {
        val v = floatArrayOf(1f, 2f, 3f)
        assertEquals(1f, VectorSearch.cosineSimilarity(v, v), 1e-5f)
    }

    @Test
    fun `cosine similarity is 0 for orthogonal vectors`() {
        assertEquals(0f, VectorSearch.cosineSimilarity(floatArrayOf(1f, 0f), floatArrayOf(0f, 1f)), 1e-5f)
    }

    @Test
    fun `cosine similarity is 0 for mismatched dimensions`() {
        // Guards against mixing cloud and on-device embeddings of different sizes.
        assertEquals(0f, VectorSearch.cosineSimilarity(floatArrayOf(1f, 2f), floatArrayOf(1f, 2f, 3f)), 0f)
    }

    @Test
    fun `topK orders by similarity and respects k`() {
        val query = floatArrayOf(1f, 0f)
        val candidates = listOf(
            "a" to floatArrayOf(1f, 0f),     // identical -> 1.0
            "b" to floatArrayOf(0.7f, 0.7f), // ~0.707
            "c" to floatArrayOf(0f, 1f)      // orthogonal -> 0 (filtered by default threshold)
        )
        val top = VectorSearch.topK(query, candidates, k = 2)
        assertEquals(listOf("a", "b"), top)
    }

    @Test
    fun `topK drops candidates below the similarity threshold`() {
        val query = floatArrayOf(1f, 0f)
        val candidates = listOf("orthogonal" to floatArrayOf(0f, 1f))
        // Default threshold filters the irrelevant match instead of always returning k items.
        assertTrue(VectorSearch.topK(query, candidates, k = 5).isEmpty())
    }

    @Test
    fun `topKScored returns scores in descending order`() {
        val query = floatArrayOf(1f, 0f)
        val candidates = listOf("a" to floatArrayOf(1f, 0f), "b" to floatArrayOf(0.6f, 0.8f))
        val scored = VectorSearch.topKScored(query, candidates, k = 2, minSimilarity = 0f)
        assertEquals("a", scored[0].first)
        assertTrue(scored[0].second >= scored[1].second)
    }

    @Test
    fun `float-byte codec round-trips`() {
        val original = floatArrayOf(-1.5f, 0f, 3.14159f, 42f)
        val restored = original.toByteArray().toFloatArray()
        assertEquals(original.size, restored.size)
        for (i in original.indices) assertEquals(original[i], restored[i], 1e-6f)
    }
}
