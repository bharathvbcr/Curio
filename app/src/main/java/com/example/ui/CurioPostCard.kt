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
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Favorite
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.WatchLater
import androidx.compose.material.icons.outlined.Workspaces
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.IconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.ui.graphics.vector.ImageVector
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
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
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
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.WatchLater
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.OpenInNew
import androidx.compose.material.icons.filled.Workspaces
import android.content.Intent
import kotlinx.coroutines.launch
import com.example.MainActivity
import com.example.domain.model.AuthState
import com.example.domain.model.Bookmark
import com.example.domain.model.Space
import com.example.domain.model.SpaceRules
import com.example.domain.model.CategorySpaces
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
import com.example.ui.theme.rememberReduceMotion
import com.example.ui.theme.minTouchTarget
import com.example.ui.theme.tappable
import com.example.ui.theme.CurioColors
import androidx.compose.foundation.selection.toggleable
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
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
import androidx.compose.material.icons.filled.AddTask
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material.icons.filled.Schedule
import com.example.interop.ChronosReminderChoice
import java.text.SimpleDateFormat
import java.util.Locale

@OptIn(ExperimentalLayoutApi::class, ExperimentalFoundationApi::class)
@Composable
internal fun CurioPostCard(
    bookmark: Bookmark,
    actions: CurioCardActions,
    spaces: List<Space>,
    isProcessing: Boolean,
    isAnalysisError: Boolean = false,
    analysisErrorMessage: String? = null,
    isImagenGenerated: Boolean,
    imagenUrl: String?,
    tier: GlassTier,
    isSelected: Boolean,
    onToggleSelect: () -> Unit,
    inSelectionMode: Boolean,
    isReorderMode: Boolean = false,
    onMoveUp: () -> Unit = {},
    onMoveDown: () -> Unit = {},
    onBookmarkClick: () -> Unit = {},
    chronosFlowInstalled: Boolean = false,
    /** Embedding-derived Space this unfiled card likely belongs in; shown as a tap-to-file pill. */
    suggestedSpace: Space? = null
) {
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    var isExpanded by remember { mutableStateOf(false) }
    var showOptions by remember { mutableStateOf(false) }
    var showSpacePicker by remember { mutableStateOf(false) }
    var showNewSpaceForCard by remember { mutableStateOf(false) }
    var showNotesEditor by remember { mutableStateOf(false) }

    // Close any open child dialogs when the card collapses so they don't linger
    // in a detached state after the expanded section has animated away.
    LaunchedEffect(isExpanded) {
        if (!isExpanded) {
            showNotesEditor = false
            showSpacePicker = false
            showNewSpaceForCard = false
        }
    }

    val isProcessingThisCard = isProcessing

    val imageLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        uri?.let {
            try {
                val bitmap = if (Build.VERSION.SDK_INT < 28) {
                    @Suppress("DEPRECATION")
                    MediaStore.Images.Media.getBitmap(context.contentResolver, it)
                } else {
                    ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, it))
                }
                actions.onProcessOcr(bitmap)
            } catch (e: Exception) { /* ignore */ }
        }
    }

    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val pressScale by animateFloatAsState(if (pressed) 0.975f else 1f, CurioMotion.snappy(), label = "cardPressScale")
    val chevronRotation by animateFloatAsState(if (isExpanded) 180f else 0f, CurioMotion.liquid(), label = "chevronRot")

    // The Space a bookmark is filed in drives its accent + footer pill; categories now seed Spaces
    // and no longer surface directly in the card.
    val currentSpace = remember(spaces, bookmark.spaceId) { spaces.firstOrNull { it.id == bookmark.spaceId } }
    val accent = currentSpace?.let { Color(it.color) }
        ?: if (!bookmark.category.isNullOrBlank()) getCategoryColor(bookmark.category) else MaterialTheme.colorScheme.primary
    val srcColor = CurioColors.sourceAccent(bookmark.sourceType, fallback = accent)

    val shareableText = remember(bookmark.isAnalyzed, bookmark.title, bookmark.category, bookmark.tags, bookmark.summary, bookmark.text) {
        if (bookmark.isAnalyzed) {
            "📌 ${bookmark.title ?: "Curio bookmark"}\nCategory: ${bookmark.category ?: "General"}\nTags: ${bookmark.tags.joinToString { "#$it" }}\n\n${bookmark.summary ?: ""}\n\n${bookmark.text}"
        } else bookmark.text
    }

    // Permalink back to the original X post (null for manual/non-tweet entries).
    val tweetLink = tweetUrl(bookmark)

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .scale(pressScale)
            .clip(RoundedCornerShape(22.dp))
            .combinedClickable(
                interactionSource = interaction,
                indication = null,
                onLongClick = { if (inSelectionMode) onToggleSelect() else showOptions = true },
                onClick = { if (inSelectionMode) onToggleSelect() else isExpanded = !isExpanded }
            )
            .glassSurface(
                tier = tier,
                shape = RoundedCornerShape(22.dp),
                tint = when {
                    isSelected -> MaterialTheme.colorScheme.primary.copy(alpha = 0.16f)
                    bookmark.isAnalyzed -> MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.10f)
                    else -> null
                },
                borderColor = if (isSelected) MaterialTheme.colorScheme.primary else null
            )
            .testTag("bookmark_card_${bookmark.id}")
    ) {
        // Category accent edge — a vivid left stripe that makes categories scannable.
        Box(modifier = Modifier.matchParentSize()) {
            Box(
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .fillMaxHeight()
                    .width(4.dp)
                    .background(Brush.verticalGradient(listOf(accent.copy(alpha = 0.9f), accent.copy(alpha = 0.35f))))
            )
        }
        Column(
            modifier = Modifier
                .animateContentSize(animationSpec = CurioMotion.liquid())
                .padding(start = 16.dp, top = 14.dp, end = 14.dp, bottom = 14.dp),
            verticalArrangement = Arrangement.spacedBy(11.dp)
        ) {
            // ── HEADER: selection ring · avatar · name/handle · time · chevron ──
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(11.dp),
                verticalAlignment = Alignment.Top
            ) {
                // Selection ring — only rendered in selection mode (it used to sit on every card
                // at low alpha: pure clutter outside multi-select). Enter selection via the card's
                // ⋯ sheet → Select; rings then animate in on all cards. The 20dp ring is the
                // visual; the tap area is expanded to the 48dp minimum and exposes proper
                // checkbox role + checked/unchecked state so TalkBack announces it correctly.
                AnimatedVisibility(visible = inSelectionMode) {
                    Box(
                        modifier = Modifier
                            .minTouchTarget()
                            .semantics { stateDescription = if (isSelected) "Selected" else "Not selected" }
                            .toggleable(
                                value = isSelected,
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                                role = Role.Checkbox,
                                onValueChange = { onToggleSelect() }
                            )
                            .testTag("bookmark_select_checkbox_${bookmark.id}"),
                        contentAlignment = Alignment.Center
                    ) {
                        Box(
                            modifier = Modifier
                                .size(20.dp)
                                .bounceScale(isSelected)
                                .border(
                                    width = 1.5.dp,
                                    color = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f),
                                    shape = CircleShape
                                )
                                .background(if (isSelected) MaterialTheme.colorScheme.primary else Color.Transparent, CircleShape),
                            contentAlignment = Alignment.Center
                        ) {
                            if (isSelected) Icon(Icons.Default.Check, contentDescription = null, modifier = Modifier.size(11.dp), tint = MaterialTheme.colorScheme.onPrimary)
                        }
                    }
                }

                // Author avatar — gradient disc with a real-author initial or source glyph
                val avatarInitial = authorInitial(bookmark)
                Box(
                    modifier = Modifier
                        .size(44.dp)
                        .clip(CircleShape)
                        .background(Brush.linearGradient(listOf(srcColor.copy(alpha = 0.95f), srcColor.copy(alpha = 0.5f)))),
                    contentAlignment = Alignment.Center
                ) {
                    if (avatarInitial != null) {
                        Text(
                            text = avatarInitial.toString(),
                            style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black),
                            color = Color.White
                        )
                    } else {
                        val glyph = when (bookmark.sourceType) {
                            SourceType.GITHUB -> Icons.Filled.Hub
                            SourceType.ARXIV -> Icons.AutoMirrored.Filled.MenuBook
                            SourceType.HUGGING_FACE -> Icons.Filled.AutoAwesome
                            else -> Icons.Filled.Bookmarks
                        }
                        Icon(glyph, contentDescription = null, tint = Color.White, modifier = Modifier.size(22.dp))
                    }
                }

                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                        Text(
                            text = displayAuthor(bookmark),
                            style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Black),
                            color = MaterialTheme.colorScheme.onSurface,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        if (bookmark.isAnalyzed) {
                            Icon(Icons.Default.AutoAwesome, contentDescription = "AI curated", modifier = Modifier.size(13.dp), tint = MaterialTheme.colorScheme.primary)
                        } else if (isProcessing) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                                // Announce curation start/finish to TalkBack without stealing focus.
                                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }
                            ) {
                                CircularProgressIndicator(modifier = Modifier.size(11.dp), strokeWidth = 1.5.dp, color = MaterialTheme.colorScheme.primary)
                                Text("Curating…", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold), color = MaterialTheme.colorScheme.primary)
                            }
                        }
                        Spacer(Modifier.weight(1f))
                        Text(
                            text = relativeTime(bookmark.createdAt),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        // Reorder / expand controls keep their small glyphs but restore the default
                        // 48dp IconButton hit area (they were forced to 26dp — well under the minimum).
                        if (isReorderMode) {
                            IconButton(onClick = onMoveUp, modifier = Modifier.testTag("move_up_button_${bookmark.id}")) {
                                Icon(Icons.Default.KeyboardArrowUp, contentDescription = "Move up", modifier = Modifier.size(20.dp), tint = MaterialTheme.colorScheme.primary)
                            }
                            IconButton(onClick = onMoveDown, modifier = Modifier.testTag("move_down_button_${bookmark.id}")) {
                                Icon(Icons.Default.KeyboardArrowDown, contentDescription = "Move down", modifier = Modifier.size(20.dp), tint = MaterialTheme.colorScheme.primary)
                            }
                        } else {
                            IconButton(onClick = { isExpanded = !isExpanded }, modifier = Modifier.testTag("expand_button_${bookmark.id}")) {
                                Icon(Icons.Default.ExpandMore, contentDescription = if (isExpanded) "Collapse" else "Expand", modifier = Modifier.size(22.dp).rotate(chevronRotation), tint = MaterialTheme.colorScheme.primary)
                            }
                        }
                    }
                    Text(
                        text = buildString {
                            val handle = bookmark.authorUsername?.trim()?.takeIf { it.isNotEmpty() }
                            when {
                                handle != null -> append("@$handle")
                                !bookmark.category.isNullOrBlank() -> append("@${bookmark.category.lowercase().replace(' ', '_')}")
                                else -> append("saved · ${formatEpoch(bookmark.createdAt)}")
                            }
                            readingTime(bookmark.text)?.let { append("  ·  $it") }
                        },
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }

            if (isAnalysisError && !analysisErrorMessage.isNullOrBlank()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .glassSurface(tier = tier, shape = RoundedCornerShape(12.dp), tint = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.25f))
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(Icons.Default.ErrorOutline, contentDescription = null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(16.dp))
                    Text(
                        analysisErrorMessage,
                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.weight(1f)
                    )
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(10.dp))
                            .background(MaterialTheme.colorScheme.error.copy(alpha = 0.12f))
                            .pressBounce { actions.onRunAiAnalysis() }
                            .padding(horizontal = 10.dp, vertical = 6.dp)
                            .testTag("card_retry_curate_${bookmark.id}")
                    ) {
                        Text("Retry", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black), color = MaterialTheme.colorScheme.error)
                    }
                }
            }

            // ── TITLE (short, bold) ──
            if (!bookmark.title.isNullOrBlank()) {
                Text(
                    text = bookmark.title,
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black, lineHeight = 24.sp),
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = if (isExpanded) 6 else 2,
                    overflow = TextOverflow.Ellipsis
                )
            }

            // ── SNIPPET ──
            val snippet = cleanSnippet(bookmark.text)
            if (snippet.isNotBlank()) {
                Text(
                    text = snippet,
                    style = MaterialTheme.typography.bodyMedium.copy(lineHeight = 21.sp),
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.82f),
                    maxLines = if (isExpanded) Int.MAX_VALUE else 3,
                    overflow = TextOverflow.Ellipsis
                )
            }

            // ── MEDIA: real post image · generated art · or an elegant fallback cover ──
            // Every card gets a visual anchor — image-less entries fall back to a bold
            // category-tinted gradient cover so the feed stays consistent and never bare.
            val isImgGenerated = isImagenGenerated
            when {
                !bookmark.imageUrl.isNullOrBlank() -> {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        SubcomposeAsyncImage(
                            model = bookmark.imageUrl,
                            contentDescription = bookmark.imageAltText?.takeIf { it.isNotBlank() } ?: "Post image",
                            contentScale = ContentScale.Crop,
                            modifier = Modifier
                                .fillMaxWidth()
                                .aspectRatio(16f / 9f)
                                .clip(RoundedCornerShape(16.dp))
                                .border(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f), RoundedCornerShape(16.dp))
                                .testTag("post_image_${bookmark.id}"),
                            loading = {
                                val reduceMotion = rememberReduceMotion()
                                if (reduceMotion) {
                                    Box(Modifier.fillMaxSize().background(srcColor.copy(alpha = 0.4f)))
                                } else {
                                    val infinite = rememberInfiniteTransition(label = "shimmer")
                                    val a by infinite.animateFloat(0.25f, 0.6f, infiniteRepeatable(tween(800), RepeatMode.Reverse), label = "shimmerAlpha")
                                    Box(Modifier.fillMaxSize().background(srcColor.copy(alpha = a)))
                                }
                            },
                            error = {
                                CurioFallbackCover(bookmark, srcColor, accent, isExpanded)
                            }
                        )
                        if (isExpanded && !bookmark.imageAltText.isNullOrBlank()) {
                            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                Text("ALT", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black), color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 1.dp))
                                Text(
                                    bookmark.imageAltText,
                                    style = MaterialTheme.typography.labelSmall.copy(fontStyle = androidx.compose.ui.text.font.FontStyle.Italic),
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f),
                                    maxLines = 3,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }
                    }
                }
                isImgGenerated -> {
                    ImagenBookmarkArt(category = bookmark.category, isGenerated = true, onGenerateClick = {}, imageUrl = imagenUrl, modifier = Modifier.height(if (isExpanded) 140.dp else 88.dp))
                }
                bookmark.isAnalyzed && isExpanded -> {
                    ImagenBookmarkArt(category = bookmark.category, isGenerated = false, onGenerateClick = { actions.onGenerateImagen() }, modifier = Modifier.height(130.dp))
                }
                else -> {
                    CurioFallbackCover(bookmark, srcColor, accent, isExpanded)
                }
            }

            // ── TAG ROW (preview) ──
            if (bookmark.isAnalyzed && bookmark.tags.isNotEmpty() && !isExpanded) {
                Row(
                    modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(7.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    bookmark.tags.take(4).forEach { tag -> TagChip(tag) { actions.onSelectTag(tag) } }
                    val overflow = bookmark.tags.size - 4
                    if (overflow > 0) {
                        Box(
                            modifier = Modifier
                                .clip(RoundedCornerShape(50))
                                .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f))
                                .pressBounce { isExpanded = true }
                                .padding(horizontal = 10.dp, vertical = 5.dp)
                        ) {
                            Text("+$overflow", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black), color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                        }
                    }
                }
            }

            // ── FOOTER META: category · source · quick actions ──
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp), modifier = Modifier.weight(1f)) {
                    if (tweetLink != null) {
                        Row(
                            modifier = Modifier
                                .clip(RoundedCornerShape(50))
                                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.14f))
                                .pressBounce { openUrl(context, tweetLink) }
                                .padding(horizontal = 10.dp, vertical = 5.dp)
                                .testTag("view_tweet_button_${bookmark.id}"),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Icon(Icons.Filled.OpenInNew, contentDescription = null, modifier = Modifier.size(13.dp), tint = MaterialTheme.colorScheme.primary)
                            Text("View on X", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, color = MaterialTheme.colorScheme.primary))
                        }
                    }
                    if (currentSpace != null) {
                        val spColor = Color(currentSpace.color)
                        Row(
                            modifier = Modifier
                                .clip(RoundedCornerShape(50))
                                .background(spColor.copy(alpha = 0.16f))
                                .pressBounce { actions.onSelectSpace(currentSpace.id) }
                                .padding(horizontal = 8.dp, vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Icon(spaceIcon(currentSpace.icon), contentDescription = null, modifier = Modifier.size(11.dp), tint = spColor)
                            Text(currentSpace.name, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold, color = spColor), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    } else if (suggestedSpace != null) {
                        // Unfiled, but the embedding auto-organiser thinks it belongs in an existing
                        // Space (medium confidence) → suggest it; tap files via onAssignToSpace.
                        val sugColor = Color(suggestedSpace.color)
                        Row(
                            modifier = Modifier
                                .clip(RoundedCornerShape(50))
                                .border(1.dp, sugColor.copy(alpha = 0.5f), RoundedCornerShape(50))
                                .pressBounce { actions.onAssignToSpace(suggestedSpace.id) }
                                .padding(horizontal = 8.dp, vertical = 4.dp)
                                .testTag("suggest_semantic_${bookmark.id}"),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Icon(Icons.Default.AutoAwesome, contentDescription = null, modifier = Modifier.size(11.dp), tint = sugColor)
                            Text(suggestedSpace.name, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold, color = sugColor), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    } else if (!bookmark.isAnalyzed && !isProcessing) {
                        Row(
                            modifier = Modifier
                                .clip(RoundedCornerShape(50))
                                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.14f))
                                .pressBounce { actions.onRunAiAnalysis() }
                                .padding(horizontal = 8.dp, vertical = 4.dp)
                                .testTag("curate_chip_${bookmark.id}"),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Icon(Icons.Default.AutoAwesome, contentDescription = null, modifier = Modifier.size(11.dp), tint = MaterialTheme.colorScheme.primary)
                            Text("Curate", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, color = MaterialTheme.colorScheme.primary))
                        }
                    } else if (bookmark.isAnalyzed && !bookmark.category.isNullOrBlank()) {
                        // Unfiled but categorised → the AI category *suggests* a Space; tap to file it.
                        val meta = CategorySpaces.forCategory(bookmark.category)
                        val sugColor = Color(meta.color)
                        Row(
                            modifier = Modifier
                                .clip(RoundedCornerShape(50))
                                .border(1.dp, sugColor.copy(alpha = 0.5f), RoundedCornerShape(50))
                                .pressBounce { actions.onAcceptCategory() }
                                .padding(horizontal = 8.dp, vertical = 4.dp)
                                .testTag("suggest_space_${bookmark.id}"),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(11.dp), tint = sugColor)
                            Text(meta.name, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold, color = sugColor), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                    if (bookmark.sourceType != null) {
                        Row(
                            modifier = Modifier.background(srcColor.copy(alpha = 0.14f), RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Text(sourceDisplayName(bookmark), style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold, color = srcColor))
                            if (bookmark.referenceCount > 1) Text("×${bookmark.referenceCount}", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, color = srcColor))
                        }
                    }
                    if (!bookmark.summary.isNullOrBlank()) {
                        Icon(Icons.Default.AutoAwesome, contentDescription = "Has summary", modifier = Modifier.size(13.dp), tint = MaterialTheme.colorScheme.secondary)
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    IconButton(onClick = { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove); actions.onToggleFavorite() }, modifier = Modifier.size(48.dp).testTag("favorite_button_${bookmark.id}")) {
                        Icon(
                            imageVector = if (bookmark.isFavorite) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                            contentDescription = if (bookmark.isFavorite) "Unfavorite" else "Favorite",
                            modifier = Modifier.size(20.dp).bounceScale(bookmark.isFavorite),
                            tint = if (bookmark.isFavorite) CurioColors.Favorite else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f)
                        )
                    }
                    IconButton(onClick = { haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove); actions.onToggleSavedForLater() }, modifier = Modifier.size(48.dp).testTag("readlater_button_${bookmark.id}")) {
                        Icon(
                            imageVector = Icons.Filled.WatchLater,
                            contentDescription = if (bookmark.isSavedForLater) "Remove from read later" else "Save for later",
                            modifier = Modifier.size(20.dp).bounceScale(bookmark.isSavedForLater),
                            tint = if (bookmark.isSavedForLater) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)
                        )
                    }
                    // Hold the card or tap More to open the full action sheet (copy, share, curate, …)
                    IconButton(onClick = { showOptions = true }, modifier = Modifier.testTag("card_more_button_${bookmark.id}")) {
                        Icon(Icons.Default.MoreHoriz, contentDescription = "More options", modifier = Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f))
                    }
                }
            }

            // ── EXPANDED DETAILS ──
            AnimatedVisibility(visible = isExpanded, enter = expandVertically(animationSpec = CurioMotion.liquid()) + fadeIn(), exit = shrinkVertically(animationSpec = CurioMotion.liquid()) + fadeOut()) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(Modifier.fillMaxWidth().height(1.dp).background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)))

                    if (!bookmark.url.isNullOrBlank()) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.08f))
                                .tappable { openUrl(context, bookmark.url) }
                                .padding(horizontal = 10.dp, vertical = 9.dp)
                                .testTag("open_link_row_${bookmark.id}"),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Icon(Icons.Filled.Link, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
                            Text(bookmark.url, style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace, textDecoration = TextDecoration.Underline), color = MaterialTheme.colorScheme.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                            Text("OPEN", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, color = MaterialTheme.colorScheme.primary))
                        }
                    }

                    // OCR status / output
                    if (bookmark.isOcrScheduled) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.primary)
                            Text("EXTRACTING TEXT…", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary))
                        }
                    } else if (!bookmark.ocrText.isNullOrBlank()) {
                        DetailPanel("OCR EXTRACTED", bookmark.ocrText, MaterialTheme.colorScheme.primary)
                    }

                    if (bookmark.isAnalyzed && !bookmark.summary.isNullOrBlank()) {
                        DetailPanel("QUICK SUMMARY", bookmark.summary, MaterialTheme.colorScheme.secondary, bold = true)
                    }
                    if (bookmark.isDeepAnalyzed && !bookmark.deepSummary.isNullOrBlank()) {
                        MarkdownDetailPanel("DEEP ANALYSIS", bookmark.deepSummary, MaterialTheme.colorScheme.tertiary, icon = Icons.Default.AutoAwesome)
                    }
                    if (!bookmark.sourceAbstract.isNullOrBlank()) {
                        DetailPanel("ABSTRACT", bookmark.sourceAbstract, srcColor)
                    }

                    // Personal note: shows the note if present (tap to edit), else a subtle "add note" row.
                    val noteAccent = MaterialTheme.colorScheme.tertiary
                    if (!bookmark.notes.isNullOrBlank()) {
                        Box(modifier = Modifier.clip(RoundedCornerShape(12.dp)).tappable { showNotesEditor = true }.testTag("note_panel_${bookmark.id}")) {
                            DetailPanel("MY NOTE", bookmark.notes, noteAccent)
                        }
                    } else {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(12.dp))
                                .background(noteAccent.copy(alpha = 0.06f))
                                .tappable { showNotesEditor = true }
                                .padding(horizontal = 10.dp, vertical = 9.dp)
                                .testTag("add_note_row_${bookmark.id}"),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Icon(Icons.Filled.Edit, contentDescription = null, tint = noteAccent, modifier = Modifier.size(16.dp))
                            Text("ADD A NOTE", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, color = noteAccent, letterSpacing = 0.6.sp))
                        }
                    }

                    if (bookmark.isAnalyzed && bookmark.tags.isNotEmpty()) {
                        FlowRow(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(7.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                            bookmark.tags.forEach { tag -> TagChip(tag) { actions.onSelectTag(tag) } }
                        }
                    }

                    // Curate / OCR / Deep / Reader and the rest now live in the hold-to-open
                    // action sheet — hold the card or tap ⋯ to reach them.
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.08f))
                            .tappable { showOptions = true }
                            .padding(horizontal = 12.dp, vertical = 9.dp)
                            .testTag("card_actions_row_${bookmark.id}"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(Icons.Default.MoreHoriz, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
                        Text("CURATE, SHARE & MORE", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, color = MaterialTheme.colorScheme.primary, letterSpacing = 0.6.sp))
                        Spacer(Modifier.weight(1f))
                        if (isProcessingThisCard) CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.primary)
                    }
                }
            }
        }
    }

    if (showOptions) {
        CardOptionsSheet(
            bookmark = bookmark,
            actions = actions,
            isProcessing = isProcessingThisCard,
            shareableText = shareableText,
            tweetLink = tweetLink,
            chronosFlowInstalled = chronosFlowInstalled,
            onOcr = { imageLauncher.launch("image/*") },
            onSelect = onToggleSelect,
            onReader = onBookmarkClick,
            onMoveToSpace = { showSpacePicker = true },
            onNotes = { showNotesEditor = true },
            onDismiss = { showOptions = false }
        )
    }

    if (showNotesEditor) {
        NotesEditorDialog(
            existingNote = bookmark.notes,
            tier = tier,
            onDismiss = { showNotesEditor = false },
            onSave = { note ->
                actions.onUpdateNotes(note)
                showNotesEditor = false
            }
        )
    }

    if (showSpacePicker) {
        AssignToSpaceDialog(
            spaces = spaces,
            currentSpaceId = bookmark.spaceId,
            tier = tier,
            onDismiss = { showSpacePicker = false },
            onAssign = { spaceId ->
                actions.onAssignToSpace(spaceId)
                showSpacePicker = false
            },
            onCreateSpace = {
                showSpacePicker = false
                showNewSpaceForCard = true
            }
        )
    }

    if (showNewSpaceForCard) {
        SpaceEditorDialog(
            existing = null,
            tier = tier,
            onDismiss = { showNewSpaceForCard = false },
            onConfirm = { name, color, icon, description, rules, isPinned ->
                actions.onCreateSpaceAndAssign(name, color, icon, description, rules, isPinned)
                showNewSpaceForCard = false
            }
        )
    }
}

