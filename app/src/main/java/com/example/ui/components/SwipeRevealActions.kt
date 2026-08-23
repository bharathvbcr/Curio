package com.example.ui.components

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.WatchLater
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.example.ui.theme.CurioMotion
import com.example.ui.theme.motionSpec
import com.example.ui.theme.tappable
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * Swipe-to-**reveal** container — a safer replacement for swipe-to-dismiss.
 *
 * The old feed used `SwipeToDismissBox`: a single full left swipe deleted a card outright, so a
 * stray gesture while scrolling could silently drop a bookmark (Undo snackbar notwithstanding).
 * This component never deletes from the gesture itself:
 *
 * - **Left swipe** slides the card aside to expose a pinned Delete dock. Releasing early springs
 *   back; nothing is deleted. The dock then needs a tap to **arm** ("Sure?") and a second tap to
 *   confirm — a gesture + two deliberate taps, matching the two-step confirms used elsewhere
 *   (card options sheet, bulk bar).
 * - **Right swipe** remains an instant read-later toggle: reversible and non-destructive, so no
 *   confirm is needed. A tinted indicator tracks the finger and the toggle fires past a threshold.
 *
 * Only one card in a list should be revealed at a time: the parent hoists the revealed id and
 * passes [revealed] / [onRevealChange] so sibling cards close when this one opens.
 */
