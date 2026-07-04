package com.example.ui.components

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.example.ui.theme.GlassTier
import com.example.ui.theme.glassSurface
import com.example.ui.theme.rememberReduceMotion

/**
 * Animated shimmer brush that sweeps a soft highlight across a placeholder. Falls back to a
 * static tint when the user has reduce-motion enabled (no perpetual animation).
 */
@Composable
private fun rememberShimmerBrush(): Brush {
    val base = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)
    val highlight = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.16f)
    if (rememberReduceMotion()) {
        return Brush.linearGradient(listOf(base, base))
    }
    val transition = rememberInfiniteTransition(label = "skeletonShimmer")
    val x by transition.animateFloat(
        initialValue = -600f,
        targetValue = 600f,
        animationSpec = infiniteRepeatable(
            animation = tween(1100, easing = androidx.compose.animation.core.LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "skeletonShimmerX"
    )
    return Brush.linearGradient(
        colors = listOf(base, highlight, base),
        start = Offset(x, 0f),
        end = Offset(x + 300f, 300f)
    )
}

@Composable
private fun ShimmerBlock(modifier: Modifier, shape: Shape = RoundedCornerShape(6.dp)) {
    Box(modifier = modifier.clip(shape).background(rememberShimmerBrush()))
}

/**
 * A single placeholder shaped like a [com.example.ui.CurioPostCard] — avatar, two header lines,
 * a couple of body lines and a media block — used while the very first sync loads so the feed
 * shows structured motion instead of the "your archive is empty" call-to-action.
 */
@Composable
private fun SkeletonCard(tier: GlassTier) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .glassSurface(tier = tier, shape = RoundedCornerShape(22.dp))
            .padding(16.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(11.dp)) {
                ShimmerBlock(Modifier.size(44.dp), shape = CircleShape)
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    ShimmerBlock(Modifier.width(140.dp).height(13.dp))
                    ShimmerBlock(Modifier.width(90.dp).height(11.dp))
                }
            }
            ShimmerBlock(Modifier.fillMaxWidth().height(12.dp))
            ShimmerBlock(Modifier.fillMaxWidth(0.85f).height(12.dp))
            ShimmerBlock(Modifier.fillMaxWidth().height(90.dp), shape = RoundedCornerShape(16.dp))
        }
    }
}

/**
 * A short stack of shimmering [SkeletonCard]s for the first-load state of the bookmark feed.
 */
@Composable
fun CurioSkeletonList(tier: GlassTier, count: Int = 3) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .semantics { contentDescription = "Loading your bookmarks" },
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        repeat(count) { SkeletonCard(tier) }
        Spacer(Modifier.height(4.dp))
    }
}
