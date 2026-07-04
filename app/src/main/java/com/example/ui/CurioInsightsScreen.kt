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
import androidx.compose.material.icons.filled.Workspaces
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
import androidx.lifecycle.compose.collectAsStateWithLifecycle
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
import com.example.ui.theme.motionSpec
import com.example.ui.theme.pressBounce
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
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
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Hub
import androidx.compose.material.icons.automirrored.filled.MenuBook
import java.text.SimpleDateFormat
import java.util.Locale

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun CurioInsightsScreen(
    viewModel: BookmarkViewModel,
    tier: GlassTier,
    onNavigateToFeed: () -> Unit,
    onNavigateToSettings: () -> Unit = {}
) {
    val stats by viewModel.stats.collectAsStateWithLifecycle()
    val spaces by viewModel.spaces.collectAsStateWithLifecycle()
    val digest by viewModel.digestState.collectAsStateWithLifecycle()
    val rediscover by viewModel.rediscoverPicks.collectAsStateWithLifecycle()
    var play by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { play = true }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item { Spacer(Modifier.height(8.dp)) }

        // HERO
        item {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(26.dp))
                    .background(curioAccentBrush(MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.tertiary))
                    .padding(22.dp)
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("YOUR RESEARCH INDEX", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, letterSpacing = 1.5.sp), color = Color.White.copy(alpha = 0.85f))
                    if (stats.totalCount == 0) {
                        Text("Start building your index", style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Black), color = Color.White)
                        Text("Sync bookmarks from X to unlock insights, digests, and AI chat.", style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold), color = Color.White.copy(alpha = 0.85f))
                        Spacer(Modifier.height(8.dp))
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(14.dp))
                                .background(Color.White.copy(alpha = 0.2f))
                                .pressBounce(onClick = onNavigateToFeed)
                                .padding(horizontal = 16.dp, vertical = 10.dp)
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Icon(Icons.Default.Sync, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
                                Text("GO TO BOOKMARKS", style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black), color = Color.White)
                            }
                        }
                    } else {
                    Text("${stats.totalCount}", style = MaterialTheme.typography.displayLarge.copy(fontSize = 72.sp, fontWeight = FontWeight.Black, lineHeight = 74.sp, letterSpacing = (-3).sp), color = Color.White)
                    val pct = stats.curatedCount.toFloat() / stats.totalCount
                    val animPct by animateFloatAsState(if (play) pct else 0f, motionSpec(CurioMotion.liquid()), label = "heroPct")
                    Text("${stats.curatedCount} AI-curated · ${(pct * 100).toInt()}% complete", style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold), color = Color.White.copy(alpha = 0.9f))
                    Spacer(Modifier.height(6.dp))
                    Box(modifier = Modifier
                        .fillMaxWidth().height(8.dp).clip(RoundedCornerShape(50))
                        .background(Color.White.copy(alpha = 0.25f))
                        .semantics { stateDescription = "${(pct * 100).toInt()} percent curated" }
                    ) {
                        Box(modifier = Modifier.fillMaxWidth(animPct).fillMaxHeight().clip(RoundedCornerShape(50)).background(Color.White))
                    }
                    }
                }
            }
        }

        // STAT TILES
        item {
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                StatTile("OCR Syncs", stats.ocrCount.toString(), Icons.Default.Screenshot, MaterialTheme.colorScheme.secondary, tier, Modifier.weight(1f)) {
                    viewModel.clearAllFilters(); viewModel.setLibraryFilter(LibraryFilter.HAS_OCR); onNavigateToFeed()
                }
                StatTile("Sources", stats.sourceCount.toString(), Icons.Default.Hub, MaterialTheme.colorScheme.primary, tier, Modifier.weight(1f)) {
                    viewModel.clearAllFilters(); viewModel.setLibraryFilter(LibraryFilter.HAS_SOURCE); onNavigateToFeed()
                }
                StatTile("Deep", stats.deepAnalyzedCount.toString(), Icons.Default.AutoAwesome, MaterialTheme.colorScheme.tertiary, tier, Modifier.weight(1f)) {
                    viewModel.clearAllFilters(); viewModel.setLibraryFilter(LibraryFilter.DEEP_ANALYZED); onNavigateToFeed()
                }
            }
        }

        // WEEKLY AI DIGEST — themed Grok summary of the last 7 days of saves
        item {
            WeeklyDigestCard(
                state = digest,
                tier = tier,
                onGenerate = { viewModel.generateWeeklyDigest() },
                onDismiss = { viewModel.dismissDigest() },
                onNavigateToSettings = onNavigateToSettings,
                onNavigateToFeed = onNavigateToFeed
            )
        }

        // REDISCOVER — resurface older, not-yet-starred saves worth revisiting
        if (rediscover.isNotEmpty()) {
            item {
                RediscoverCard(
                    picks = rediscover,
                    tier = tier,
                    onShuffle = { viewModel.shuffleRediscover() }
                )
            }
        }

        // SPACE DISTRIBUTION — how the index is split across the user's Spaces
        item {
            Box(modifier = Modifier.fillMaxWidth().glassSurface(tier = tier).padding(18.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Default.Workspaces, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
                        Text("SPACE DISTRIBUTION", style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black), color = MaterialTheme.colorScheme.primary)
                    }
                    val populatedSpaces = spaces.filter { it.count > 0 }.sortedByDescending { it.count }
                    if (populatedSpaces.isEmpty()) {
                        Text("No filed bookmarks yet. Curate a bookmark or add it to a Space to populate this view.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(14.dp))
                                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f))
                                .pressBounce(onClick = onNavigateToFeed)
                                .padding(horizontal = 14.dp, vertical = 8.dp)
                        ) {
                            Text("GO TO BOOKMARKS", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black), color = MaterialTheme.colorScheme.primary)
                        }
                    } else {
                        populatedSpaces.forEach { space ->
                            val pct = if (stats.totalCount > 0) space.count.toFloat() / stats.totalCount else 0f
                            val animW by animateFloatAsState(if (play) pct else 0f, motionSpec(CurioMotion.liquid()), label = "bar_${space.id}")
                            val color = Color(space.color)
                            Column(
                                verticalArrangement = Arrangement.spacedBy(5.dp),
                                modifier = Modifier
                                    .clip(RoundedCornerShape(10.dp))
                                    .pressBounce { viewModel.clearAllFilters(); viewModel.selectSpace(space.id); onNavigateToFeed() }
                            ) {
                                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                    Row(horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically, modifier = Modifier.weight(1f)) {
                                        Icon(spaceIcon(space.icon), contentDescription = null, tint = color, modifier = Modifier.size(13.dp))
                                        Text(space.name.uppercase(), style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold), color = MaterialTheme.colorScheme.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    }
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Text("${space.count} · ${(pct * 100).toInt()}%", style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold), color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f))
                                        Icon(Icons.Default.ChevronRight, contentDescription = "Filter feed to this Space", tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f), modifier = Modifier.size(16.dp))
                                    }
                                }
                                Box(modifier = Modifier.fillMaxWidth().height(9.dp).clip(RoundedCornerShape(50)).background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f))) {
                                    Box(modifier = Modifier.fillMaxWidth(animW).fillMaxHeight().clip(RoundedCornerShape(50)).background(Brush.horizontalGradient(listOf(color.copy(alpha = 0.7f), color))))
                                }
                            }
                        }
                    }
                }
            }
        }

        // HOT TAGS
        item {
            Box(modifier = Modifier.fillMaxWidth().glassSurface(tier = tier).padding(18.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Default.LocalFireDepartment, contentDescription = null, tint = MaterialTheme.colorScheme.tertiary, modifier = Modifier.size(18.dp))
                        Text("HOT TOPICS", style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black), color = MaterialTheme.colorScheme.tertiary)
                    }
                    if (stats.topTags.isEmpty()) {
                        Text("No tags yet. Curate bookmarks to surface trending topics.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(14.dp))
                                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f))
                                .pressBounce(onClick = onNavigateToFeed)
                                .padding(horizontal = 14.dp, vertical = 8.dp)
                        ) {
                            Text("GO TO BOOKMARKS", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black), color = MaterialTheme.colorScheme.primary)
                        }
                    } else {
                        val maxCount = (stats.topTags.maxOfOrNull { it.second } ?: 1).coerceAtLeast(1)
                        FlowRow(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            stats.topTags.forEach { (tag, count) ->
                                val intensity = count.toFloat() / maxCount
                                Row(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(50))
                                        .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.08f + intensity * 0.22f))
                                        .pressBounce { viewModel.clearAllFilters(); viewModel.selectTag(tag); onNavigateToFeed() }
                                        .padding(horizontal = 12.dp, vertical = 7.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(5.dp)
                                ) {
                                    Text("#$tag", style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black), color = MaterialTheme.colorScheme.primary)
                                    Text(count.toString(), style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold), color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f))
                                }
                            }
                        }
                    }
                }
            }
        }

        item { Spacer(Modifier.height(80.dp)) }
    }
}

