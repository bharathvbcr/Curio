package com.example

import com.example.data.embedding.SemanticOrganizer
import com.example.data.embedding.VectorSearch
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Pure-JVM tests for the embedding-driven auto-organisation engine. */
class SemanticOrganizerTest {

    // Two well-separated directions in 3-space so cosine cleanly distinguishes them.
    private val aDir = floatArrayOf(1f, 0f, 0f)
    private val bDir = floatArrayOf(0f, 1f, 0f)

    private fun near(base: FloatArray, jitter: Float) =
        floatArrayOf(base[0] + jitter, base[1] + jitter / 2, base[2])

    @Test
    fun `high-similarity card auto-files into nearest space`() {
        val plan = SemanticOrganizer.buildPlan(
            unfiled = listOf("x" to aDir.copyOf()),
            spaceCentroids = mapOf("spaceA" to aDir, "spaceB" to bDir)
        )
        assertEquals(1, plan.autoFile.size)
        assertEquals("x", plan.autoFile.first().bookmarkId)
        assertEquals("spaceA", plan.autoFile.first().spaceId)
        assertTrue(plan.suggestions.isEmpty())
    }

    @Test
    fun `medium-similarity card becomes a suggestion, not an auto-file`() {
        // Nearest to aDir but with a big off-axis (z) component that pulls its cosine into the
        // suggestion band: cosine(medium,aDir)=1/sqrt(1+0.09+1.44)=1/1.590≈0.63 (∈[0.50,0.68]),
        // while cosine(medium,bDir)=0.3/1.590≈0.19, so spaceA is unambiguously the nearest.
        val medium = floatArrayOf(1f, 0.3f, 1.2f)
        val plan = SemanticOrganizer.buildPlan(
            unfiled = listOf("m" to medium),
            spaceCentroids = mapOf("spaceA" to aDir, "spaceB" to bDir)
        )
        assertTrue("expected a suggestion", plan.suggestions.any { it.bookmarkId == "m" && it.spaceId == "spaceA" })
        assertTrue(plan.autoFile.none { it.bookmarkId == "m" })
    }

    @Test
    fun `unrelated cards cluster into a new space when the group is big enough`() {
        // Five near-identical vectors in a direction unrelated to the existing spaces -> one cluster.
        val cDir = floatArrayOf(0f, 0f, 1f)
        val unfiled = (0 until 5).map { "c$it" to near(cDir, it * 0.001f) }
        val plan = SemanticOrganizer.buildPlan(
            unfiled = unfiled,
            spaceCentroids = mapOf("spaceA" to aDir, "spaceB" to bDir)
        )
        assertEquals(1, plan.clusters.size)
        assertEquals(5, plan.clusters.first().bookmarkIds.size)
        assertTrue(plan.autoFile.isEmpty())
    }

    @Test
    fun `a lone leftover does not form a cluster`() {
        val cDir = floatArrayOf(0f, 0f, 1f)
        val plan = SemanticOrganizer.buildPlan(
            unfiled = listOf("lonely" to cDir),
            spaceCentroids = mapOf("spaceA" to aDir)
        )
        assertTrue(plan.clusters.isEmpty())
        assertTrue(plan.autoFile.isEmpty())
        assertTrue(plan.suggestions.isEmpty())
    }

    @Test
    fun `no existing spaces means everything is a clustering candidate`() {
        val cDir = floatArrayOf(0f, 0f, 1f)
        val unfiled = (0 until 4).map { "c$it" to near(cDir, it * 0.001f) }
        val plan = SemanticOrganizer.buildPlan(unfiled = unfiled, spaceCentroids = emptyMap())
        assertEquals(1, plan.clusters.size)
        assertEquals(4, plan.clusters.first().bookmarkIds.size)
    }

    @Test
    fun `pair of similar leftovers forms a cluster`() {
        val cDir = floatArrayOf(0f, 0f, 1f)
        val unfiled = listOf("p0" to near(cDir, 0f), "p1" to near(cDir, 0.001f))
        val plan = SemanticOrganizer.buildPlan(unfiled = unfiled, spaceCentroids = emptyMap())
        assertEquals(1, plan.clusters.size)
        assertEquals(2, plan.clusters.first().bookmarkIds.size)
    }

