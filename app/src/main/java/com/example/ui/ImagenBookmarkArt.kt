package com.example.ui

import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Bookmarks
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CloudSync
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Psychology
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Screenshot
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Timer
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.window.Dialog
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Label
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.Bookmarks
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.IconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.ui.draw.clip
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.AutoAwesome
import android.content.Intent
import kotlinx.coroutines.launch
import com.example.MainActivity
import com.example.domain.model.AuthState
import com.example.domain.model.Bookmark
import com.example.domain.model.SourceType
import com.example.ui.components.GlassBottomBar
import com.example.ui.components.GlassNavigationItem
import com.example.ui.components.GlassScaffold
import com.example.ui.components.GlassTopBar
import com.example.ui.components.LiquidGlassFab
import com.example.ui.screens.auth.AuthViewModel
import com.example.ui.screens.auth.LoginScreen
import com.example.ui.theme.BookmarkTheme
import com.example.ui.theme.GlassTier
import com.example.ui.theme.glassSurface
import com.example.ui.theme.rememberGlassTier
import com.example.ui.theme.CurioMotion
import com.example.ui.theme.pressBounce
import com.example.ui.theme.bounceScale
import com.example.ui.theme.curioAccentBrush
import coil.compose.AsyncImage
import coil.compose.SubcomposeAsyncImage
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.alpha
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.tween
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Article
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Hub
import androidx.compose.material.icons.automirrored.filled.MenuBook
import java.text.SimpleDateFormat
import java.util.Locale