/**
 * Per-card action callbacks, bound to the bookmark at the call site. Hoisting these (instead of
 * passing the whole [BookmarkViewModel]) decouples the leaf card from the ViewModel, making it
 * independently previewable/testable and the dependency explicit. The bookmark id/instance is
 * captured by each lambda where the underlying VM call needs it.
 */
@androidx.compose.runtime.Immutable
internal data class CurioCardActions(
    val onProcessOcr: (android.graphics.Bitmap) -> Unit,
    val onGenerateImagen: () -> Unit,
    val onSelectTag: (String) -> Unit,
    val onSelectSpace: (String) -> Unit,
    val onAcceptCategory: () -> Unit,
    val onToggleFavorite: () -> Unit,
    val onToggleSavedForLater: () -> Unit,
    val onUpdateNotes: (String?) -> Unit,
    val onAssignToSpace: (String?) -> Unit,
    val onCreateSpaceAndAssign: (name: String, color: Long, icon: String, description: String, rules: SpaceRules, isPinned: Boolean) -> Unit,
    val onRunAiAnalysis: () -> Unit,
    val onRunDeepAnalysis: () -> Unit,
    val onResolveSource: () -> Unit,
    val exportBibtex: () -> String?,
    val onDelete: () -> Unit,
    // ChronosFlow productivity handoff (only invoked when ChronosFlow is installed).
    val onRemindInChronosFlow: (com.example.interop.ChronosReminderChoice) -> Unit = {},
    val onCaptureToChronosFlow: () -> Unit = {},
    val onCreateChronosFlowTask: () -> Unit = {},
)

