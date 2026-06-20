package com.example.ui.theme

import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.EaseInOutCubic
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.scale
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role

/**
 * Curio motion language — iOS-flavoured liquid & bouncy springs.
 *
 * The whole app should feel physical: things overshoot a touch, settle softly,
 * and react to the finger. These specs are deliberately tuned to mimic the
 * UIKit spring feel (gentle overshoot, low stiffness) rather than Material's
 * comparatively rigid defaults.
 */
object CurioMotion {

    /** Lively overshoot — great for appearance, FABs, selection pops. */
    fun <T> bouncy(): SpringSpec<T> =
        spring(dampingRatio = 0.52f, stiffness = Spring.StiffnessMediumLow)

    /** A softer, classier bounce for content size / expansion changes. */
    fun <T> liquid(): SpringSpec<T> =
        spring(dampingRatio = 0.72f, stiffness = Spring.StiffnessLow)

    /** Quick, controlled response for press feedback. */
    fun <T> snappy(): SpringSpec<T> =
        spring(dampingRatio = 0.78f, stiffness = Spring.StiffnessMedium)

    /** Almost no overshoot — for things that must not look jiggly. */
    fun <T> gentle(): SpringSpec<T> =
        spring(dampingRatio = 0.9f, stiffness = Spring.StiffnessMediumLow)

    /** Smooth fade timing used to pair with spring movement. */
    fun <T> fade(): AnimationSpec<T> = tween(durationMillis = 240, easing = EaseInOutCubic)
}

/**
 * iOS-style "press to shrink, release to spring back" tap feedback.
 * Removes the Material ripple and replaces it with a tactile scale bounce.
 */
fun Modifier.pressBounce(
    pressedScale: Float = 0.94f,
    enabled: Boolean = true,
    // Defaults make every bounce-press control announce as a Button to accessibility services and
    // emit a light haptic tick — both were missing app-wide. Pass role = null to opt out.
    role: Role? = Role.Button,
    haptic: Boolean = true,
    onClick: () -> Unit
): Modifier = composed {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val haptics = LocalHapticFeedback.current
    val scale by animateFloatAsState(
        targetValue = if (pressed) pressedScale else 1f,
        animationSpec = CurioMotion.bouncy(),
        label = "pressBounceScale"
    )
    this
        .scale(scale)
        .clickable(
            interactionSource = interaction,
            indication = null,
            enabled = enabled,
            role = role,
            onClick = {
                if (haptic) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                onClick()
            }
        )
}

/**
 * Animates an element's scale toward [target] with a bouncy spring without
 * consuming the click — useful for selection / active states layered on top of
 * other gesture handling (e.g. combinedClickable).
 */
fun Modifier.bounceScale(active: Boolean, activeScale: Float = 1.04f): Modifier = composed {
    val scale by animateFloatAsState(
        targetValue = if (active) activeScale else 1f,
        animationSpec = CurioMotion.bouncy(),
        label = "bounceScaleState"
    )
    this.scale(scale)
}

/** Content-size spring used for expand/collapse reveals. */
fun <T> curioExpandSpec(): FiniteAnimationSpec<T> = CurioMotion.liquid()
