package com.example

import com.example.data.embedding.EmbeddingText
import com.example.domain.model.Bookmark
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.ExecutionException

class EmbeddingTextTest {

    @Test
    fun `clipForOnDevice trims and caps at MAX_EMBED_CHARS`() {
        val long = "a".repeat(600)
        assertEquals(EmbeddingText.MAX_EMBED_CHARS, EmbeddingText.clipForOnDevice("  $long  ").length)
    }

    @Test
    fun `chunksForDocument respects chunk char limit`() {
        val b = Bookmark(
            id = "1",
            text = "x".repeat(2000),
            createdAt = 0L,
            userId = "u",
            summary = "s".repeat(600)
        )
        val chunks = EmbeddingText.chunksForDocument(b)
        assertTrue(chunks.all { it.length <= EmbeddingText.MAX_EMBED_CHARS })
        assertTrue(chunks.size <= 4)
    }

    @Test
    fun `cloud chunks can be larger than on-device chunks`() {
        val b = Bookmark(id = "1", text = "y".repeat(2500), createdAt = 0L, userId = "u")
        val onDevice = EmbeddingText.chunksForDocument(b)
        val cloud = EmbeddingText.chunksForDocument(b, EmbeddingText.CLOUD_CHUNK_CHARS)
        assertTrue(cloud.any { it.length > EmbeddingText.MAX_EMBED_CHARS })
        assertTrue(onDevice.all { it.length <= EmbeddingText.MAX_EMBED_CHARS })
    }

    @Test
    fun `meanPool averages same-dimension vectors`() {
        val pooled = EmbeddingText.meanPool(
            listOf(floatArrayOf(2f, 4f), floatArrayOf(0f, 0f))
        )!!
        assertEquals(1f, pooled[0], 1e-5f)
        assertEquals(2f, pooled[1], 1e-5f)
    }

    @Test
    fun `isTokenLimitError detects seq256 overflow message`() {
        val root = RuntimeException("token.size() + 2 <= max_input_size (261 vs 256)")
        val wrapped = ExecutionException(root)
        assertTrue(EmbeddingText.isTokenLimitError(wrapped))
    }

    @Test
    fun `isTokenLimitError ignores unrelated failures`() {
        assertFalse(EmbeddingText.isTokenLimitError(IllegalStateException("network down")))
    }
}