/** A single tappable action inside [CardOptionsSheet]. */
private data class CardAction(
    val label: String,
    val icon: ImageVector,
    val tint: Color,
    val onClick: () -> Unit
)

/**
 * Bottom sheet opened by holding a card (or tapping its ⋯ button). Houses every
 * per-card action so the card face itself stays clean. Multi-select is still
 * reachable here via "Select", for the rare times it's wanted.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CardOptionsSheet(
    bookmark: Bookmark,
    actions: CurioCardActions,
    isProcessing: Boolean,
    shareableText: String,
    tweetLink: String?,
    chronosFlowInstalled: Boolean,
    onOcr: () -> Unit,
    onSelect: () -> Unit,
    onReader: () -> Unit,
    onMoveToSpace: () -> Unit,
    onNotes: () -> Unit,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    var confirmingDelete by remember { mutableStateOf(false) }

    // Animate the sheet closed, then run the action (and clear the flag).
    fun act(action: () -> Unit) {
        scope.launch { sheetState.hide() }.invokeOnCompletion {
            onDismiss()
            action()
        }
    }

    val cs = MaterialTheme.colorScheme

    // Cache the BibTeX export so it is not recomputed on every recomposition of the sheet.
    // exportBibtex() may do non-trivial formatting work; memoising it by bookmark identity is safe
    // because the sheet is only shown while the bookmark is unchanged.
    val bibtexText = remember(bookmark.id, bookmark.sourceType) { actions.exportBibtex() }

    // Secondary actions grouped into scannable list sections.
    val curateActions = buildList {
        if (!isProcessing) {
            add(CardAction(if (bookmark.isAnalyzed) "Re-curate" else "AI Curate", if (bookmark.isAnalyzed) Icons.Default.Autorenew else Icons.Default.Psychology, cs.primary) { actions.onRunAiAnalysis() })
        }
        add(CardAction(if (bookmark.isDeepAnalyzed) "Reanalyze+" else "Deep analyze", Icons.Default.AutoAwesome, cs.tertiary) { actions.onRunDeepAnalysis() })
        add(CardAction(if (!bookmark.ocrText.isNullOrBlank()) "Update image text" else "Scan image (OCR)", Icons.Default.Screenshot, cs.secondary, onOcr))
    }
    val moreActions = buildList {
        add(CardAction("Share", Icons.Outlined.Share, cs.onSurface.copy(alpha = 0.7f)) { shareBookmark(context, shareableText) })
        add(CardAction("Reader view", Icons.AutoMirrored.Filled.MenuBook, cs.primary, onReader))
        add(CardAction(if (!bookmark.notes.isNullOrBlank()) "Edit note" else "Add note", Icons.Outlined.Edit, cs.tertiary, onNotes))
        if (bookmark.sourceType == null) {
            add(CardAction("Resolve source", Icons.Outlined.Link, cs.secondary) { actions.onResolveSource() })
        }
        if (bookmark.sourceType == SourceType.ARXIV) {
            bibtexText?.let { bib ->
                add(CardAction("Copy BibTeX", Icons.Outlined.ContentCopy, Color(0xFFE53935)) { copyToClipboard(context, bib, "BibTeX") })
            }
        }
        if (tweetLink != null) {
            add(CardAction("View on X", Icons.Default.OpenInNew, cs.primary) { openUrl(context, tweetLink) })
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = cs.surface,
        dragHandle = { BottomSheetDefaults.DragHandle() }
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            SheetHeader(bookmark)
            SheetDivider(Modifier.padding(vertical = 4.dp))

            SheetQuickIconRow(
                bookmark = bookmark,
                onCopy = { act { copyToClipboard(context, shareableText) } },
                onFavorite = { actions.onToggleFavorite() },
                onReadLater = { actions.onToggleSavedForLater() },
                onChangeSpace = { act(onMoveToSpace) },
                onOpenLink = bookmark.url?.takeIf { it.isNotBlank() }?.let { url -> { act { openUrl(context, url) } } },
            )

            if (curateActions.isNotEmpty()) {
                SheetDivider(Modifier.padding(vertical = 8.dp))
                SheetSectionLabel("CURATE")
                if (isProcessing) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier.padding(start = 4.dp, top = 2.dp, bottom = 2.dp),
                    ) {
                        CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp, color = cs.primary)
                        Text("Curating…", style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold), color = cs.onSurface.copy(alpha = 0.7f))
                    }
                }
                curateActions.forEach { a ->
                    SheetListRow(a) { act(a.onClick) }
                }
            }

            if (moreActions.isNotEmpty()) {
                SheetDivider(Modifier.padding(vertical = 8.dp))
                SheetSectionLabel("MORE")
                moreActions.forEach { a ->
                    SheetListRow(a) { act(a.onClick) }
                }
            }

            if (chronosFlowInstalled) {
                SheetDivider(Modifier.padding(vertical = 8.dp))
                ChronosFlowActions(
                    onRemind = { choice -> act { actions.onRemindInChronosFlow(choice) } },
                    onCapture = { act { actions.onCaptureToChronosFlow() } },
                    onCreateTask = { act { actions.onCreateChronosFlowTask() } },
                )
            }

            SheetDivider(Modifier.padding(vertical = 8.dp))
            // Delete is two-step: the first tap arms an inline confirm so a stray
            // tap in the menu can't quietly drop a card.
            if (confirmingDelete) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(cs.error.copy(alpha = 0.10f))
                        .border(1.dp, cs.error.copy(alpha = 0.25f), RoundedCornerShape(14.dp))
                        .padding(start = 14.dp, top = 8.dp, bottom = 8.dp, end = 8.dp)
                        .testTag("sheet_delete_confirm_${bookmark.id}"),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Icon(Icons.Default.Delete, contentDescription = null, tint = cs.error, modifier = Modifier.size(18.dp))
                    Text("Delete this card?", style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold), color = cs.onSurface, modifier = Modifier.weight(1f))
                    Text(
                        "CANCEL",
                        style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black),
                        color = cs.onSurface.copy(alpha = 0.7f),
                        modifier = Modifier.clip(RoundedCornerShape(10.dp)).tappable { confirmingDelete = false }.padding(horizontal = 12.dp, vertical = 8.dp)
                    )
                    Text(
                        "DELETE",
                        style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black),
                        color = cs.error,
                        modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(cs.error.copy(alpha = 0.16f)).tappable { act { actions.onDelete() } }.padding(horizontal = 14.dp, vertical = 8.dp).testTag("sheet_delete_confirm_button_${bookmark.id}")
                    )
                }
            } else {
                SheetFooterRow(
                    onSelect = { act(onSelect) },
                    onDelete = { confirmingDelete = true },
                )
            }
        }
    }
}

/**
 * ChronosFlow productivity actions inside the options sheet: save the bookmark to ChronosFlow's
 * reading list with an optional "remind me to read later" time, drop it into the inbox, or turn it
 * into a follow-up task. The reminder row expands to a small set of preset times (the app has no
 * time picker). Shown only when ChronosFlow is installed.
 */