/**
 * On-demand weekly AI digest card. Renders the [DigestUiState] machine: a generate prompt when idle,
 * a spinner while Grok works, the rendered markdown when ready, and explicit empty/error states.
 */
@Composable
private fun WeeklyDigestCard(
    state: DigestUiState,
    tier: GlassTier,
    onGenerate: () -> Unit,
    onDismiss: () -> Unit,
    onNavigateToSettings: () -> Unit = {},
    onNavigateToFeed: () -> Unit = {}
) {
    val accent = MaterialTheme.colorScheme.tertiary
    val context = LocalContext.current
    Box(modifier = Modifier.fillMaxWidth().glassSurface(tier = tier).padding(18.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Default.AutoAwesome, contentDescription = null, tint = accent, modifier = Modifier.size(18.dp))
                Text(
                    "WEEKLY DIGEST",
                    style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black, letterSpacing = 0.8.sp),
                    color = accent
                )
                Spacer(Modifier.weight(1f))
                if (state is DigestUiState.Ready) {
                    Text(
                        "${state.itemCount} saves",
                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                    )
                }
            }

            when (state) {
                is DigestUiState.Idle -> {
                    Text(
                        "Get a themed AI summary of what you saved this week — grouped by theme, with what's worth a closer look.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f)
                    )
                    DigestActionButton("GENERATE DIGEST", accent, onGenerate)
                }
                is DigestUiState.Loading -> {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp, color = accent)
                        Text(
                            "Reading your week…",
                            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold),
                            color = MaterialTheme.colorScheme.onSurface
                        )
                    }
                }
                is DigestUiState.Ready -> {
                    MarkdownText(
                        markdown = state.markdown,
                        style = MaterialTheme.typography.bodySmall.copy(lineHeight = 19.sp),
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.92f),
                        accent = accent
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        DigestActionButton("REGENERATE", accent, onGenerate, modifier = Modifier.weight(1f))
                        DigestActionButton("COPY", accent, { copyToClipboard(context, state.markdown, "Weekly Digest") }, modifier = Modifier.weight(1f))
                        DigestActionButton("SHARE", accent, { shareBookmark(context, state.markdown) }, modifier = Modifier.weight(1f))
                    }
                    DigestActionButton("DISMISS", MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f), onDismiss, filled = false, modifier = Modifier.fillMaxWidth())
                }
                is DigestUiState.Empty -> {
                    Text(
                        state.reason,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f)
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        DigestActionButton("GO TO BOOKMARKS", accent, onNavigateToFeed, modifier = Modifier.weight(1f))
                        DigestActionButton("DISMISS", MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f), onDismiss, filled = false, modifier = Modifier.weight(1f))
                    }
                }
                is DigestUiState.Error -> {
                    Text(
                        state.message,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        DigestActionButton("TRY AGAIN", accent, onGenerate, modifier = Modifier.weight(1f))
                        if (state.message.contains("key", ignoreCase = true) || state.message.contains("auth", ignoreCase = true) || state.message.contains("sign in", ignoreCase = true)) {
                            DigestActionButton("SETTINGS", MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f), onNavigateToSettings, filled = false, modifier = Modifier.weight(1f))
                        }
                    }
                }
            }
        }
    }
}