@Composable
internal fun ImagenBookmarkArt(
    category: String?,
    isGenerated: Boolean,
    onGenerateClick: () -> Unit,
    modifier: Modifier = Modifier,
    imageUrl: String? = null
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.15f))
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f),
                shape = RoundedCornerShape(12.dp)
            )
            .testTag("imagen_art_box"),
        contentAlignment = Alignment.Center
    ) {
        // A real Grok-generated cover takes precedence over the procedural fallback graphic.
        if (isGenerated && !imageUrl.isNullOrBlank()) {
            AsyncImage(
                model = imageUrl,
                contentDescription = "Grok-generated cover for ${category ?: "bookmark"}",
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().testTag("imagen_generated_image")
            )
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(10.dp)
                    .background(Color(0xFF111111).copy(alpha = 0.7f), RoundedCornerShape(6.dp))
                    .padding(horizontal = 8.dp, vertical = 3.dp)
            ) {
                Text(
                    text = "GROK IMAGINE",
                    style = MaterialTheme.typography.labelSmall.copy(
                        fontSize = 8.sp, fontWeight = FontWeight.Black, color = Color.White
                    )
                )
            }
            return@Box
        }
        if (!isGenerated) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier
                    .clickable { onGenerateClick() }
                    .padding(16.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.AutoAwesome,
                    contentDescription = "Generate Imagen visual",
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(28.dp)
                )
                Text(
                    text = "GENERATE IMAGEN VISUAL REPRESENTATION",
                    style = MaterialTheme.typography.labelSmall.copy(
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 1.sp,
                        color = MaterialTheme.colorScheme.primary
                    )
                )
                Text(
                    text = "Distinguish categories or content types elegantly",
                    style = MaterialTheme.typography.bodySmall.copy(fontSize = 10.sp),
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                )
            }
        } else {
            val cleanCategory = category?.trim()?.lowercase() ?: "tech"
            
            // Custom category colors
            val gradColors = when (cleanCategory) {
                "development" -> listOf(Color(0xFF2196F3), Color(0xFF00BCD4))
                "design" -> listOf(Color(0xFF9C27B0), Color(0xFFE91E63))
                "crypto", "blockchain" -> listOf(Color(0xFFFF9800), Color(0xFFFFC107))
                "business", "marketing" -> listOf(Color(0xFF4CAF50), Color(0xFF009688))
                "life", "personal" -> listOf(Color(0xFFE91E63), Color(0xFFFF5722))
                else -> listOf(Color(0xFF607D8B), Color(0xFF9E9E9E))
            }
            
            androidx.compose.foundation.Canvas(
                modifier = Modifier.fillMaxSize()
            ) {
                val w = size.width
                val h = size.height
                
                // Draw radial background gradient
                drawRect(
                    brush = Brush.radialGradient(
                        colors = listOf(gradColors[0].copy(alpha = 0.45f), gradColors[1].copy(alpha = 0.1f)),
                        center = Offset(w / 2f, h / 2f),
                        radius = w
                    )
                )
                
                // Drawing dynamic content-themed icons or shapes
                when (cleanCategory) {
                    "development" -> {
                        val linesCount = 8
                        for (i in 0..linesCount) {
                            val x = (w / linesCount) * i
                            drawLine(
                                color = gradColors[0].copy(alpha = 0.15f),
                                start = Offset(x, 0f),
                                end = Offset(x, h),
                                strokeWidth = 1f
                            )
                        }
                        drawCircle(
                            color = gradColors[1].copy(alpha = 0.35f),
                            radius = 35f,
                            center = Offset(w * 0.4f, h * 0.5f)
                        )
                        drawCircle(
                            color = gradColors[0].copy(alpha = 0.25f),
                            radius = 20f,
                            center = Offset(w * 0.6f, h * 0.35f)
                        )
                    }
                    "design" -> {
                        drawCircle(
                            color = gradColors[0].copy(alpha = 0.35f),
                            radius = 45f,
                            center = Offset(w * 0.35f, h * 0.6f)
                        )
                        drawCircle(
                            color = gradColors[1].copy(alpha = 0.35f),
                            radius = 35f,
                            center = Offset(w * 0.6f, h * 0.45f)
                        )
                    }
                    "crypto", "blockchain" -> {
                        drawCircle(
                            color = gradColors[0].copy(alpha = 0.1f),
                            radius = 55f,
                            center = Offset(w / 2f, h / 2f)
                        )
                        drawCircle(
                            color = gradColors[1].copy(alpha = 0.2f),
                            radius = 35f,
                            center = Offset(w / 2f, h / 2f)
                        )
                        drawCircle(
                            color = gradColors[0].copy(alpha = 0.4f),
                            radius = 18f,
                            center = Offset(w / 2f, h / 2f)
                        )
                    }
                    "business", "marketing" -> {
                        drawLine(
                            color = gradColors[0].copy(alpha = 0.4f),
                            start = Offset(w * 0.2f, h * 0.8f),
                            end = Offset(w * 0.4f, h * 0.6f),
                            strokeWidth = 6f
                        )
                        drawLine(
                            color = gradColors[0].copy(alpha = 0.4f),
                            start = Offset(w * 0.4f, h * 0.6f),
                            end = Offset(w * 0.6f, h * 0.65f),
                            strokeWidth = 6f
                        )
                        drawLine(
                            color = gradColors[1].copy(alpha = 0.5f),
                            start = Offset(w * 0.6f, h * 0.65f),
                            end = Offset(w * 0.8f, h * 0.3f),
                            strokeWidth = 8f
                        )
                    }
                    else -> {
                        drawCircle(
                            color = gradColors[0].copy(alpha = 0.15f),
                            radius = 50f,
                            center = Offset(w / 2f, h / 2f)
                        )
                        drawCircle(
                            color = gradColors[1].copy(alpha = 0.35f),
                            radius = 15f,
                            center = Offset(w * 0.35f, h * 0.4f)
                        )
                        drawCircle(
                            color = gradColors[0].copy(alpha = 0.35f),
                            radius = 15f,
                            center = Offset(w * 0.65f, h * 0.6f)
                        )
                    }
                }
            }
            
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(10.dp)
                    .background(
                        color = gradColors[0].copy(alpha = 0.85f),
                        shape = RoundedCornerShape(6.dp)
                    )
                    .padding(horizontal = 8.dp, vertical = 3.dp)
            ) {
                Text(
                    text = "IMAGEN ACTIVE",
                    style = MaterialTheme.typography.labelSmall.copy(
                        fontSize = 8.sp,
                        fontWeight = FontWeight.Black,
                        color = Color.White
                    ),
                    modifier = Modifier.testTag("imagen_active_badge")
                )
            }
            
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
                modifier = Modifier.padding(16.dp)
            ) {
                Text(
                    text = (category ?: "CURATED CONTENT").uppercase(),
                    style = MaterialTheme.typography.titleMedium.copy(
                        fontWeight = FontWeight.Black,
                        color = Color.White,
                        letterSpacing = 2.sp
                    )
                )
                Text(
                    text = "REPRESENTATIVE GENERATIVE GRAPHIC",
                    style = MaterialTheme.typography.labelSmall.copy(
                        fontSize = 8.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White.copy(alpha = 0.7f),
                        letterSpacing = 1.sp
                    )
                )
            }
        }
    }
}
