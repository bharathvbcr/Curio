package com.example

import com.example.domain.model.Bookmark
import com.example.domain.model.SourceType
import com.example.ui.authorInitial
import com.example.ui.cleanSnippet
import com.example.ui.displayAuthor
import com.example.ui.readingTime
import com.example.ui.sourceDisplayName
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Pure formatting helpers used across the feed/cards. */
@RunWith(RobolectricTestRunner)
@Config(manifest = Config.NONE)
class CurioFormatTest {

    private fun bm(
        sourceType: SourceType? = null,
        authorName: String? = null,
        url: String? = null
    ) = Bookmark(id = "1", text = "t", createdAt = 1_700_000_000_000L, userId = "u",
        sourceType = sourceType, authorName = authorName, url = url)

    private fun words(n: Int) = (1..n).joinToString(" ") { "word" }

    @Test
    fun `readingTime null for short posts, scales by word count`() {
        assertNull(readingTime("a short note"))
        assertNull(readingTime(words(39)))
        assertEquals("1 min read", readingTime(words(50)))   // 50/200 -> round 0 -> floored to 1
        assertEquals("3 min read", readingTime(words(600)))  // 600/200 -> 3
    }

    @Test
    fun `cleanSnippet strips urls but keeps a pure-url post intact`() {
        val s = cleanSnippet("read this https://example.com/x/y now")
        assertTrue(s.contains("read this"))
        assertTrue(s.contains("now"))
        assertTrue(!s.contains("http"))
        // Stripping a URL-only post would blank it, so it falls back to the original.
        assertEquals("https://example.com", cleanSnippet("https://example.com"))
    }

    @Test
    fun `sourceDisplayName maps known sources and falls back to host`() {
        assertEquals("arXiv", sourceDisplayName(bm(sourceType = SourceType.ARXIV)))
        assertEquals("GitHub", sourceDisplayName(bm(sourceType = SourceType.GITHUB)))
        assertEquals("Hugging Face", sourceDisplayName(bm(sourceType = SourceType.HUGGING_FACE)))
        assertEquals("DOI", sourceDisplayName(bm(sourceType = SourceType.DOI)))
        assertEquals("example.com", sourceDisplayName(bm(url = "https://www.example.com/post/1")))
        assertEquals("Curio", sourceDisplayName(bm()))
    }

    @Test
    fun `authorInitial only for tweet-like entries`() {
        assertNull(authorInitial(bm(sourceType = SourceType.ARXIV, authorName = "Albert Gu")))
        assertEquals('E', authorInitial(bm(authorName = "elon")))
        assertNull(authorInitial(bm())) // no author
    }

    @Test
    fun `displayAuthor prefers real author then source`() {
        assertEquals("Ada Lovelace", displayAuthor(bm(authorName = "Ada Lovelace")))
        assertEquals("GitHub", displayAuthor(bm(sourceType = SourceType.GITHUB)))
    }
}
