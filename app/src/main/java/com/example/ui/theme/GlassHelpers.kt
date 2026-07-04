package com.example.ui.theme

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.composed

/**
 * Performance tiers for dynamic glass rendering:
 * - Full: Includes refraction gradients & specular highlight
 * - Blur: Frosted haze with standard rendering
 * - Solid: High-performance simple opacity card with border highlights
 */
enum class GlassTier { Full, Blur, Solid }

object GlassTokens {
    val containerShape = RoundedCornerShape(24.dp)
    val cardShape = RoundedCornerShape(22.dp)
}

/**
 * Automatically evaluates device capabilities to pick the safest glass rendering tier.
 */
@Composable
fun rememberGlassTier(override: GlassTier? = null): GlassTier {
    if (override != null) return override
    val context = LocalContext.current
    return remember(context) {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val isLowRam = am?.isLowRamDevice == true
        val sdkInt = Build.VERSION.SDK_INT
        when {
            isLowRam || sdkInt < 26 -> GlassTier.Solid
            sdkInt < 31 -> GlassTier.Blur // standard alpha drawing without RenderEffect
            else -> GlassTier.Full // true blur + high-end glass physics
        }
    }
}

/**
 * Custom glass surface modifier leveraging Jetpack Compose primitives.
 *
 * Layers, bottom→top:
 *  1. translucent tint fill (the "frost")
 *  2. a diagonal specular sheen (top-left bright → transparent) — the signature
 *     Apple liquid-glass highlight that makes the panel read as a lit pane of glass
 *  3. a crisp 1px top-edge light line
 *  4. a hairline border
 *
 * We never apply RenderEffect blur to the layer itself — that would blur the
 * child text/icons. The frosting illusion comes from translucency + highlights.
 */
fun Modifier.glassSurface(
    tier: GlassTier,
    shape: Shape = GlassTokens.containerShape,
    tint: Color? = null,
    borderColor: Color? = null,
    edgeSheenColor: Color? = null,
    highlight: Boolean = true
): Modifier = composed {
    // Read the app's resolved theme (honours the in-app Light/Dark override) rather than the raw
    // system setting, so glass frosting matches the Material colors even when they disagree.
    val isDark = LocalCurioDarkTheme.current

    val opacity = when (tier) {
        GlassTier.Full -> if (isDark) 0.34f else 0.20f
        GlassTier.Blur -> if (isDark) 0.26f else 0.14f
        GlassTier.Solid -> if (isDark) 0.42f else 0.26f
    }
    val resolvedTint = tint ?: (if (isDark) Color(0xFF1D1B20).copy(alpha = opacity) else Color.White.copy(alpha = opacity))
    val resolvedBorder = borderColor ?: (if (isDark) Color.White.copy(alpha = 0.14f) else Color.Black.copy(alpha = 0.07f))
    val resolvedSheen = edgeSheenColor ?: (if (isDark) Color.White.copy(alpha = 0.18f) else Color.White.copy(alpha = 0.5f))

    // Specular highlight intensity scales with tier so Solid devices stay cheap.
    val specularTop = if (highlight && tier != GlassTier.Solid) {
        if (isDark) Color.White.copy(alpha = 0.10f) else Color.White.copy(alpha = 0.38f)
    } else Color.Transparent

    this
        .clip(shape)
        .background(
            brush = Brush.verticalGradient(
                colors = listOf(
                    resolvedTint,
                    resolvedTint.copy(alpha = resolvedTint.alpha * 0.65f)
                )
            )
        )
        .background(
            brush = Brush.linearGradient(
                colors = listOf(specularTop, Color.Transparent, Color.Transparent),
                start = Offset.Zero,
                end = Offset(420f, 520f)
            )
        )
        .drawBehind {
            val strokeWidth = 1.dp.toPx()
            drawLine(
                color = resolvedSheen,
                start = Offset(0f, 0f),
                end = Offset(size.width, 0f),
                strokeWidth = strokeWidth * 1.5f
            )
        }
        .border(1.dp, resolvedBorder, shape)
}

/**
 * A vivid, theme-driven accent gradient brush. Pairs the Material You primary
 * with the tertiary for the bold X-style highlight moments (FAB, send button,
 * hero numbers, active chips).
 */
fun curioAccentBrush(primary: Color, tertiary: Color): Brush =
    Brush.linearGradient(
        colors = listOf(primary, lerpToward(primary, tertiary, 0.6f)),
        start = Offset.Zero,
        end = Offset(360f, 360f)
    )

private fun lerpToward(a: Color, b: Color, t: Float): Color =
    Color(
        red = a.red + (b.red - a.red) * t,
        green = a.green + (b.green - a.green) * t,
        blue = a.blue + (b.blue - a.blue) * t,
        alpha = 1f
    )
