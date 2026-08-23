package com.example

import com.example.data.semantic.RagCompressor
import com.example.domain.model.Bookmark
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Stress tests for the RAG MMR compressor: CJK token estimation (4 chars/token is a Latin
 * heuristic — Chinese/Japanese run ~1 char/token), plus adversarial inputs (empty embeddings,
 * oversized single items, degenerate budgets) must terminate and never return an empty context
 * when any candidate exists.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class RagCompressorStressTest {

    private fun bm(text: String, title: String? = null) = Bookmark(
        id = text.take(8), text = text, createdAt = 1L, userId = "u1", title = title
    )

    private fun unit() = FloatArray(8) { 0.35f } // non-empty placeholder vector

    @Test
    fun `cjk text estimates roughly one token per character`() {
        val cjk = "深度学习改变了自然语言处理的研究范式并且持续高速发展"
        val latin = "a".repeat(cjk.length)
        val cjkTokens = RagCompressor().estimateTokens(bm(cjk))
        val latinTokens = RagCompressor().estimateTokens(bm(latin))
        assertTrue(
            "CJK $cjkTokens tokens vs Latin $latinTokens for same char count — CJK must not be divided by 4",
            cjkTokens >= latinTokens * 3
        )
    }

    @Test
    fun `mixed cjk-latin estimates exceed latin-only estimate`() {
        val mixed = "Transformers在NLP中占主导地位since2017"
        val latin = "x".repeat(mixed.length)
        assertTrue(
            RagCompressor().estimateTokens(bm(mixed)) > RagCompressor().estimateTokens(bm(latin))
        )
    }

    @Test
    fun `empty embedding candidates pass through untouched`() {
        val compressor = RagCompressor(maxTokens = 10)
        val out = compressor.compress(unit(), listOf(bm("no vector") to FloatArray(0)))
        assertEquals(1, out.size)
    }

    @Test
    fun `single item larger than budget is still admitted once`() {
        val compressor = RagCompressor(maxTokens = 1)
        val out = compressor.compress(unit(), listOf(bm("huge context block") to unit()))
        assertEquals(1, out.size)
    }

    @Test
    fun `zero budget with multiple items never returns empty`() {
        val compressor = RagCompressor(maxTokens = 0)
        val out = compressor.compress(
            unit(),
            listOf(bm("alpha beta") to unit(), bm("gamma delta") to unit())
        )
        assertTrue(out.isNotEmpty())
    }

    @Test
    fun `large corpus terminates under budget`() {
        val compressor = RagCompressor(maxTokens = 64)
        val scored = (0 until 500).map { bm("item number $it padding padding padding") to unit().clone() }
        val out = compressor.compress(unit(), scored)
        assertTrue(out.isNotEmpty())
        assertTrue(out.size < scored.size) // budget actually bit
    }

    @Test
    fun `duplicate near-identical items are diversity-suppressed`() {
        val compressor = RagCompressor(lambda = 0.5f, maxTokens = 4096)
        val v = unit()
        // Single-hot vector: still relevant to the all-0.35 query (~0.35 cosine, above the
        // default 0.25 floor) but far from the duplicate pair's direction.
        val distinct = FloatArray(8) { i -> if (i == 7) 0.9f else 0f }
        val scored = listOf(
            bm("identical one") to v,
            bm("identical two") to v.clone(),
            bm("unique different topic") to distinct
        )
        val out = compressor.compress(unit(), scored)
        assertTrue("expected diversity selection", out.any { it.text == "unique different topic" })
    }
}