@Composable
internal fun SwipeRevealActions(
    /** External control of the open state; when it flips to `false` the card springs closed. */
    revealed: Boolean,
    /** Reports settle events: `true` once the Delete dock has sprung open, `false` once closed. */
    onRevealChange: (Boolean) -> Unit,
    /** Called only after the dock's two-tap arm→confirm sequence. */
    onDelete: () -> Unit,
    /** Instant read-later toggle fired by a committed right swipe. */
    onReadLater: () -> Unit,
    modifier: Modifier = Modifier,
    /** Mirrors the bookmark's saved-for-later state so the right-swipe label stays truthful. */
    readLaterActive: Boolean = false,
    /** Disables all swipe gestures (selection / reorder modes) without removing the content. */
    gesturesEnabled: Boolean = true,
    deleteTestTag: String? = null,
    content: @Composable () -> Unit
) {
    val density = LocalDensity.current
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val cs = MaterialTheme.colorScheme

    val dockWidth = 104.dp
    val dockWidthPx = with(density) { dockWidth.toPx() }
    val readLaterTriggerPx = with(density) { 88.dp.toPx() }
    val maxRightPx = readLaterTriggerPx * 1.5f

    val offsetX = remember { Animatable(0f) }
    var armed by remember { mutableStateOf(false) }
    // Explicit <Float> — motionSpec/snappy are generic and have no expected type to infer from here.
    val settleSpec = motionSpec<Float>(CurioMotion.snappy())

    // External control: close springs back + disarms; open pins the dock at full width so a
    // parent-driven reveal (restore, programmatic open) composes the dock too.
    LaunchedEffect(revealed) {
        if (!revealed) {
            armed = false
            if (offsetX.value != 0f) offsetX.animateTo(0f, settleSpec)
        } else if (offsetX.value > -dockWidthPx) {
            armed = false
            offsetX.animateTo(-dockWidthPx, settleSpec)
        }
    }

    // Gesture layer removed while the finger is still dragging (e.g. selection mode entered
    // mid-swipe) → onDragStopped never fires, leaving the card frozen partially swiped.
    LaunchedEffect(gesturesEnabled) {
        if (!gesturesEnabled && offsetX.value != 0f) {
            offsetX.animateTo(0f, settleSpec)
            onRevealChange(false)
        }
    }

    // The armed "Sure?" state can't linger — auto-disarm so a later stray tap can't confirm.
    LaunchedEffect(armed) {
        if (armed) {
            delay(2_800)
            armed = false
        }
    }

    fun settle() {
        // Decisions must observe the FINAL drag position: per-delta snapTo launches are queued
        // on the same scope, so reading inside this launch sees the settled value instead of a
        // stale mid-flick sample (which mis-settled very fast swipes).
        scope.launch {
            val x = offsetX.value
            when {
                // Past roughly half the dock → spring open and pin the Delete dock.
                x < -dockWidthPx * 0.45f -> {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    offsetX.animateTo(-dockWidthPx, settleSpec)
                    onRevealChange(true)
                }
                // Committed right swipe → instant (reversible) read-later toggle, then close.
                x > readLaterTriggerPx -> {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    onReadLater()
                    offsetX.animateTo(0f, settleSpec)
                    onRevealChange(false)
                }
                else -> {
                    offsetX.animateTo(0f, settleSpec)
                    onRevealChange(false)
                }
            }
        }
    }

    val dragState = rememberDraggableState { delta ->
        scope.launch {
            val next = (offsetX.value + delta).coerceIn(-dockWidthPx * 1.12f, maxRightPx)
            offsetX.snapTo(next)
        }
    }

    val revealProgress = (-offsetX.value / dockWidthPx).coerceIn(0f, 1f)
    val readLaterProgress = (offsetX.value / readLaterTriggerPx).coerceIn(0f, 1f)

    Box(
        modifier = modifier
            .fillMaxWidth()
            .then(
                if (gesturesEnabled) {
                    Modifier.draggable(
                        state = dragState,
                        orientation = Orientation.Horizontal,
                        onDragStopped = { settle() }
                    )
                } else Modifier
            )
            // Gesture-only affordances are invisible to TalkBack — expose the same two
            // actions as labeled accessibility actions so they're reachable without swiping.
            .semantics {
                customActions = listOf(
                    androidx.compose.ui.semantics.CustomAccessibilityAction("Delete bookmark") {
                        onDelete()
                        true
                    },
                    androidx.compose.ui.semantics.CustomAccessibilityAction(
                        if (readLaterActive) "Remove from read later" else "Save for later"
                    ) {
                        onReadLater()
                        true
                    }
                )
            }
    ) {
        // ── ACTION BACKDROP (behind the sliding card) ──
        Box(
            modifier = Modifier
                .matchParentSize()
                .clip(RoundedCornerShape(22.dp))
        ) {
            // Right-swipe: read-later indicator (gesture-driven, no tap target).
            if (readLaterProgress > 0f) {
                Row(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(cs.secondary.copy(alpha = 0.12f + 0.10f * readLaterProgress))
                        .padding(start = 24.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.alpha(readLaterProgress)
                    ) {
                        Icon(
                            Icons.Filled.WatchLater,
                            contentDescription = null,
                            tint = cs.secondary,
                            modifier = Modifier.size(22.dp)
                        )
                        Text(
                            text = if (readLaterActive) "Remove" else "Read later",
                            style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Black),
                            color = cs.secondary,
                            modifier = Modifier.padding(start = 8.dp)
                        )
                    }
                }
            }

            // Left-swipe: pinned Delete dock — tap to arm, tap again to confirm.
            if (revealProgress > 0f) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(cs.error.copy(alpha = 0.08f + 0.10f * revealProgress))
                )
                Column(
                    modifier = Modifier
                        .align(Alignment.CenterEnd)
                        .width(dockWidth)
                        .fillMaxHeight()
                        .clip(RoundedCornerShape(22.dp))
                        .background(
                            if (armed) cs.error.copy(alpha = 0.92f)
                            else cs.error.copy(alpha = 0.10f + 0.14f * revealProgress)
                        )
                        .semantics {
                            contentDescription =
                                if (armed) "Confirm delete bookmark" else "Delete bookmark"
                        }
                        .tappable(role = Role.Button) {
                            when {
                                // Mostly-closed sliver tapped → finish opening instead of arming.
                                offsetX.value > -dockWidthPx * 0.75f -> scope.launch {
                                    offsetX.animateTo(-dockWidthPx, settleSpec)
                                    onRevealChange(true)
                                }
                                !armed -> armed = true
                                else -> onDelete()
                            }
                        }
                        .then(if (deleteTestTag != null) Modifier.testTag(deleteTestTag) else Modifier),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center
                ) {
                    Icon(
                        Icons.Filled.Delete,
                        contentDescription = null,
                        tint = if (armed) cs.onError else cs.error,
                        modifier = Modifier.size(22.dp)
                    )
                    Text(
                        text = if (armed) "Sure?" else "Delete",
                        style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black),
                        color = if (armed) cs.onError else cs.error,
                        modifier = Modifier.padding(top = 4.dp)
                    )
                }
            }
        }

        // ── SLIDING CARD ──
        Box(modifier = Modifier.offset { IntOffset(offsetX.value.roundToInt(), 0) }) {
            content()
            // While revealed, the card's own taps are swallowed: tapping it just closes the dock
            // (standard iOS Mail behaviour) instead of expanding the card underneath the finger.
            if (revealProgress > 0.05f) {
                Box(
                    modifier = Modifier
                        .matchParentSize()
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            onClick = {
                                scope.launch {
                                    offsetX.animateTo(0f, settleSpec)
                                    onRevealChange(false)
                                }
                            }
                        )
                )
            }
        }
    }
}