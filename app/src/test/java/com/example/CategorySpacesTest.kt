package com.example

import com.example.domain.model.CategorySpaces
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CategorySpacesTest {

    @Test
    fun `known category returns canonical meta`() {
        val meta = CategorySpaces.forCategory("architectures")
        assertEquals("Architectures", meta.name)
        assertEquals(0xFF1E88E5, meta.color)
        assertEquals("hub", meta.icon)
    }

    @Test
    fun `custom category title-cases and uses fallback appearance`() {
        val meta = CategorySpaces.forCategory("my-custom_topic")
        assertEquals("My Custom Topic", meta.name)
        assertEquals(0xFF607D8B, meta.color)
        assertEquals("label", meta.icon)
    }

    @Test
    fun `blank custom category becomes Uncategorized`() {
        val meta = CategorySpaces.forCategory("   ")
        assertEquals("Uncategorized", meta.name)
    }

    @Test
    fun `category space ids are recognized`() {
        assertTrue(CategorySpaces.isCategorySpaceId("space_cat_user123_agents"))
        assertFalse(CategorySpaces.isCategorySpaceId("space_abc-def"))
        assertFalse(CategorySpaces.isCategorySpaceId(null))
    }

    @Test
    fun `rule filing eligibility includes unfiled and category spaces only`() {
        assertTrue(CategorySpaces.bookmarkEligibleForRuleFiling(null))
        assertTrue(CategorySpaces.bookmarkEligibleForRuleFiling(""))
        assertTrue(CategorySpaces.bookmarkEligibleForRuleFiling("space_cat_u_agents"))
        assertFalse(CategorySpaces.bookmarkEligibleForRuleFiling("space_manual_abc"))
    }
}
