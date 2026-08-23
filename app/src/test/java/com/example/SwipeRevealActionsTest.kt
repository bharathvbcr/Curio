package com.example

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.dp
import com.example.ui.components.SwipeRevealActions
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Gesture + state-machine stress tests for the swipe-to-reveal card actions: the destructive
 * path must REQUIRE reveal → arm ("Sure?") → confirm, early releases must spring back inert,
 * and mode flips / external closes must never strand the card mid-swipe.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], qualifiers = "w400dp-h800dp")
class SwipeRevealActionsTest {

    @get:Rule
    val composeRule = createComposeRule()

    private val containerTag = "swipe_container"
    private val deleteDockTag = "swipe_delete_test"

    @androidx.compose.runtime.Composable
    private fun content() = Box(
        Modifier
            .fillMaxWidth()
            .height(96.dp)
            .testTag("card_content")
    )

    @Test
    fun `reveal then arm then confirm deletes - full two-step sequence`() {
        var deleted = false
        composeRule.setContent {
            SwipeRevealActions(
                modifier = Modifier.testTag(containerTag),
                revealed = true,
                onRevealChange = {},
                onDelete = { deleted = true },
                onReadLater = {},
                deleteTestTag = deleteDockTag,
                content = { content() }
            )
        }

        composeRule.onNodeWithTag(deleteDockTag).assertIsDisplayed()
        // Tap 1: arm — nothing deletes yet.
        composeRule.onNodeWithTag(deleteDockTag).performClick()
        composeRule.onNodeWithText("Sure?").assertIsDisplayed()
        assertFalse("arming must not delete", deleted)
        // Tap 2 within the disarm window: confirm.
        composeRule.onNodeWithTag(deleteDockTag).performClick()
        assertTrue("second tap must confirm", deleted)
    }

    @Test
    fun `short left drag springs back without revealing`() {
        var deleted = false
        var revealedEvents = 0
        composeRule.setContent {
            SwipeRevealActions(
                modifier = Modifier.testTag(containerTag),
                revealed = false,
                onRevealChange = { if (it) revealedEvents++ },
                onDelete = { deleted = true },
                onReadLater = {},
                deleteTestTag = deleteDockTag,
                content = { content() }
            )
        }

        // ~30dp nudge: well under the 45%-of-104dp reveal threshold.
        composeRule.onNodeWithTag(containerTag).performTouchInput {
            down(center)
            moveBy(Offset(-30.dp.toPx(), 0f))
            up()
        }
        composeRule.waitForIdle()

        assertFalse("short drag must not delete", deleted)
        assertEquals("short drag must not pin the dock", 0, revealedEvents)
    }

    @Test
    fun `committed right swipe toggles read later exactly once and closes`() {
        var toggles = 0
        composeRule.setContent {
            SwipeRevealActions(
                modifier = Modifier.testTag(containerTag),
                revealed = false,
                onRevealChange = {},
                onDelete = {},
                onReadLater = { toggles++ },
                content = { content() }
            )
        }

        composeRule.onNodeWithTag(containerTag).performTouchInput {
            down(center)
            moveBy(Offset(120.dp.toPx(), 0f))
            up()
        }
        composeRule.waitForIdle()

        assertEquals("one committed right swipe = one toggle", 1, toggles)
    }

    @Test
    fun `external close collapses an open dock`() {
        var deleted = false
        val revealed = mutableStateOf(true)
        composeRule.setContent {
            SwipeRevealActions(
                modifier = Modifier.testTag(containerTag),
                revealed = revealed.value,
                onRevealChange = { revealed.value = it },
                onDelete = { deleted = true },
                onReadLater = {},
                deleteTestTag = deleteDockTag,
                content = { content() }
            )
        }
        composeRule.onNodeWithTag(deleteDockTag).assertIsDisplayed()

        revealed.value = false
        composeRule.waitForIdle()

        // Dock gone from composition once progress hits zero; a stray tap can't confirm.
        composeRule.onNodeWithTag(deleteDockTag).assertDoesNotExist()
        assertFalse(deleted)

        // Re-opening requires the full arm→confirm cycle again (armed was reset).
        revealed.value = true
        composeRule.waitForIdle()
        composeRule.onNodeWithTag(deleteDockTag).performClick()
        composeRule.onNodeWithText("Sure?").assertIsDisplayed()
    }

    @Test
    fun `gestures disabled swallows swipes entirely`() {
        var deleted = false
        var readLater = false
        composeRule.setContent {
            SwipeRevealActions(
                modifier = Modifier.testTag(containerTag),
                revealed = false,
                onRevealChange = {},
                onDelete = { deleted = true },
                onReadLater = { readLater = true },
                gesturesEnabled = false,
                deleteTestTag = deleteDockTag,
                content = { content() }
            )
        }

        composeRule.onNodeWithTag(containerTag).performTouchInput {
            down(center)
            moveBy(Offset(-300.dp.toPx(), 0f))
            up()
        }
        composeRule.waitForIdle()

        assertFalse(deleted)
        assertFalse(readLater)
        composeRule.onNodeWithTag(deleteDockTag).assertDoesNotExist()
    }

    @Test
    fun `gesture layer removed mid-drag recovers instead of freezing`() {
        var deleted = false
        val enabled = mutableStateOf(true)
        composeRule.setContent {
            SwipeRevealActions(
                modifier = Modifier.testTag(containerTag),
                revealed = false,
                onRevealChange = {},
                onDelete = { deleted = true },
                onReadLater = {},
                gesturesEnabled = enabled.value,
                deleteTestTag = deleteDockTag,
                content = { content() }
            )
        }

        // Drag past the reveal threshold, then yank the gesture layer before release —
        // onDragStopped will never fire, so the recovery effect must spring the card back.
        composeRule.onNodeWithTag(containerTag).performTouchInput {
            down(center)
            moveBy(Offset(-120.dp.toPx(), 0f))
        }
        enabled.value = false
        composeRule.waitForIdle()
        composeRule.runOnUiThread { /* let the recovery LaunchedEffect settle */ }
        composeRule.waitForIdle()

        composeRule.onNodeWithTag(deleteDockTag).assertDoesNotExist()
        assertFalse(deleted)
    }

    @Test
    fun `rapid alternating swipes stay consistent`() {
        var toggles = 0
        composeRule.setContent {
            SwipeRevealActions(
                modifier = Modifier.testTag(containerTag),
                revealed = false,
                onRevealChange = {},
                onDelete = {},
                onReadLater = { toggles++ },
                content = { content() }
            )
        }
        // Alternate inert nudges with committed right swipes; every step must leave the
        // container alive and exactly the committed ones may fire a toggle.
        val steps = listOf(-60f, 130f, -60f, 140f)
        for ((index, dxDp) in steps.withIndex()) {
            composeRule.onNodeWithTag(containerTag)
                .assertExists("container vanished before step $index")
            composeRule.onNodeWithTag(containerTag).performTouchInput {
                down(center)
                moveBy(Offset(dxDp.dp.toPx(), 0f))
                up()
            }
            composeRule.waitForIdle()
            composeRule.onNodeWithTag(containerTag)
                .assertExists("container vanished after step $index")
        }
        assertEquals(2, toggles)
    }
}
