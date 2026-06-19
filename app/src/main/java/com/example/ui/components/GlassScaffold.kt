package com.example.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.example.ui.theme.GlassTier
import com.example.ui.theme.rememberGlassTier
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeEffect
import dev.chrisbanes.haze.hazeSource

/**
 * Standard Material 3 Scaffold with responsive liquid-glass panel integrations.
 *
 * Glass blur is driven by a SINGLE hoisted [HazeState]: the scrollable content registers as the
 * blur source ([hazeSource]) and the top/bottom bars sample it ([hazeEffect]) so they show a real
 * frosted backdrop of the content behind them. On the [GlassTier.Solid] tier (low-RAM / older
 * devices) the haze effect is skipped entirely to stay cheap — the bars fall back to the opaque
 * `glassSurface` tint.
 */
@Composable
fun GlassScaffold(
    modifier: Modifier = Modifier,
    topBar: @Composable (GlassTier) -> Unit = {},
    bottomBar: @Composable (GlassTier) -> Unit = {},
    floatingActionButton: @Composable (GlassTier) -> Unit = {},
    content: @Composable (PaddingValues, GlassTier) -> Unit
) {
    val tier = rememberGlassTier()
    val hazeState = remember { HazeState() }
    val blurEnabled = tier != GlassTier.Solid
    // Haze 1.x requires the backdrop color of the area behind the blur; without it the effect
    // throws "backgroundColor not specified" at draw time.
    val backdropColor = MaterialTheme.colorScheme.surface

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            Box(modifier = if (blurEnabled) Modifier.hazeEffect(hazeState) { backgroundColor = backdropColor } else Modifier) { topBar(tier) }
        },
        bottomBar = {
            Box(modifier = if (blurEnabled) Modifier.hazeEffect(hazeState) { backgroundColor = backdropColor } else Modifier) { bottomBar(tier) }
        },
        floatingActionButton = { floatingActionButton(tier) },
        contentWindowInsets = WindowInsets.navigationBars
    ) { innerPadding ->
        Box(modifier = if (blurEnabled) Modifier.hazeSource(hazeState) else Modifier) {
            content(innerPadding, tier)
        }
    }
}
