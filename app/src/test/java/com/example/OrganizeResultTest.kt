package com.example

import com.example.domain.model.OrganizeResult
import com.example.domain.model.SpaceSuggestion
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OrganizeResultTest {

    @Test
    fun `EMPTY has no feedback`() {
        assertFalse(OrganizeResult.EMPTY.hasFeedback)
        assertNull(OrganizeResult.EMPTY.announceMessage())
    }

    @Test
    fun `announceMessage covers auto-file new-space and suggestion counts`() {
        val result = OrganizeResult(
            autoFiled = 2,
            newSpaces = 1,
            suggestions = listOf(
                SpaceSuggestion("a", "s1", "Agents", 0.55f),
                SpaceSuggestion("b", "s2", "Training", 0.52f)
            )
        )
        assertTrue(result.hasFeedback)
        assertEquals(
            "Auto-organised — filed 2, created 1 space, 2 suggestions",
            result.announceMessage()
        )
    }

    @Test
    fun `announceMessage uses singular forms`() {
        val result = OrganizeResult(
            autoFiled = 0,
            newSpaces = 0,
            suggestions = listOf(SpaceSuggestion("a", "s1", "Agents", 0.55f))
        )
        assertEquals("Auto-organised — 1 suggestion", result.announceMessage())
    }
}
