package com.example

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.example.data.local.AppDatabase
import com.example.data.local.SemanticCacheDao
import com.example.data.semantic.ComplexityRouter
import com.example.data.semantic.OnDeviceSemanticLayer
import com.example.data.semantic.RagCompressor
import com.example.data.semantic.SemanticPreference
import com.example.domain.model.Bookmark
import com.example.data.remote.GrokReasoning
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Covers the on-device semantic layer that replaced the Python sidecar: complexity routing, MMR
 * compression, and the response cache (exact + semantic hits, threshold miss, cross-user
 * isolation, and feedback-driven eviction).
 */
@RunWith(RobolectricTestRunner::class)
class OnDeviceSemanticLayerTest {

    private lateinit var context: Context
    private lateinit var db: AppDatabase
    private lateinit var dao: SemanticCacheDao
    private lateinit var layer: OnDeviceSemanticLayer

    @Before
    fun setup() {
        context = ApplicationProvider.getApplicationContext()
        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        dao = db.semanticCacheDao()
        SemanticPreference.setCacheThreshold(context, SemanticPreference.THRESHOLD_INITIAL)
        layer = OnDeviceSemanticLayer(context, dao)
    }

    @After
    fun teardown() {
        db.close()
    }

    // ---- Router ----

    @Test
    fun `router sends a short simple query to the fast tier`() {
        val decision = ComplexityRouter().route("hello there")
        assertEquals("fast", decision.tier)
        assertEquals(GrokReasoning.LOW, decision.reasoningEffort)
    }

    @Test
    fun `router sends a code and multi-step query to the deep tier`() {
        val decision = ComplexityRouter().route(
            "def solve(): first, analyze the approach then compare and prove why step 1 works here"
        )
        assertEquals("deep", decision.tier)
        assertEquals(GrokReasoning.HIGH, decision.reasoningEffort)
    }

    // ---- Compressor ----

    @Test
    fun `compressor drops chunks irrelevant to the query`() {
        val query = floatArrayOf(1f, 0f)
        val relevant = bookmark("a") to floatArrayOf(1f, 0f)          // cosine 1.0
        val irrelevant = bookmark("b") to floatArrayOf(0f, 1f)        // cosine 0.0 < 0.25
        val kept = RagCompressor().compress(query, listOf(relevant, irrelevant))
        assertEquals(listOf("a"), kept.map { it.id })
    }

    @Test
    fun `compressor keeps chunks without embeddings`() {
        val query = floatArrayOf(1f, 0f)
        val noEmbedding = bookmark("c") to FloatArray(0)
        val kept = RagCompressor().compress(query, listOf(noEmbedding))
        assertEquals(listOf("c"), kept.map { it.id })
    }

    // ---- Cache ----

    @Test
    fun `exact repeat of a query is served from cache`() = runTest {
        val vec = floatArrayOf(1f, 0f)
        layer.store("what is attention", vec, "Attention weights inputs.", "user-a", "fast")
        val hit = layer.lookup("what is attention", vec, "user-a")
        assertNotNull(hit)
        assertEquals("Attention weights inputs.", hit!!.response)
        assertEquals(1f, hit.similarity, 1e-4f)
    }

    @Test
    fun `a semantically similar query hits above threshold`() = runTest {
        layer.store("what is self attention", floatArrayOf(1f, 0f), "It weights inputs.", "user-a", "fast")
        // Different text (exact-hash miss) but near-identical vector (cosine ~0.99 >= 0.90).
        val hit = layer.lookup("explain self-attention please", floatArrayOf(0.99f, 0.14f), "user-a")
        assertNotNull(hit)
        assertTrue(hit!!.similarity >= 0.90f)
    }

    @Test
    fun `a dissimilar query misses`() = runTest {
        layer.store("what is self attention", floatArrayOf(1f, 0f), "It weights inputs.", "user-a", "fast")
        val miss = layer.lookup("unrelated cooking question", floatArrayOf(0.5f, 0.87f), "user-a")
        assertNull(miss)
    }

    @Test
    fun `one user's cached answer is never served to another`() = runTest {
        val vec = floatArrayOf(1f, 0f)
        layer.store("what is attention", vec, "A's private answer.", "user-a", "fast")
        val crossUser = layer.lookup("what is attention", vec, "user-b")
        assertNull(crossUser)
    }

    @Test
    fun `thumbs down evicts the entry so it is not served again`() = runTest {
        val vec = floatArrayOf(1f, 0f)
        val entryId = layer.store("what is attention", vec, "A weak answer.", "user-a", "fast")
        assertNotNull(entryId)
        layer.feedback(entryId!!, accepted = false, similarity = 0.95f)
        val afterEviction = layer.lookup("what is attention", vec, "user-a")
        assertNull(afterEviction)
        // Threshold nudged up above the rejected similarity.
        assertTrue(SemanticPreference.getCacheThreshold(context) > SemanticPreference.THRESHOLD_INITIAL)
    }

    private fun bookmark(id: String): Bookmark =
        Bookmark(id = id, text = "text for $id", createdAt = 0L, userId = "user-a", title = "Title $id")
}