@Composable
private fun ChronosFlowActions(
    onRemind: (ChronosReminderChoice) -> Unit,
    onCapture: () -> Unit,
    onCreateTask: () -> Unit,
) {
    val cs = MaterialTheme.colorScheme
    var remindExpanded by remember { mutableStateOf(false) }

    Text(
        "CHRONOSFLOW",
        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, letterSpacing = 0.6.sp),
        color = cs.primary
    )
    ChronosRow(Icons.Filled.Schedule, "Remind me to read later", cs.secondary) { remindExpanded = !remindExpanded }
    if (remindExpanded) {
        ChronosReminderChoice.entries.forEach { choice ->
            Text(
                text = choice.label,
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                color = cs.onSurface,
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .tappable { onRemind(choice) }
                    .padding(start = 38.dp, top = 10.dp, bottom = 10.dp, end = 12.dp)
            )
        }
    }
    ChronosRow(Icons.Filled.Inbox, "Capture to ChronosFlow inbox", cs.tertiary, onCapture)
    ChronosRow(Icons.Filled.AddTask, "Create ChronosFlow task", cs.primary, onCreateTask)
}

@Composable
private fun ChronosRow(icon: ImageVector, label: String, tint: Color, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .tappable(onClick = onClick)
            .padding(vertical = 10.dp, horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
            color = MaterialTheme.colorScheme.onSurface
        )
    }
}

