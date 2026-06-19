package com.example.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.example.ui.theme.MyApplicationTheme

/**
 * Curio brand mark: a bookmark ribbon with an AI "spark" knocked out of it.
 *
 * Drawn with the SAME 108x108 geometry as the launcher icon (res/drawable/
 * ic_launcher_foreground.xml), so the in-app logo and the home-screen icon are
 * pixel-identical in shape. The spark is a genuine [PathFillType.EvenOdd] hole,
 * so whatever sits behind the mark shows through it.
 *
 * Theme-aware: [tint] defaults to [MaterialTheme.colorScheme] onSurface, so the
 * mark flips white-on-dark / black-on-light (and follows Material You dynamic
 * color) automatically. Use it bare in headers, or via [CurioLogo] for a badge.
 */
@Composable
fun CurioLogoMark(
    modifier: Modifier = Modifier,
    tint: Color = MaterialTheme.colorScheme.onSurface,
    paddingFraction: Float = 0.04f,
) {
    Canvas(modifier = modifier) {
        drawPath(curioMarkPath(size, paddingFraction), color = tint)
    }
}

/**
 * Curio logo as a self-contained badge: the brand mark on a tinted, rounded
 * tile — the in-app echo of the app icon. The spark cutout reveals the
 * [containerColor] tile behind the mark, exactly like the launcher icon.
 *
 * All colors default to [MaterialTheme.colorScheme], so the badge re-themes with
 * light/dark and Material You. Drop it into a splash or auth header at any size.
 */
@Composable
fun CurioLogo(
    modifier: Modifier = Modifier,
    containerColor: Color = MaterialTheme.colorScheme.primary,
    contentColor: Color = MaterialTheme.colorScheme.onPrimary,
    shape: Shape = RoundedCornerShape(28.dp),
) {
    Box(
        modifier = modifier
            .clip(shape)
            .background(containerColor),
        contentAlignment = Alignment.Center,
    ) {
        // Larger inset so the bookmark breathes inside the tile, matching the
        // safe-zone margin the adaptive launcher icon uses.
        CurioLogoMark(
            modifier = Modifier.fillMaxSize(),
            tint = contentColor,
            paddingFraction = 0.22f,
        )
    }
}

/**
 * Builds the bookmark + spark path, scaled to fit [size] (aspect-preserved,
 * centered) with [paddingFraction] breathing room on the limiting axis.
 * Coordinates are authored in the bookmark's 108-viewport bounding box
 * (x:37..71, y:30..80) so they line up 1:1 with the vector drawable.
 */
private fun curioMarkPath(size: Size, paddingFraction: Float): Path {
    val originX = 37f
    val originY = 30f
    val markW = 34f // 71 - 37
    val markH = 50f // 80 - 30

    val scale = minOf(
        size.width * (1f - 2f * paddingFraction) / markW,
        size.height * (1f - 2f * paddingFraction) / markH,
    )
    val offsetX = (size.width - markW * scale) / 2f
    val offsetY = (size.height - markH * scale) / 2f

    fun x(v: Float) = offsetX + (v - originX) * scale
    fun y(v: Float) = offsetY + (v - originY) * scale

    return Path().apply {
        fillType = PathFillType.EvenOdd

        // Bookmark ribbon with rounded top corners and a V-notch tail.
        moveTo(x(46f), y(30f))
        lineTo(x(62f), y(30f))
        quadraticTo(x(71f), y(30f), x(71f), y(39f))
        lineTo(x(71f), y(80f))
        lineTo(x(54f), y(66f))
        lineTo(x(37f), y(80f))
        lineTo(x(37f), y(39f))
        quadraticTo(x(37f), y(30f), x(46f), y(30f))
        close()

        // Four-point AI spark — knocked out of the ribbon via EvenOdd.
        moveTo(x(54f), y(35f))
        quadraticTo(x(56.40f), y(45.60f), x(67f), y(48f))
        quadraticTo(x(56.40f), y(50.40f), x(54f), y(61f))
        quadraticTo(x(51.60f), y(50.40f), x(41f), y(48f))
        quadraticTo(x(51.60f), y(45.60f), x(54f), y(35f))
        close()
    }
}

@Preview(name = "Logo badge — light", showBackground = true, backgroundColor = 0xFFFEF7FF)
@Preview(name = "Logo badge — dark", showBackground = true, backgroundColor = 0xFF141218)
@Composable
private fun CurioLogoBadgePreview() {
    MyApplicationTheme(dynamicColor = false) {
        CurioLogo(modifier = Modifier.size(96.dp))
    }
}

@Preview(name = "Bare mark — light", showBackground = true, backgroundColor = 0xFFFEF7FF)
@Preview(name = "Bare mark — dark", showBackground = true, backgroundColor = 0xFF141218)
@Composable
private fun CurioLogoMarkPreview() {
    MyApplicationTheme(dynamicColor = false) {
        CurioLogoMark(modifier = Modifier.size(72.dp))
    }
}
