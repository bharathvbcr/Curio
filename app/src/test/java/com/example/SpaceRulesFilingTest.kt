package com.example

import com.example.domain.model.Bookmark
import com.example.domain.model.CategorySpaces
import com.example.domain.model.RuleField
import com.example.domain.model.RuleMatch
import com.example.domain.model.RuleOp
import com.example.domain.model.Space
import com.example.domain.model.SpaceRule
import com.example.domain.model.SpaceRules
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Behavioral tests for Smart-Space rule filing: eligible bookmarks (unfiled + AI category Spaces)
 * are swept in; manual user filings are left alone.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class SpaceRulesFilingTest {

    private val uid = "user1"
    private val repo = FakeBookmarkRepository()

    private val agentsRule = SpaceRules(
        match = RuleMatch.ANY,
        autoFile = true,
        rules = listOf(SpaceRule(RuleField.CATEGORY, RuleOp.EQUALS, "agents"))
    )

    private fun bookmark(
        id: String,
        category: String? = null,
        spaceId: String? = null
    ) = Bookmark(
        id = id,
        text = "post $id",
        createdAt = 1L,
        userId = uid,
        category = category,
        spaceId = spaceId
    )

    private fun smartSpace(id: String, rules: SpaceRules = agentsRule) = Space(
        id = id,
        userId = uid,
        name = "Agents",
        color = 0xFF1E88E5,
        icon = "hub",
        createdAt = 1L,
        rules = rules
    )

    @Before
    fun reset() {
        repo.bookmarksFlow.value = emptyList()
        repo.spacesFlow.value = emptyList()
    }

    @Test
    fun `applySpaceRules files bookmarks sitting in category space`() = runTest {
        val smartId = "space_smart_1"
        val catId = "${CategorySpaces.SPACE_ID_PREFIX}${uid}_agents"
        repo.spacesFlow.value = listOf(smartSpace(smartId))
        repo.bookmarksFlow.value = listOf(bookmark("b1", category = "agents", spaceId = catId))

        val count = repo.applySpaceRules(smartId)

        assertEquals(1, count)
        assertEquals(smartId, repo.bookmarksFlow.value.single().spaceId)
    }

    @Test
    fun `applySpaceRules skips manually filed bookmarks`() = runTest {
        val smartId = "space_smart_1"
        val manualId = "space_manual_abc"
        repo.spacesFlow.value = listOf(smartSpace(smartId))
        repo.bookmarksFlow.value = listOf(bookmark("b1", category = "agents", spaceId = manualId))

        val count = repo.applySpaceRules(smartId)

        assertEquals(0, count)
        assertEquals(manualId, repo.bookmarksFlow.value.single().spaceId)
    }

    @Test
    fun `applyRulesToLibrary pulls from category spaces`() = runTest {
        val smartId = "space_smart_1"
        val catId = "${CategorySpaces.SPACE_ID_PREFIX}${uid}_agents"
        repo.spacesFlow.value = listOf(smartSpace(smartId))
        repo.bookmarksFlow.value = listOf(bookmark("b1", category = "agents", spaceId = catId))

        val count = repo.applyRulesToLibrary(uid)

        assertEquals(1, count)
        assertEquals(smartId, repo.bookmarksFlow.value.single().spaceId)
    }

    @Test
    fun `fileByRules can reclaim bookmark from category space`() = runTest {
        val smartId = "space_smart_1"
        val catId = "${CategorySpaces.SPACE_ID_PREFIX}${uid}_agents"
        repo.spacesFlow.value = listOf(smartSpace(smartId))
        val bm = bookmark("b1", category = "agents", spaceId = catId)
        repo.bookmarksFlow.value = listOf(bm)

        val filed = repo.fileByRules(bm)

        assertEquals(smartId, filed)
        assertEquals(smartId, repo.bookmarksFlow.value.single().spaceId)
    }

    @Test
    fun `fileByRules does not override manual space`() = runTest {
        val smartId = "space_smart_1"
        val manualId = "space_manual_abc"
        repo.spacesFlow.value = listOf(smartSpace(smartId))
        val bm = bookmark("b1", category = "agents", spaceId = manualId)
        repo.bookmarksFlow.value = listOf(bm)

        assertNull(repo.fileByRules(bm))
        assertEquals(manualId, repo.bookmarksFlow.value.single().spaceId)
    }
}