    @Test
    fun `transitive similarity chains into one cluster`() {
        // A~B and B~C via small steps; A and C are not directly above threshold to each other.
        val a = floatArrayOf(1f, 0f, 0f)
        val b = floatArrayOf(0.85f, 0.53f, 0f)   // cos(a,b) ≈ 0.85
        val c = floatArrayOf(0.3f, 0.95f, 0f)    // cos(b,c) ≈ 0.76, cos(a,c) ≈ 0.30
        assertTrue(VectorSearch.cosineSimilarity(a, b) >= SemanticOrganizer.CLUSTER_THRESHOLD)
        assertTrue(VectorSearch.cosineSimilarity(b, c) >= SemanticOrganizer.CLUSTER_THRESHOLD)
        assertTrue(VectorSearch.cosineSimilarity(a, c) < SemanticOrganizer.CLUSTER_THRESHOLD)

        val plan = SemanticOrganizer.buildPlan(
            unfiled = listOf("a" to a, "b" to b, "c" to c),
            spaceCentroids = emptyMap()
        )
        assertEquals(1, plan.clusters.size)
        assertEquals(setOf("a", "b", "c"), plan.clusters.first().bookmarkIds.toSet())
    }

    @Test
    fun `tie-breaking prefers the larger space when cosine scores match`() {
        val query = floatArrayOf(1f, 0.1f, 0f)
        val smallCentroid = floatArrayOf(1f, 0f, 0f)
        val largeCentroid = floatArrayOf(1f, 0f, 0f)
        val plan = SemanticOrganizer.buildPlan(
            unfiled = listOf("x" to query),
            spaceCentroids = mapOf("small" to smallCentroid, "large" to largeCentroid),
            spaceMemberCounts = mapOf("small" to 2, "large" to 20)
        )
        assertEquals("large", plan.autoFile.first().spaceId)
    }

    @Test
    fun `different embedding dimensions never cross-cluster`() {
        val dim3 = floatArrayOf(0f, 0f, 1f)
        val dim4a = floatArrayOf(0f, 0f, 1f, 0f)
        val dim4b = floatArrayOf(0f, 0f, 0.99f, 0.01f)
        val plan = SemanticOrganizer.buildPlan(
            unfiled = listOf(
                "a" to near(dim3, 0f),
                "b" to near(dim3, 0.001f),
                "c" to dim4a,
                "d" to dim4b
            ),
            spaceCentroids = emptyMap()
        )
        assertEquals(2, plan.clusters.size)
        val sizes = plan.clusters.map { it.bookmarkIds.size }.sorted()
        assertEquals(listOf(2, 2), sizes)
    }

    @Test
    fun `centroid match skips mismatched dimensions`() {
        val query = floatArrayOf(1f, 0f, 0f)
        val wrongDim = floatArrayOf(1f, 0f, 0f, 0f)
        val plan = SemanticOrganizer.buildPlan(
            unfiled = listOf("x" to query),
            spaceCentroids = mapOf("wrong" to wrongDim)
        )
        assertTrue(plan.autoFile.isEmpty())
        assertTrue(plan.suggestions.isEmpty())
        assertTrue(plan.clusters.isEmpty())
    }

    @Test
    fun `zero-norm embedding is ignored`() {
        val zero = floatArrayOf(0f, 0f, 0f)
        val plan = SemanticOrganizer.buildPlan(
            unfiled = listOf("z" to zero, "a" to aDir),
            spaceCentroids = mapOf("spaceA" to aDir)
        )
        assertEquals(1, plan.autoFile.size)
        assertEquals("a", plan.autoFile.first().bookmarkId)
        assertTrue(plan.suggestions.isEmpty())
        assertTrue(plan.clusters.isEmpty())
    }

    @Test
    fun `oversized dimension bucket skips clustering`() {
        val cDir = floatArrayOf(0f, 0f, 1f)
        val unfiled = (0 until SemanticOrganizer.MAX_CLUSTER_BUCKET_SIZE + 1).map {
            "c$it" to near(cDir, it * 0.0001f)
        }
        val plan = SemanticOrganizer.buildPlan(unfiled = unfiled, spaceCentroids = emptyMap())
        assertTrue(plan.clusters.isEmpty())
    }
}