private val sheetDividerAlpha = 0.08f

@Composable
private fun SheetHeader(bookmark: Bookmark) {
    val cs = MaterialTheme.colorScheme
    val accent = CurioColors.sourceAccent(bookmark.sourceType)
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(
            modifier = Modifier
                .padding(top = 4.dp)
                .size(10.dp)
                .clip(CircleShape)
                .background(accent),
        )
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                text = "${sourceDisplayName(bookmark)} · ${relativeTime(bookmark.createdAt)}",
                style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp),
                color = cs.primary,
            )
            Text(
                text = bookmark.title?.takeIf { it.isNotBlank() } ?: cleanSnippet(bookmark.text),
                style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black, lineHeight = 22.sp),
                color = cs.onSurface,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun SheetSectionLabel(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, letterSpacing = 0.8.sp),
        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.45f),
        modifier = Modifier.padding(start = 4.dp, bottom = 2.dp),
    )
}

@Composable
private fun SheetDivider(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().height(1.dp).background(MaterialTheme.colorScheme.onSurface.copy(alpha = sheetDividerAlpha)))
}

/** Icon-only quick actions row using outlined icons. Toggles stay in-sheet; navigational actions dismiss. */
@Composable
private fun SheetQuickIconRow(
    bookmark: Bookmark,
    onCopy: () -> Unit,
    onFavorite: () -> Unit,
    onReadLater: () -> Unit,
    onChangeSpace: () -> Unit,
    onOpenLink: (() -> Unit)?,
) {
    val cs = MaterialTheme.colorScheme
    val favoriteTint = if (bookmark.isFavorite) CurioColors.Favorite else cs.onSurface.copy(alpha = 0.7f)
    val favoriteIcon = if (bookmark.isFavorite) Icons.Outlined.Favorite else Icons.Outlined.FavoriteBorder
    val readLaterTint = if (bookmark.isSavedForLater) cs.secondary else cs.onSurface.copy(alpha = 0.7f)
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SheetIconButton(Icons.Outlined.ContentCopy, "Copy", cs.onSurface.copy(alpha = 0.7f), onCopy, Modifier.weight(1f))
        SheetIconButton(favoriteIcon, if (bookmark.isFavorite) "Unfavorite" else "Favorite", favoriteTint, onFavorite, Modifier.weight(1f), bookmark.isFavorite)
        SheetIconButton(Icons.Outlined.WatchLater, if (bookmark.isSavedForLater) "Remove from read later" else "Save for later", readLaterTint, onReadLater, Modifier.weight(1f), bookmark.isSavedForLater)
        SheetIconButton(
            Icons.Outlined.Workspaces,
            if (!bookmark.spaceId.isNullOrBlank()) "Change space" else "Add to space",
            cs.tertiary,
            onChangeSpace,
            Modifier.weight(1f),
        )
        if (onOpenLink != null) {
            SheetIconButton(Icons.Outlined.Link, "Open link", cs.secondary, onOpenLink, Modifier.weight(1f))
        }
    }
}

