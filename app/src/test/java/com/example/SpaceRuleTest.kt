package com.example

import com.example.domain.model.Bookmark
import com.example.domain.model.RuleField
import com.example.domain.model.RuleMatch
import com.example.domain.model.RuleOp
import com.example.domain.model.SourceType
import com.example.domain.model.SpaceRule
import com.example.domain.model.SpaceRules
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Tests the Smart Spaces auto-filing predicate ([SpaceRule]/[SpaceRules]) and its JSON codec.
 * This logic decides which bookmarks get filed into a Space, so correctness matters; it was untested.
 * Robolectric supplies the real org.json used by toJson/fromJson.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class SpaceRuleTest {

    private fun bm(
        text: String = "",
        title: String? = null,
        summary: String? = null,
        ocrText: String? = null,
        sourceTitle: String? = null,
        sourceAbstract: String? = null,
        tags: List<String> = emptyList(),
        category: String? = null,
        sourceType: SourceType? = null,
        authorName: String? = null,
        authorUsername: String? = null,
        sourceAuthors: String? = null,
        url: String? = null
    ) = Bookmark(
        id = "1", text = text, createdAt = 1_700_000_000_000L, userId = "u",
        title = title, summary = summary, ocrText = ocrText, sourceTitle = sourceTitle,
        sourceAbstract = sourceAbstract, tags = tags, category = category, sourceType = sourceType,
        authorName = authorName, authorUsername = authorUsername, sourceAuthors = sourceAuthors, url = url
    )

    @Test
    fun `keyword contains is case-insensitive across text fields`() {
        val rule = SpaceRule(RuleField.KEYWORD, RuleOp.CONTAINS, "Diffusion")
        assertTrue(rule.matches(bm(text = "a paper on latent diffusion models")))
        assertTrue(rule.matches(bm(sourceAbstract = "We study DIFFUSION sampling")))
        assertFalse(rule.matches(bm(text = "a paper on transformers")))
    }

    @Test
    fun `blank value never matches`() {
        assertFalse(SpaceRule(RuleField.KEYWORD, RuleOp.CONTAINS, "   ").matches(bm(text = "anything")))
    }

    @Test
    fun `each field is inspected`() {
        assertTrue(SpaceRule(RuleField.TAG, RuleOp.EQUALS, "mamba").matches(bm(tags = listOf("ssm", "Mamba"))))
        assertTrue(SpaceRule(RuleField.CATEGORY, RuleOp.EQUALS, "architectures").matches(bm(category = "Architectures")))
        assertTrue(SpaceRule(RuleField.SOURCE, RuleOp.EQUALS, "arxiv").matches(bm(sourceType = SourceType.ARXIV)))
        assertTrue(SpaceRule(RuleField.AUTHOR, RuleOp.CONTAINS, "gu").matches(bm(sourceAuthors = "Albert Gu, Tri Dao")))
        assertTrue(SpaceRule(RuleField.URL, RuleOp.STARTS_WITH, "https://github").matches(bm(url = "https://github.com/x/y")))
    }

    @Test
    fun `ops behave distinctly`() {
        val b = bm(title = "FlashAttention")
        assertTrue(SpaceRule(RuleField.KEYWORD, RuleOp.STARTS_WITH, "flash").matches(b))
        assertFalse(SpaceRule(RuleField.KEYWORD, RuleOp.EQUALS, "flash").matches(b))
        assertTrue(SpaceRule(RuleField.KEYWORD, RuleOp.EQUALS, "flashattention").matches(b))
    }

    @Test
    fun `rule set ANY vs ALL`() {
        val r1 = SpaceRule(RuleField.TAG, RuleOp.EQUALS, "rag")
        val r2 = SpaceRule(RuleField.CATEGORY, RuleOp.EQUALS, "agents")
        val b = bm(tags = listOf("rag"), category = "evals") // matches r1 only
        assertTrue(SpaceRules(RuleMatch.ANY, true, listOf(r1, r2)).matches(b))
        assertFalse(SpaceRules(RuleMatch.ALL, true, listOf(r1, r2)).matches(b))
    }

    @Test
    fun `inactive when all rules are drafts`() {
        val draftsOnly = SpaceRules(RuleMatch.ANY, true, listOf(SpaceRule(RuleField.TAG, RuleOp.EQUALS, "")))
        assertFalse(draftsOnly.isActive)
        assertFalse(draftsOnly.matches(bm(tags = listOf("anything"))))
        assertFalse(SpaceRules.EMPTY.matches(bm(text = "x")))
    }

    @Test
    fun `match score prefers more specific smart space`() {
        val broad = SpaceRule(RuleField.CATEGORY, RuleOp.EQUALS, "agents")
        val narrow1 = SpaceRule(RuleField.TAG, RuleOp.EQUALS, "rag")
        val narrow2 = SpaceRule(RuleField.CATEGORY, RuleOp.EQUALS, "agents")
        val b = bm(tags = listOf("rag"), category = "agents")
        val broadRules = SpaceRules(RuleMatch.ANY, true, listOf(broad))
        val narrowRules = SpaceRules(RuleMatch.ALL, true, listOf(narrow1, narrow2))
        assertTrue(broadRules.matches(b))
        assertTrue(narrowRules.matches(b))
        assertEquals(1, broadRules.matchScore(b))
        assertEquals(2, narrowRules.matchScore(b))
    }

    @Test
    fun `json round-trips and parsing is tolerant`() {
        val rules = SpaceRules(
            RuleMatch.ALL, autoFile = false,
            rules = listOf(
                SpaceRule(RuleField.KEYWORD, RuleOp.CONTAINS, "diffusion"),
                SpaceRule(RuleField.SOURCE, RuleOp.EQUALS, "ARXIV")
            )
        )
        val restored = SpaceRules.fromJson(rules.toJson())
        assertEquals(RuleMatch.ALL, restored.match)
        assertFalse(restored.autoFile)
        assertEquals(2, restored.rules.size)
        assertEquals("diffusion", restored.rules[0].value)

        // Tolerant: blank/garbage/unknown-enum inputs degrade to EMPTY or skip the bad rule.
        assertEquals(SpaceRules.EMPTY, SpaceRules.fromJson(null))
        assertEquals(SpaceRules.EMPTY, SpaceRules.fromJson("not json"))
        assertTrue(SpaceRules.fromJson("""{"m":"ANY","a":true,"r":[{"f":"BOGUS","o":"EQUALS","v":"x"}]}""").rules.isEmpty())
    }
}
