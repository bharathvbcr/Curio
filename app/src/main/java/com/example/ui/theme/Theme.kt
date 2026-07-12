package com.example.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

// Cosmic Slate Theme Palette - Bold, X-inspired contrast with vivid accents.
// (Material You dynamic color still overrides this when available.)
val CosmicPrimary = Color(0xFFB69CFF)        // electric lavender accent
val CosmicSecondary = Color(0xFF7FD7FF)      // cyan secondary pop
val CosmicTertiary = Color(0xFFFF9EC4)        // warm pink tertiary
val CosmicBackgroundDark = Color(0xFF08080C)  // near-black, X-style canvas
val CosmicSurfaceDark = Color(0xFF14131A)

val CosmicPrimaryLight = Color(0xFF6750A4)
val CosmicSecondaryLight = Color(0xFF006A78)
val CosmicTertiaryLight = Color(0xFFB3105E)
val CosmicBackgroundLight = Color(0xFFFBF8FF)
val CosmicSurfaceLight = Color(0xFFFFFFFF)

private val DarkColorScheme = darkColorScheme(
    primary = CosmicPrimary,
    onPrimary = Color(0xFF1F1147),
    primaryContainer = Color(0xFF2C2150),
    onPrimaryContainer = Color(0xFFE9DDFF),
    secondary = CosmicSecondary,
    onSecondary = Color(0xFF00344A),
    tertiary = CosmicTertiary,
    onTertiary = Color(0xFF5A1138),
    background = CosmicBackgroundDark,
    surface = CosmicSurfaceDark,
    surfaceVariant = Color(0xFF211F2A),
    onSurfaceVariant = Color(0xFFC9C5D4),
    onBackground = Color(0xFFF2EFF7),
    onSurface = Color(0xFFF2EFF7),
    outline = Color(0xFF49454F)
)

private val LightColorScheme = lightColorScheme(
    primary = CosmicPrimaryLight,
    secondary = CosmicSecondaryLight,
    tertiary = CosmicTertiaryLight,
    background = CosmicBackgroundLight,
    surface = CosmicSurfaceLight,
    surfaceVariant = Color(0xFFEDE7F4),
    onPrimary = Color.White,
    onSecondary = Color.White,
    onTertiary = Color.White,
    onBackground = Color(0xFF15131C),
    onSurface = Color(0xFF15131C)
)

/**
 * The app's *resolved* dark/light choice (from the in-app AppThemeSetting), not the raw OS
 * setting. Glass surfaces read this instead of [isSystemInDarkTheme] so that forcing Light or
 * Dark in Settings frosts correctly even when it disagrees with the phone's system setting.
 * Defaults to dark (X-style canvas) until [BookmarkTheme] provides the real value.
 */
val LocalCurioDarkTheme = staticCompositionLocalOf { true }

/**
 * Creates an M3 dynamic/static theme with optional seed color styling.
 */
@Composable
fun BookmarkTheme(
    darkTheme: Boolean = true,
    dynamicColor: Boolean = false,
    brandSeed: Color? = null,
    content: @Composable () -> Unit
) {
    val context = LocalContext.current
    val colorScheme: ColorScheme = when {
        // If a brand seed color is provided, we can build custom themes
        brandSeed != null -> {
            if (darkTheme) {
                darkColorScheme(
                    primary = brandSeed,
                    background = CosmicBackgroundDark,
                    surface = CosmicSurfaceDark
                )
            } else {
                lightColorScheme(
                    primary = brandSeed,
                    background = CosmicBackgroundLight,
                    surface = CosmicSurfaceLight
                )
            }
        }
        // Material You dynamic wallpapers
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    CompositionLocalProvider(LocalCurioDarkTheme provides darkTheme) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = Typography,
            content = content
        )
    }
}

