package com.example.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.example.ui.theme.GlassTier
import com.example.ui.theme.glassSurface
import com.example.ui.theme.pressBounce

/**
 * Liquid-glass Floating Action Button with an iOS-style bouncy press response
 * and a soft accent-tinted frosted body.
 */
@Composable
fun LiquidGlassFab(
    onClick: () -> Unit,
    tier: GlassTier,
    modifier: Modifier = Modifier,
    icon: @Composable () -> Unit = {
        Icon(
            imageVector = Icons.Default.Sync,
            contentDescription = "Sync",
            tint = MaterialTheme.colorScheme.primary
        )
    }
) {
    Box(
        modifier = modifier
            .size(64.dp)
            .glassSurface(
                tier = tier,
                shape = CircleShape,
                tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.24f),
                borderColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.4f),
                edgeSheenColor = Color.White.copy(alpha = 0.55f)
            )
            .clip(CircleShape)
            .pressBounce(pressedScale = 0.86f, onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        icon()
    }
}