/** A single icon-only button in [SheetQuickIconRow]. */
@Composable
private fun SheetIconButton(
    icon: ImageVector,
    contentDescription: String,
    tint: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    active: Boolean = false,
) {
    Box(
        modifier = modifier
            .height(52.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(tint.copy(alpha = if (active) 0.18f else 0.10f))
            .then(
                if (active) Modifier.border(1.dp, tint.copy(alpha = 0.45f), RoundedCornerShape(14.dp))
                else Modifier
            )
            .tappable(onClick = onClick)
            .testTag("sheet_icon_$contentDescription"),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            icon,
            contentDescription = contentDescription,
            tint = tint,
            modifier = Modifier.size(22.dp).bounceScale(active),
        )
    }
}

/** Full-width list row for secondary sheet actions. */
@Composable
private fun SheetListRow(action: CardAction, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .tappable(onClick = onClick)
            .padding(vertical = 11.dp, horizontal = 4.dp)
            .testTag("sheet_row_${action.label}"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Icon(action.icon, contentDescription = null, tint = action.tint, modifier = Modifier.size(20.dp))
        Text(
            text = action.label,
            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
            color = cs.onSurface,
            modifier = Modifier.weight(1f),
        )
        Icon(
            Icons.Filled.KeyboardArrowDown,
            contentDescription = null,
            tint = cs.onSurface.copy(alpha = 0.25f),
            modifier = Modifier.size(18.dp).rotate(-90f),
        )
    }
}

/** Compact footer for multi-select entry and destructive delete. */
@Composable
private fun SheetFooterRow(onSelect: () -> Unit, onDelete: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier
                .weight(1f)
                .clip(RoundedCornerShape(14.dp))
                .background(cs.onSurface.copy(alpha = 0.06f))
                .tappable(onClick = onSelect)
                .padding(vertical = 13.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Outlined.Check, contentDescription = null, tint = cs.onSurface.copy(alpha = 0.7f), modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("Select", style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold), color = cs.onSurface.copy(alpha = 0.7f))
        }
        Row(
            modifier = Modifier
                .weight(1f)
                .clip(RoundedCornerShape(14.dp))
                .background(cs.error.copy(alpha = 0.08f))
                .tappable(onClick = onDelete)
                .padding(vertical = 13.dp)
                .testTag("sheet_delete_button"),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Outlined.Delete, contentDescription = null, tint = cs.error, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("Delete", style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold), color = cs.error)
        }
    }
}