/**
 * Resurfacing card: shows a few older, un-starred saves (with a source link) to bring forgotten
 * research back into view. Tapping a row opens its link; the shuffle icon rotates to the next batch.
 */
@Composable
private fun RediscoverCard(
    picks: List<Bookmark>,
    tier: GlassTier,
    onShuffle: () -> Unit
) {
    val context = LocalContext.current
    val accent = MaterialTheme.colorScheme.secondary
    Box(modifier = Modifier.fillMaxWidth().glassSurface(tier = tier).padding(18.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Default.Refresh, contentDescription = null, tint = accent, modifier = Modifier.size(18.dp))
                Text(
                    "REDISCOVER",
                    style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black, letterSpacing = 0.8.sp),
                    color = accent
                )
                Spacer(Modifier.weight(1f))
                Text(
                    "SHUFFLE",
                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black),
                    color = accent,
                    modifier = Modifier
                        .clip(RoundedCornerShape(10.dp))
                        .pressBounce(onClick = onShuffle)
                        .padding(horizontal = 12.dp, vertical = 10.dp)
                )
            }
            Text(
                "Saves you haven't starred — worth a second look.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
            )
            picks.forEach { b ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(accent.copy(alpha = 0.06f))
                        .pressBounce { openUrl(context, b.url) }
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            text = b.sourceTitle?.takeIf { it.isNotBlank() } ?: b.title?.takeIf { it.isNotBlank() } ?: b.text.take(80).trim(),
                            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold, lineHeight = 18.sp),
                            color = MaterialTheme.colorScheme.onSurface,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text(
                            text = "${sourceDisplayName(b)} · saved ${relativeTime(b.createdAt)}",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Icon(Icons.Default.Link, contentDescription = null, tint = accent, modifier = Modifier.size(16.dp))
                        Icon(Icons.Default.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f), modifier = Modifier.size(16.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun DigestActionButton(
    label: String,
    accent: Color,
    onClick: () -> Unit,
    filled: Boolean = true,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .height(48.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(if (filled) accent else accent.copy(alpha = 0.12f))
            .pressBounce(onClick = onClick)
            .padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            label,
            style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black, letterSpacing = 0.5.sp),
            color = if (filled) MaterialTheme.colorScheme.onTertiary else accent
        )
    }
}
