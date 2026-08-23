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
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.SnackbarDuration
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
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
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.WatchLater
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Workspaces
import android.content.Intent
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.example.MainActivity
import com.example.data.embedding.EmbeddingModelManager
import com.example.domain.model.AuthState
import com.example.domain.model.Bookmark
import com.example.domain.model.SourceType
import com.example.ui.components.GlassBottomBar
import com.example.ui.components.GlassNavigationItem
import com.example.ui.components.GlassScaffold
import com.example.ui.components.GlassTopBar
import com.example.ui.components.LiquidGlassFab
import com.example.ui.components.CurioSkeletonList
import com.example.ui.components.SwipeRevealActions
import com.example.ui.screens.auth.AuthViewModel
import com.example.ui.screens.auth.LoginScreen
import com.example.ui.theme.BookmarkTheme
import androidx.compose.foundation.text.ClickableText
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import com.example.ui.theme.GlassTier
import com.example.ui.theme.glassSurface
import com.example.ui.theme.rememberGlassTier
import com.example.ui.theme.CurioMotion
import com.example.ui.theme.pressBounce
import com.example.ui.theme.bounceScale
import com.example.ui.theme.curioAccentBrush
import com.example.ui.theme.tappable
import com.example.ui.theme.minTouchTarget
import com.example.ui.theme.CurioColors
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
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

@OptIn(ExperimentalLayoutApi::class, androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
internal fun BookmarkFeedScreen(
    viewModel: BookmarkViewModel,
    tier: GlassTier,
    onBookmarkClick: (Bookmark) -> Unit,
    onOpenMenu: () -> Unit = {},
    onNavigateToSettings: () -> Unit = {},
    loginSuccessMessage: String? = null,
    onDismissLoginSuccess: () -> Unit = {}
) {
    val context = LocalContext.current
    val bookmarks by viewModel.bookmarks.collectAsStateWithLifecycle()
    val syncState by viewModel.syncState.collectAsStateWithLifecycle()
    val xaiKeyConfigured by viewModel.xaiKeyConfigured.collectAsStateWithLifecycle()
    val forceLocalNano by viewModel.forceLocalNano.collectAsStateWithLifecycle()
    val stats by viewModel.stats.collectAsStateWithLifecycle()
    // Collected ONCE here (not per card) so a single card's processing/imagen change no longer
    // forces every CurioPostCard to recompose; per-card values are derived in the items loop.
    val analysisState by viewModel.analysisState.collectAsStateWithLifecycle()
    val imagenGeneratedIds by viewModel.imagenGeneratedIds.collectAsStateWithLifecycle()
    val imagenUrls by viewModel.imagenUrls.collectAsStateWithLifecycle()

    val searchQuery by viewModel.searchQuery.collectAsStateWithLifecycle()
    val selectedTag by viewModel.selectedTag.collectAsStateWithLifecycle()
    val searchMode by viewModel.searchMode.collectAsStateWithLifecycle()
    val isSemanticLoading by viewModel.isSemanticLoading.collectAsStateWithLifecycle()
    val embeddingModelState by viewModel.embeddingModelState.collectAsStateWithLifecycle()
    val quickFilter by viewModel.quickFilter.collectAsStateWithLifecycle()
    val spaces by viewModel.spaces.collectAsStateWithLifecycle()
    val spaceSuggestions by viewModel.spaceSuggestions.collectAsStateWithLifecycle()
    val selectedSpaceId by viewModel.selectedSpaceId.collectAsStateWithLifecycle()
    val activeSpace = remember(spaces, selectedSpaceId) { spaces.firstOrNull { it.id == selectedSpaceId } }

    var selectedIds by remember { mutableStateOf(emptySet<String>()) }
    var showBulkSpaceDialog by remember { mutableStateOf(false) }
    var showBulkNewSpace by remember { mutableStateOf(false) }
    var isReorderMode by remember { mutableStateOf(false) }
    var showActionsMenu by remember { mutableStateOf(false) }
    var showExportDialog by remember { mutableStateOf(false) }
    var showModelDialog by remember { mutableStateOf(false) }
    // Id of the card whose swipe Delete dock is currently open. Hoisted so only one card can
    // be revealed at a time, and so scrolling / mode changes can close it.
    var revealedCardId by remember { mutableStateOf<String?>(null) }
    val isSyncing = syncState is SyncUiState.Loading

    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    // Delete now, offer Undo. The bookmarks flow is Room-backed, so both the delete and the
    // restore re-emit — the card animates out and (on Undo) back in. We keep the captured
    // Bookmark objects so the restore is verbatim (analysis, tags, Space, favorite all preserved).
    val deleteWithUndo: (List<Bookmark>) -> Unit = { toDelete ->
        if (toDelete.isNotEmpty()) {
            viewModel.deleteBookmarks(toDelete.map { it.id })
            scope.launch {
                val result = snackbarHostState.showSnackbar(
                    message = if (toDelete.size == 1) "Bookmark deleted" else "${toDelete.size} bookmarks deleted",
                    actionLabel = "Undo",
                    withDismissAction = true,
                    duration = SnackbarDuration.Long
                )
                if (result == SnackbarResult.ActionPerformed) viewModel.restoreBookmarks(toDelete)
            }
        }
    }

    LaunchedEffect(Unit) {
        viewModel.curationError.collect { message ->
            CurioNotifier.notify(context, message)
        }
    }

    LaunchedEffect(loginSuccessMessage) {
        val msg = loginSuccessMessage ?: return@LaunchedEffect
        delay(5_000)
        if (loginSuccessMessage == msg) onDismissLoginSuccess()
    }

    LaunchedEffect(syncState) {
        val state = syncState
        if (state is SyncUiState.Success) {
            delay(5_000)
            if (viewModel.syncState.value is SyncUiState.Success) {
                viewModel.dismissSyncBanner()
            }
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
    androidx.compose.material3.pulltorefresh.PullToRefreshBox(
        isRefreshing = isSyncing,
        onRefresh = { viewModel.syncBookmarks(fetchNextPage = false) },
        modifier = Modifier.fillMaxSize()
    ) {
        val listState = rememberLazyListState()
        // Scrolling closes any revealed Delete dock — a destructive action should never
        // ride off-screen attached to a card the user is no longer looking at.
        LaunchedEffect(listState.isScrollInProgress) {
            if (listState.isScrollInProgress) revealedCardId = null
        }
        LazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
        // 0. MERGED HEADER — brand · search · controls · filters (space-efficient)
        item {
            Column(
                verticalArrangement = Arrangement.spacedBy(11.dp),
                modifier = Modifier.statusBarsPadding().padding(top = 6.dp)
            ) {
                // ── Row 1: hamburger · merged search pill (with AI toggle) · live count ──
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(44.dp)
                            .clip(CircleShape)
                            .glassSurface(tier = tier, shape = CircleShape)
                            .pressBounce(pressedScale = 0.9f) { onOpenMenu() },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Default.Menu, contentDescription = "Open menu", tint = MaterialTheme.colorScheme.onSurface, modifier = Modifier.size(20.dp))
                    }

                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .glassSurface(tier = tier, shape = RoundedCornerShape(26.dp))
                            .padding(start = 14.dp, end = 6.dp)
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Filled.Search,
                                contentDescription = "Search Bookmarks",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(18.dp)
                            )
                            androidx.compose.material3.TextField(
                                value = searchQuery,
                                onValueChange = { viewModel.updateSearchQuery(it) },
                                placeholder = { Text("Search your index…", style = MaterialTheme.typography.bodyMedium.copy(color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))) },
                                textStyle = MaterialTheme.typography.bodyMedium.copy(color = MaterialTheme.colorScheme.onSurface),
                                singleLine = true,
                                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                                    imeAction = androidx.compose.ui.text.input.ImeAction.Search
                                ),
                                colors = androidx.compose.material3.TextFieldDefaults.colors(
                                    focusedContainerColor = Color.Transparent,
                                    unfocusedContainerColor = Color.Transparent,
                                    disabledContainerColor = Color.Transparent,
                                    focusedIndicatorColor = Color.Transparent,
                                    unfocusedIndicatorColor = Color.Transparent
                                ),
                                modifier = Modifier.weight(1f).testTag("search_field_input")
                            )
                            if (searchQuery.isNotEmpty()) {
                                Box(
                                    modifier = Modifier
                                        .minTouchTarget(40.dp)
                                        .clip(CircleShape)
                                        .pressBounce(pressedScale = 0.85f) { viewModel.updateSearchQuery("") },
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        imageVector = Icons.Filled.Close,
                                        contentDescription = "Clear search",
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.size(18.dp)
                                    )
                                }
                            }
                            Box(
                                modifier = Modifier
                                    .bounceScale(searchMode == SearchMode.SEMANTIC)
                                    // Announce the toggle's on/off state to TalkBack.
                                    .semantics { stateDescription = if (searchMode == SearchMode.SEMANTIC) "AI search on" else "AI search off" }
                                    .background(
                                        brush = if (searchMode == SearchMode.SEMANTIC) curioAccentBrush(MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.tertiary) else Brush.linearGradient(listOf(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f), MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f))),
                                        shape = RoundedCornerShape(20.dp)
                                    )
                                    .pressBounce(pressedScale = 0.9f) {
                                        when {
                                            // Turning AI off is always allowed.
                                            searchMode == SearchMode.SEMANTIC ->
                                                viewModel.setSearchMode(SearchMode.KEYWORD)
                                            // Semantic search needs the on-device model; prompt to get it.
                                            embeddingModelState is EmbeddingModelManager.State.Ready ->
                                                viewModel.setSearchMode(SearchMode.SEMANTIC)
                                            else -> showModelDialog = true
                                        }
                                    }
                                    .padding(horizontal = 10.dp, vertical = 8.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                if (isSemanticLoading) {
                                    CircularProgressIndicator(
                                        modifier = Modifier.size(13.dp),
                                        strokeWidth = 2.dp,
                                        color = if (searchMode == SearchMode.SEMANTIC) Color.White else MaterialTheme.colorScheme.primary
                                    )
                                } else {
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                                        Icon(Icons.Default.AutoAwesome, contentDescription = null, modifier = Modifier.size(12.dp), tint = if (searchMode == SearchMode.SEMANTIC) Color.White else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                                        Text(
                                            text = "AI",
                                            style = MaterialTheme.typography.labelSmall.copy(
                                                fontWeight = FontWeight.Black,
                                                color = if (searchMode == SearchMode.SEMANTIC) Color.White else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                                            )
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Row 2: compact stat + control strip (replaces the giant hero card) ──
                Box(modifier = Modifier.fillMaxWidth().glassSurface(tier = tier, shape = RoundedCornerShape(20.dp)).padding(horizontal = 14.dp, vertical = 10.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(
                                    text = "${bookmarks.size}",
                                    style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Black, letterSpacing = (-1).sp),
                                    color = MaterialTheme.colorScheme.onSurface
                                )
                                Text(
                                    text = "bookmarks",
                                    style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold),
                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f),
                                    modifier = Modifier.padding(bottom = 3.dp)
                                )
                            }
                            Text(
                                text = "${stats.curatedCount} curated · ${stats.sourceCount} sources",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                            )
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            // Primary action — a labeled pill so its meaning is unambiguous.
                            Row(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(50))
                                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.14f))
                                    .pressBounce(onClick = { if (!isSyncing) viewModel.syncBookmarks(fetchNextPage = false) })
                                    .padding(horizontal = 12.dp, vertical = 7.dp)
                                    .testTag("sync_button"),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                if (isSyncing) {
                                    CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.primary)
                                } else {
                                    Icon(Icons.Default.Refresh, contentDescription = null, modifier = Modifier.size(15.dp), tint = MaterialTheme.colorScheme.primary)
                                }
                                Text(
                                    text = if (isSyncing) "Syncing…" else "Sync",
                                    style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black),
                                    color = MaterialTheme.colorScheme.primary
                                )
                            }

                            // Everything else lives behind a labeled overflow menu — no more guessing what an icon does.
                            Box {
                                FeedIconAction(
                                    icon = Icons.Default.MoreVert,
                                    contentDescription = "More actions",
                                    onClick = { showActionsMenu = true }
                                )
                                DropdownMenu(
                                    expanded = showActionsMenu,
                                    onDismissRequest = { showActionsMenu = false }
                                ) {
                                    DropdownMenuItem(
                                        text = { Text("Load older bookmarks") },
                                        leadingIcon = { Icon(Icons.Default.CloudSync, contentDescription = null) },
                                        onClick = {
                                            showActionsMenu = false
                                            viewModel.syncBookmarks(fetchNextPage = true)
                                        }
                                    )
                                    if (xaiKeyConfigured) {
                                        DropdownMenuItem(
                                            text = { Text(if (forceLocalNano) "AI engine: On-device" else "AI engine: Cloud") },
                                            leadingIcon = { Icon(if (forceLocalNano) Icons.Default.Psychology else Icons.Default.AutoAwesome, contentDescription = null) },
                                            trailingIcon = {
                                                Text(
                                                    text = "Tap to switch",
                                                    style = MaterialTheme.typography.labelSmall,
                                                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                                                )
                                            },
                                            onClick = {
                                                showActionsMenu = false
                                                viewModel.setForceLocalNano(!forceLocalNano)
                                            }
                                        )
                                    }
                                    DropdownMenuItem(
                                        text = { Text(if (isReorderMode) "Done reordering" else "Reorder bookmarks") },
                                        leadingIcon = { Icon(if (isReorderMode) Icons.Default.Check else Icons.Default.Autorenew, contentDescription = null) },
                                        onClick = {
                                            showActionsMenu = false
                                            isReorderMode = !isReorderMode
                                        }
                                    )
                                }
                            }
                        }
                    }
                }

                // ── Row 3: quick filters (All · Favorites · Read later) ──
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    QuickFilterPill("All", Icons.Default.Bookmarks, bookmarks.size.takeIf { quickFilter == QuickFilter.ALL }, quickFilter == QuickFilter.ALL, MaterialTheme.colorScheme.primary) { viewModel.setQuickFilter(QuickFilter.ALL) }
                    QuickFilterPill("Favorites", Icons.Default.Favorite, stats.favoriteCount, quickFilter == QuickFilter.FAVORITES, CurioColors.Favorite) { viewModel.setQuickFilter(QuickFilter.FAVORITES) }
                    QuickFilterPill("Read later", Icons.Default.WatchLater, stats.readLaterCount, quickFilter == QuickFilter.READ_LATER, MaterialTheme.colorScheme.secondary) { viewModel.setQuickFilter(QuickFilter.READ_LATER) }
                }

                // ── Row 4: Space chips — quick-switch the feed between collections ──
                // Spaces have replaced the old "category" chips; AI categories now seed Spaces, so
                // this single row is the unified way to scope the feed.
                // rememberScrollState() is unconditional — calling it inside an if block would
                // violate Compose's rules of hooks and crash when spaces transitions empty↔non-empty.
                val spaceChipsScrollState = rememberScrollState()
                if (spaces.isNotEmpty()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .horizontalScroll(spaceChipsScrollState),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        // "All" — clears the Space scope.
                        val allActive = selectedSpaceId == null
                        Box(
                            modifier = Modifier
                                .bounceScale(allActive)
                                .background(
                                    color = if (allActive) MaterialTheme.colorScheme.primary.copy(alpha = 0.2f) else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f),
                                    shape = RoundedCornerShape(12.dp)
                                )
                                .border(width = 1.dp, color = if (allActive) MaterialTheme.colorScheme.primary else Color.Transparent, shape = RoundedCornerShape(12.dp))
                                .pressBounce(pressedScale = 0.93f) { viewModel.selectSpace(null) }
                                .padding(horizontal = 14.dp, vertical = 8.dp)
                        ) {
                            Text(
                                text = "ALL",
                                style = MaterialTheme.typography.labelSmall.copy(
                                    fontWeight = FontWeight.Bold,
                                    color = if (allActive) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                                )
                            )
                        }

                        spaces.forEach { space ->
                            val active = selectedSpaceId == space.id
                            val chipColor = Color(space.color)
                            Row(
                                modifier = Modifier
                                    .bounceScale(active)
                                    .background(
                                        color = if (active) chipColor.copy(alpha = 0.2f) else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f),
                                        shape = RoundedCornerShape(12.dp)
                                    )
                                    .border(width = 1.dp, color = if (active) chipColor else Color.Transparent, shape = RoundedCornerShape(12.dp))
                                    .pressBounce(pressedScale = 0.93f) { viewModel.selectSpace(if (active) null else space.id) }
                                    .padding(horizontal = 12.dp, vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                Icon(
                                    spaceIcon(space.icon),
                                    contentDescription = null,
                                    tint = chipColor,
                                    modifier = Modifier.size(13.dp)
                                )
                                Text(
                                    text = space.name.uppercase(),
                                    style = MaterialTheme.typography.labelSmall.copy(
                                        fontWeight = FontWeight.Bold,
                                        color = if (active) chipColor else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                                    )
                                )
                                if (space.count > 0) {
                                    Text(
                                        text = "${space.count}",
                                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, fontSize = 9.sp),
                                        color = (if (active) chipColor else MaterialTheme.colorScheme.onSurface).copy(alpha = 0.45f)
                                    )
                                }
                            }
                        }
                    }
                }

                // ── Active Space banner — shown when the feed is scoped to a Space ──
                activeSpace?.let { space ->
                    val spaceColor = Color(space.color)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(14.dp))
                            .background(spaceColor.copy(alpha = 0.14f))
                            .border(1.dp, spaceColor.copy(alpha = 0.4f), RoundedCornerShape(14.dp))
                            .padding(horizontal = 12.dp, vertical = 8.dp)
                            .testTag("active_space_banner"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Box(
                            modifier = Modifier.size(28.dp).background(spaceColor.copy(alpha = 0.9f), CircleShape),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(spaceIcon(space.icon), contentDescription = null, tint = Color.White, modifier = Modifier.size(15.dp))
                        }
                        Column(modifier = Modifier.weight(1f)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text("SPACE", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, letterSpacing = 1.sp), color = spaceColor)
                                if (space.isSmart) {
                                    Text(
                                        "· SMART",
                                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, letterSpacing = 0.5.sp),
                                        color = spaceColor.copy(alpha = 0.8f)
                                    )
                                }
                            }
                            Text(space.name, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold), color = MaterialTheme.colorScheme.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (space.description.isNotBlank()) {
                                Text(space.description, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                        Box(
                            modifier = Modifier
                                .minTouchTarget(40.dp)
                                .clip(CircleShape)
                                .pressBounce(pressedScale = 0.85f) { viewModel.selectSpace(null) },
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                Icons.Filled.Close,
                                contentDescription = "Exit space",
                                tint = spaceColor,
                                modifier = Modifier.size(20.dp)
                            )
                        }
                    }
                }

                // Active query / tag filter banner (Spaces have their own chip + banner above)
                if (selectedTag != null || searchQuery.isNotBlank()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.08f))
                            .padding(start = 12.dp, end = 6.dp, top = 6.dp, bottom = 6.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = buildString {
                                append("Filtering: ")
                                if (searchQuery.isNotBlank()) append("Query '$searchQuery' • ")
                                if (selectedTag != null) append("Tag '#${selectedTag}' ")
                            }.trimEnd(' ', '•'),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.primary,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f)
                        )
                        Text(
                            text = "CLEAR ALL",
                            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, color = MaterialTheme.colorScheme.error),
                            modifier = Modifier
                                .clip(RoundedCornerShape(50))
                                .pressBounce(pressedScale = 0.9f) { viewModel.clearAllFilters() }
                                .padding(horizontal = 12.dp, vertical = 8.dp)
                        )
                    }
                }
            }
        }
        // 0b. BYOK SETUP BANNER — shown until the user saves an xAI key in Settings
        if (!xaiKeyConfigured) {
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .glassSurface(
                            tier = tier,
                            tint = MaterialTheme.colorScheme.tertiaryContainer.copy(alpha = 0.35f)
                        )
                        .pressBounce(pressedScale = 0.98f) { onNavigateToSettings() }
                        .padding(14.dp)
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Icon(
                            Icons.Default.Settings,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.tertiary,
                            modifier = Modifier.size(22.dp)
                        )
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                "Add your xAI API key to enable AI features",
                                style = MaterialTheme.typography.bodyMedium.copy(
                                    fontWeight = FontWeight.Bold
                                )
                            )
                            val uriHandler = LocalUriHandler.current
                            val bannerStyle = MaterialTheme.typography.labelSmall
                            val baseColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f)
                            val linkColor = MaterialTheme.colorScheme.primary
                            val bannerText = buildAnnotatedString {
                                withStyle(SpanStyle(color = baseColor)) {
                                    append("Auto-tagging, chat, and weekly digests need a key from ")
                                }
                                pushStringAnnotation("URL", "https://console.x.ai")
                                withStyle(SpanStyle(color = linkColor, textDecoration = TextDecoration.Underline)) {
                                    append("console.x.ai")
                                }
                                pop()
                                withStyle(SpanStyle(color = baseColor)) { append(". Tap to set up in Settings.") }
                            }
                            ClickableText(
                                text = bannerText,
                                style = bannerStyle,
                                onClick = { offset ->
                                    val hit = bannerText.getStringAnnotations("URL", offset, offset).firstOrNull()
                                    if (hit != null) uriHandler.openUri(hit.item)
                                    else onNavigateToSettings()
                                }
                            )
                        }
                    }
                }
            }
        }

        // ── CONSOLIDATED STATUS SLOT ──
        // The transient banners below (login / sync / AI error) used to be independent items
        // that could stack three-deep between the header and the first card. A single priority
        // now picks at most one: hard failures first, then progress, then confirmations.
        // (BYOK setup, active Space and active filters are persistent/contextual, not
        // transient status, so they keep their own slots.)
        val globalAnalysisError = (analysisState as? AnalysisUiState.Error)?.takeIf {
            it.bookmarkId == null || bookmarks.none { b -> b.id == it.bookmarkId }
        }
        val statusSlot: Int = when {
            syncState is SyncUiState.Error -> 0
            globalAnalysisError != null -> 1
            syncState is SyncUiState.RateLimited -> 2
            syncState is SyncUiState.Loading -> 3
            syncState is SyncUiState.Success -> 4
            !loginSuccessMessage.isNullOrBlank() -> 5
            else -> -1
        }

        // 0.5 LOGIN SUCCESS BANNER (lowest priority — suppressed while any sync/AI status is live)
        if (statusSlot == 5) {
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .glassSurface(tier = tier, tint = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.25f))
                        .padding(12.dp)
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(Icons.Default.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
                        Text(
                            text = loginSuccessMessage ?: "",
                            style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold),
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.weight(1f)
                        )
                        IconButton(onClick = onDismissLoginSuccess, modifier = Modifier.size(32.dp)) {
                            Icon(Icons.Default.Close, contentDescription = "Dismiss", tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), modifier = Modifier.size(18.dp))
                        }
                    }
                }
            }
        }

        // 1. SYNC STATUS BANNER (one of the mutually-exclusive status-slot variants)
        if (statusSlot in 0..4) {
            item {
            when (val state = syncState) {
                is SyncUiState.Loading -> {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .glassSurface(tier = tier, tint = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.2f))
                            .padding(12.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                            Text(
                                state.message ?: "Synchronizing bookmarks feed from X.com...",
                                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold)
                            )
                        }
                    }
                }
                is SyncUiState.Success -> {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .glassSurface(tier = tier, tint = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.2f))
                            .padding(12.dp)
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Icon(Icons.Default.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
                            Text(
                                state.message,
                                style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold),
                                color = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.weight(1f)
                            )
                            IconButton(onClick = { viewModel.dismissSyncBanner() }, modifier = Modifier.size(32.dp)) {
                                Icon(Icons.Default.Close, contentDescription = "Dismiss", tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), modifier = Modifier.size(18.dp))
                            }
                        }
                    }
                }
                is SyncUiState.RateLimited -> {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .glassSurface(tier = tier, tint = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.25f))
                            .padding(12.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Icon(Icons.Default.Timer, contentDescription = "Rate limited lockout", tint = MaterialTheme.colorScheme.error)
                            Text(
                                "X Rate Limited. Resume syncing in ${state.secondsLeft}s",
                                style = MaterialTheme.typography.bodyMedium.copy(
                                    fontWeight = FontWeight.Black,
                                    color = MaterialTheme.colorScheme.error
                                )
                            )
                        }
                    }
                }
                is SyncUiState.Error -> {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .glassSurface(tier = tier, tint = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.15f))
                            .padding(12.dp)
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Icon(
                                Icons.Default.ErrorOutline,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.error,
                                modifier = Modifier.size(18.dp)
                            )
                            Text(
                                text = state.error,
                                style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold),
                                color = MaterialTheme.colorScheme.error,
                                modifier = Modifier.weight(1f)
                            )
                            IconButton(
                                onClick = { viewModel.syncBookmarks(fetchNextPage = false) },
                                modifier = Modifier.size(32.dp)
                            ) {
                                Icon(
                                    Icons.Default.Refresh,
                                    contentDescription = "Retry sync",
                                    tint = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.size(18.dp)
                                )
                            }
                            IconButton(
                                onClick = { viewModel.dismissSyncBanner() },
                                modifier = Modifier.size(32.dp)
                            ) {
                                Icon(
                                    Icons.Default.Close,
                                    contentDescription = "Dismiss",
                                    tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                                    modifier = Modifier.size(18.dp)
                                )
                            }
                        }
                    }
                }
                else -> {}
            }
            }
        }

        // 2. AI ANALYSIS ERROR BANNER (only when the failed card isn't visible in the list;
        // gated by the status slot so it can never stack with a sync banner)
        if (statusSlot == 1) {
            // Non-null here: statusSlot == 1 requires globalAnalysisError != null.
            val errorMsg = globalAnalysisError!!.error
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .glassSurface(tier = tier, tint = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.15f))
                        .padding(12.dp)
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(
                            Icons.Default.ErrorOutline,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.error,
                            modifier = Modifier.size(18.dp)
                        )
                        Text(
                            text = "AI analysis failed: $errorMsg",
                            style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold),
                            color = MaterialTheme.colorScheme.error,
                            modifier = Modifier.weight(1f)
                        )
                        IconButton(
                            onClick = { viewModel.clearAnalysisError() },
                            modifier = Modifier.size(32.dp)
                        ) {
                            Icon(
                                Icons.Default.Close,
                                contentDescription = "Dismiss",
                                tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    }
                }
            }
        }

        // 4. BOOKMARK ENTRY ROW LIST
        if (bookmarks.isEmpty()) {
            item {
                val isFiltering = searchQuery.isNotBlank() || selectedTag != null ||
                    quickFilter != QuickFilter.ALL || selectedSpaceId != null
                if (isFiltering && stats.totalCount > 0) {
                    // Distinct state for "your filter/search matched nothing" vs "you have no
                    // bookmarks yet" — the latter's sync CTA would be the wrong action here.
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 24.dp, vertical = 48.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Icon(
                            Icons.Default.Search,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                            modifier = Modifier.size(40.dp)
                        )
                        Text(
                            "No matches",
                            style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
                            color = MaterialTheme.colorScheme.onSurface
                        )
                        Text(
                            "Nothing in your index matches the current search and filters.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f),
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center
                        )
                        Box(
                            modifier = Modifier
                                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f), RoundedCornerShape(12.dp))
                                .pressBounce { viewModel.clearAllFilters() }
                                .padding(horizontal = 20.dp, vertical = 10.dp)
                        ) {
                            Text("Clear filters", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                        }
                    }
                } else if (isSyncing) {
                    // First sync into an empty cache — show shimmering skeleton cards rather than
                    // the "your archive is empty" CTA, which would be the wrong action mid-load.
                    CurioSkeletonList(tier = tier)
                } else {
                    CurioEmptyState(
                        tier = tier,
                        onActionClick = { viewModel.syncBookmarks(fetchNextPage = false) }
                    )
                }
            }
        } else {
            items(bookmarks, key = { it.id }) { item ->
                Box(
                    modifier = Modifier.animateItem()
                ) {
                    val isProcessing = (analysisState as? AnalysisUiState.Processing)?.bookmarkId == item.id
                    val cardAnalysisError = analysisState as? AnalysisUiState.Error
                    val isAnalysisError = cardAnalysisError?.bookmarkId == item.id
                    val analysisErrorMessage = if (isAnalysisError) cardAnalysisError?.error else null
                    val chronosFlowInstalled = remember { viewModel.isChronosFlowInstalled() }
                    // Wrapped in remember(item) so the CurioCardActions object is recreated
                    // whenever ANY field of item changes (data class equals/hashCode). Using
                    // only item.id as the key causes stale lambda captures — e.g. onToggleFavorite
                    // would see the old isFavorite value because the key is never invalidated
                    // when a field other than id changes.
                    val cardActions = remember(item) {
                        CurioCardActions(
                            onProcessOcr = { bmp -> viewModel.processOcrForBookmark(item.id, bmp) },
                            onGenerateImagen = { viewModel.generateImagenImage(item.id) },
                            onSelectTag = { viewModel.selectTag(it) },
                            onSelectSpace = { viewModel.selectSpace(it) },
                            onAcceptCategory = { viewModel.acceptCategorySuggestion(item) },
                            onToggleFavorite = { viewModel.toggleFavorite(item) },
                            onToggleSavedForLater = { viewModel.toggleSavedForLater(item) },
                            onUpdateNotes = { viewModel.updateNotes(item.id, it) },
                            onAssignToSpace = { viewModel.assignBookmarksToSpace(listOf(item.id), it) },
                            onCreateSpaceAndAssign = { name, color, icon, description, rules, isPinned ->
                                viewModel.createSpaceAndAssign(name, color, icon, listOf(item.id), description, rules, isPinned)
                            },
                            onRunAiAnalysis = { viewModel.runAiAnalysis(item) },
                            onRunDeepAnalysis = { viewModel.runDeepAnalysis(item) },
                            onResolveSource = { viewModel.resolveSource(item) },
                            exportBibtex = { viewModel.exportSingleBibtex(item) },
                            onDelete = { deleteWithUndo(listOf(item)) },
                            onRemindInChronosFlow = { choice -> viewModel.remindToReadLaterInChronosFlow(item, choice) },
                            onCaptureToChronosFlow = { viewModel.captureToChronosFlowInbox(item) },
                            onCreateChronosFlowTask = { viewModel.createChronosFlowTask(item) },
                        )
                    }
                    // Swipe-to-triage: a left swipe now only REVEALS a pinned Delete dock (tap
                    // to arm, tap again to confirm — a swipe alone can no longer delete), and
                    // a committed right swipe toggles read-later (reversible, non-destructive).
                    // Disabled while multi-selecting or reordering so gestures don't collide.
                    val swipeEnabled = selectedIds.isEmpty() && !isReorderMode
                    SwipeRevealActions(
                        revealed = swipeEnabled && revealedCardId == item.id,
                        onRevealChange = { open ->
                            revealedCardId = when {
                                open -> item.id
                                revealedCardId == item.id -> null
                                else -> revealedCardId
                            }
                        },
                        onDelete = {
                            revealedCardId = null
                            deleteWithUndo(listOf(item))
                        },
                        onReadLater = { viewModel.toggleSavedForLater(item) },
                        readLaterActive = item.isSavedForLater,
                        gesturesEnabled = swipeEnabled,
                        deleteTestTag = "swipe_delete_${item.id}"
                    ) {
                        CurioPostCard(
                            bookmark = item,
                            actions = cardActions,
                            spaces = spaces,
                            isProcessing = isProcessing,
                            isAnalysisError = isAnalysisError,
                            analysisErrorMessage = analysisErrorMessage,
                            isImagenGenerated = imagenGeneratedIds.contains(item.id),
                            imagenUrl = imagenUrls[item.id],
                            tier = tier,
                            isSelected = selectedIds.contains(item.id),
                            onToggleSelect = {
                                selectedIds = if (selectedIds.contains(item.id)) {
                                    selectedIds - item.id
                                } else {
                                    selectedIds + item.id
                                }
                            },
                            inSelectionMode = selectedIds.isNotEmpty(),
                            isReorderMode = isReorderMode,
                            onMoveUp = { viewModel.moveBookmarkUp(item) },
                            onMoveDown = { viewModel.moveBookmarkDown(item) },
                            onBookmarkClick = { onBookmarkClick(item) },
                            chronosFlowInstalled = chronosFlowInstalled,
                            // Resolve the embedding suggestion (if any) to a live Space object; only
                            // shown for unfiled cards, so a stale suggestion for a now-filed card is inert.
                            suggestedSpace = spaceSuggestions[item.id]?.let { s ->
                                spaces.firstOrNull { it.id == s.spaceId }
                            }
                        )
                    }
                }
            }
        }

        item { Spacer(modifier = Modifier.height(80.dp)) }
    }

    // Undo host for destructive deletes — floats just above the bottom bar.
    SnackbarHost(
        hostState = snackbarHostState,
        modifier = Modifier.align(Alignment.BottomCenter).padding(16.dp)
    ) { data ->
        // Custom delete/undo snackbar — the default M3 snackbar's plain text button is too
        // easy to miss when it's the ONLY thing standing between the user and a permanent
        // (cloud-mirrored) delete. Error-toned icon + filled UNDO pill make recovery obvious.
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(MaterialTheme.colorScheme.surface)
                .border(1.dp, MaterialTheme.colorScheme.error.copy(alpha = 0.35f), RoundedCornerShape(16.dp))
                .padding(start = 12.dp, top = 8.dp, bottom = 8.dp, end = 8.dp)
                .testTag("delete_undo_snackbar"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Box(
                modifier = Modifier
                    .size(28.dp)
                    .background(MaterialTheme.colorScheme.error.copy(alpha = 0.14f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Default.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(15.dp))
            }
            Text(
                text = data.visuals.message,
                style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold),
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.weight(1f)
            )
            data.visuals.actionLabel?.let { label ->
                Text(
                    text = label.uppercase(),
                    style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black),
                    color = MaterialTheme.colorScheme.onError,
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(MaterialTheme.colorScheme.error)
                        .pressBounce { data.performAction() }
                        .padding(horizontal = 14.dp, vertical = 7.dp)
                        .testTag("undo_delete_button")
                )
            }
            if (data.visuals.withDismissAction) {
                Box(
                    modifier = Modifier
                        .minTouchTarget(40.dp)
                        .clip(CircleShape)
                        .pressBounce { data.dismiss() },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Default.Close, contentDescription = "Dismiss", tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), modifier = Modifier.size(16.dp))
                }
            }
        }
    }

    // Floating bulk operations action bar
    if (selectedIds.isNotEmpty()) {
        val cs = MaterialTheme.colorScheme
        val allIds by remember(bookmarks) { androidx.compose.runtime.derivedStateOf { bookmarks.map { it.id }.toSet() } }
        val allSelected = allIds.isNotEmpty() && selectedIds.containsAll(allIds)
        var confirmingBulkDelete by remember { mutableStateOf(false) }
        // Reset the delete-confirm arming whenever the selection changes underneath it.
        LaunchedEffect(selectedIds) { confirmingBulkDelete = false }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 24.dp, start = 16.dp, end = 16.dp)
                .align(Alignment.BottomCenter)
                .glassSurface(
                    tier = tier,
                    shape = RoundedCornerShape(28.dp),
                    tint = cs.surface.copy(alpha = 0.94f),
                    borderColor = cs.primary.copy(alpha = 0.35f)
                )
                .padding(14.dp)
                .animateContentSize(animationSpec = CurioMotion.liquid())
                .testTag("bulk_actions_panel")
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                // ── HEADER: count badge · label · select-all · close ──
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(11.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .background(cs.primary, CircleShape)
                            .bounceScale(true),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = "${selectedIds.size}",
                            style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Black),
                            color = cs.onPrimary
                        )
                    }
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = if (selectedIds.size == 1) "1 selected" else "${selectedIds.size} selected",
                            style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black),
                            color = cs.onSurface
                        )
                        Text(
                            text = "Bulk index operations",
                            style = MaterialTheme.typography.labelSmall,
                            color = cs.onSurface.copy(alpha = 0.5f)
                        )
                    }
                    // Select-all / clear-all quick toggle
                    Text(
                        text = if (allSelected) "CLEAR" else "ALL",
                        style = MaterialTheme.typography.labelMedium.copy(
                            fontWeight = FontWeight.Black,
                            letterSpacing = 0.5.sp
                        ),
                        color = cs.primary,
                        modifier = Modifier
                            .clip(RoundedCornerShape(50))
                            .background(cs.primary.copy(alpha = 0.12f))
                            .pressBounce { selectedIds = if (allSelected) emptySet() else allIds }
                            .padding(horizontal = 14.dp, vertical = 7.dp)
                            .testTag("bulk_select_all_button")
                    )
                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .clip(CircleShape)
                            .background(cs.onSurface.copy(alpha = 0.06f))
                            .pressBounce { selectedIds = emptySet() }
                            .testTag("bulk_cancel_button"),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.Close,
                            contentDescription = "Cancel bulk operation",
                            modifier = Modifier.size(18.dp),
                            tint = cs.onSurface.copy(alpha = 0.7f)
                        )
                    }
                }

                // ── ACTIONS: three equally-weighted tiles (never overflow) ──
                if (confirmingBulkDelete) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(16.dp))
                            .background(cs.error.copy(alpha = 0.10f))
                            .border(1.dp, cs.error.copy(alpha = 0.30f), RoundedCornerShape(16.dp))
                            .padding(start = 14.dp, top = 8.dp, bottom = 8.dp, end = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(Icons.Default.Delete, contentDescription = null, tint = cs.error, modifier = Modifier.size(18.dp))
                        Text(
                            text = "Delete ${selectedIds.size}?",
                            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold),
                            color = cs.onSurface,
                            modifier = Modifier.weight(1f)
                        )
                        Text(
                            "CANCEL",
                            style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black),
                            color = cs.onSurface.copy(alpha = 0.6f),
                            modifier = Modifier.clip(RoundedCornerShape(10.dp)).pressBounce { confirmingBulkDelete = false }.padding(horizontal = 12.dp, vertical = 8.dp)
                        )
                        Text(
                            "DELETE",
                            style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black),
                            color = cs.error,
                            modifier = Modifier
                                .clip(RoundedCornerShape(10.dp))
                                .background(cs.error.copy(alpha = 0.16f))
                                .pressBounce {
                                    deleteWithUndo(bookmarks.filter { it.id in selectedIds })
                                    selectedIds = emptySet()
                                }
                                .padding(horizontal = 14.dp, vertical = 8.dp)
                                .testTag("bulk_delete_confirm_button")
                        )
                    }
                } else {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        BulkActionTile(
                            label = "Space",
                            icon = Icons.Filled.Workspaces,
                            tint = cs.tertiary,
                            modifier = Modifier.weight(1f).testTag("bulk_space_button"),
                            onClick = { showBulkSpaceDialog = true }
                        )
                        BulkActionTile(
                            label = "Export",
                            icon = Icons.Default.Share,
                            tint = cs.secondary,
                            modifier = Modifier.weight(1f).testTag("bulk_export_button"),
                            onClick = { showExportDialog = true }
                        )
                        BulkActionTile(
                            label = "Delete",
                            icon = Icons.Default.Delete,
                            tint = cs.error,
                            modifier = Modifier.weight(1f).testTag("bulk_delete_button"),
                            onClick = { confirmingBulkDelete = true }
                        )
                    }
                }
            }
        }
    }
    }

    if (showExportDialog) {
        val selectedBookmarks = bookmarks.filter { selectedIds.contains(it.id) }
        SlideUpCard(
            onDismissRequest = { showExportDialog = false },
            tier = tier,
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
                    val dismiss = LocalSlideUpDismiss.current
                    Text(
                        text = "EXPORT ARCHIVE",
                        style = MaterialTheme.typography.titleMedium.copy(
                            fontWeight = FontWeight.ExtraBold,
                            color = MaterialTheme.colorScheme.secondary,
                            letterSpacing = 1.sp
                        )
                    )

                    Text(
                        text = "Export ${selectedIds.size} bookmarks to JSON, CSV, or BibTeX citation format.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center
                    )

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        // Export JSON button
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(48.dp)
                                .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(14.dp))
                                .clickable {
                                    val json = exportBackupJson(selectedBookmarks)
                                    copyToClipboard(context, json, notify = false)
                                    shareBookmark(context, json, notify = false)
                                    CurioNotifier.notify(context, "Copied & share sheet opened")
                                    selectedIds = emptySet()
                                    dismiss()
                                },
                            contentAlignment = Alignment.Center
                        ) {
                            Text("JSON", style = MaterialTheme.typography.labelMedium.copy(color = MaterialTheme.colorScheme.onPrimary, fontWeight = FontWeight.Black))
                        }

                        // Export CSV button
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(48.dp)
                                .background(MaterialTheme.colorScheme.secondary, RoundedCornerShape(14.dp))
                                .clickable {
                                    val csv = exportBackupCsv(selectedBookmarks)
                                    copyToClipboard(context, csv, notify = false)
                                    shareBookmark(context, csv, notify = false)
                                    CurioNotifier.notify(context, "Copied & share sheet opened")
                                    selectedIds = emptySet()
                                    dismiss()
                                },
                            contentAlignment = Alignment.Center
                        ) {
                            Text("CSV", style = MaterialTheme.typography.labelMedium.copy(color = MaterialTheme.colorScheme.onSecondary, fontWeight = FontWeight.Black))
                        }

                        // Export BibTeX button
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(48.dp)
                                .background(Color(0xFFB71C1C), RoundedCornerShape(14.dp))
                                .clickable {
                                    val bib = viewModel.exportBibtex(selectedBookmarks)
                                    copyToClipboard(context, bib, "BibTeX citations", notify = false)
                                    shareBookmark(context, bib, notify = false)
                                    CurioNotifier.notify(context, "Copied & share sheet opened")
                                    selectedIds = emptySet()
                                    dismiss()
                                },
                            contentAlignment = Alignment.Center
                        ) {
                            Text("BIBTEX", style = MaterialTheme.typography.labelMedium.copy(color = Color.White, fontWeight = FontWeight.Black))
                        }
                    }

                    // Additional citation formats for reference managers / notes.
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        listOf(
                            Triple("RIS", Color(0xFF455A64), { viewModel.exportRis(selectedBookmarks) }),
                            Triple("CSL-JSON", Color(0xFF5E35B1), { viewModel.exportCslJson(selectedBookmarks) }),
                            Triple("MARKDOWN", Color(0xFF00695C), { viewModel.exportMarkdown(selectedBookmarks) })
                        ).forEach { (label, color, build) ->
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .height(44.dp)
                                    .background(color, RoundedCornerShape(14.dp))
                                    .clickable {
                                        val out = build()
                                        copyToClipboard(context, out, "$label citations", notify = false)
                                        shareBookmark(context, out, notify = false)
                                        CurioNotifier.notify(context, "Copied & share sheet opened")
                                        selectedIds = emptySet()
                                        dismiss()
                                    },
                                contentAlignment = Alignment.Center
                            ) {
                                Text(label, style = MaterialTheme.typography.labelSmall.copy(color = Color.White, fontWeight = FontWeight.Black))
                            }
                        }
                    }

                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(44.dp)
                            .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f), RoundedCornerShape(14.dp))
                            .clickable { dismiss() },
                        contentAlignment = Alignment.Center
                    ) {
                        Text("CANCEL", style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)))
                    }
        }
    }

    if (showModelDialog) {
        val modelState = embeddingModelState
        var hfToken by remember { mutableStateOf("") }
        // Once the download finishes, drop straight into AI search and dismiss the dialog.
        LaunchedEffect(modelState) {
            if (modelState is EmbeddingModelManager.State.Ready) {
                viewModel.setSearchMode(SearchMode.SEMANTIC)
                showModelDialog = false
            }
        }
        SlideUpCard(
            onDismissRequest = { showModelDialog = false },
            tier = tier,
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
                    val dismiss = LocalSlideUpDismiss.current
                    Text(
                        text = "AI SEMANTIC SEARCH",
                        style = MaterialTheme.typography.titleMedium.copy(
                            fontWeight = FontWeight.ExtraBold,
                            color = MaterialTheme.colorScheme.secondary,
                            letterSpacing = 1.sp
                        )
                    )
                    Text(
                        text = "Searches your index by meaning, not just keywords. Runs fully on-device with EmbeddingGemma — a one-time ${EmbeddingModelManager.APPROX_SIZE_LABEL} download, and nothing leaves your phone.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center
                    )

                    val s = modelState
                    if (s is EmbeddingModelManager.State.Downloading) {
                        LinearProgressIndicator(
                            progress = { s.fraction.coerceIn(0f, 1f) },
                            modifier = Modifier.fillMaxWidth()
                        )
                        Text(
                            text = s.label,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                        )
                    } else {
                        if (s is EmbeddingModelManager.State.Failed) {
                            Text(
                                text = s.message,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.error,
                                textAlign = androidx.compose.ui.text.style.TextAlign.Center
                            )
                        }
                        // EmbeddingGemma is Gemma-license-gated on Hugging Face. Paste a token
                        // once (stored encrypted and reused); get one at huggingface.co/settings/tokens.
                        val hfUriHandler = LocalUriHandler.current
                        val hfLinkColor = MaterialTheme.colorScheme.primary
                        val hfLabelText = buildAnnotatedString {
                            append("Hugging Face token — get one at ")
                            pushStringAnnotation("URL", "https://huggingface.co/settings/tokens")
                            withStyle(SpanStyle(color = hfLinkColor, textDecoration = TextDecoration.Underline)) {
                                append("huggingface.co/settings/tokens")
                            }
                            pop()
                        }
                        ClickableText(
                            text = hfLabelText,
                            style = MaterialTheme.typography.labelSmall.copy(
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                            ),
                            onClick = { offset ->
                                hfLabelText.getStringAnnotations("URL", offset, offset)
                                    .firstOrNull()?.let { hfUriHandler.openUri(it.item) }
                            }
                        )
                        androidx.compose.material3.OutlinedTextField(
                            value = hfToken,
                            onValueChange = { hfToken = it },
                            singleLine = true,
                            label = { Text("Paste token here") },
                            visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation(),
                            modifier = Modifier.fillMaxWidth()
                        )
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(48.dp)
                                .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(14.dp))
                                .clickable { viewModel.downloadEmbeddingModel(hfToken) },
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = if (s is EmbeddingModelManager.State.Failed) "RETRY DOWNLOAD" else "DOWNLOAD (${EmbeddingModelManager.APPROX_SIZE_LABEL})",
                                style = MaterialTheme.typography.labelMedium.copy(color = MaterialTheme.colorScheme.onPrimary, fontWeight = FontWeight.Black)
                            )
                        }
                    }

                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(44.dp)
                            .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f), RoundedCornerShape(14.dp))
                            .clickable { dismiss() },
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = if (modelState is EmbeddingModelManager.State.Downloading) "CONTINUE IN BACKGROUND" else "CANCEL",
                            style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                        )
                    }
        }
    }

    if (showBulkSpaceDialog) {
        // Highlight the common Space only when every selected item shares it.
        val selected = bookmarks.filter { selectedIds.contains(it.id) }
        val commonSpaceId = selected.map { it.spaceId }.distinct().singleOrNull()
        AssignToSpaceDialog(
            spaces = spaces,
            currentSpaceId = commonSpaceId,
            tier = tier,
            onDismiss = { showBulkSpaceDialog = false },
            onAssign = { spaceId ->
                viewModel.assignBookmarksToSpace(selectedIds.toList(), spaceId)
                showBulkSpaceDialog = false
                selectedIds = emptySet()
            },
            onCreateSpace = {
                showBulkSpaceDialog = false
                showBulkNewSpace = true
            }
        )
    }

    if (showBulkNewSpace) {
        SpaceEditorDialog(
            existing = null,
            tier = tier,
            onDismiss = { showBulkNewSpace = false },
            onConfirm = { name, color, icon, description, rules, isPinned ->
                viewModel.createSpaceAndAssign(name, color, icon, selectedIds.toList(), description, rules, isPinned)
                showBulkNewSpace = false
                selectedIds = emptySet()
            }
        )
    }
    }
}

/** A tinted, equally-weighted action tile in the bulk-selection bar (icon over label). */
@Composable
private fun BulkActionTile(
    label: String,
    icon: ImageVector,
    tint: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .background(tint.copy(alpha = 0.13f))
            .pressBounce(onClick = onClick)
            .padding(vertical = 11.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Icon(icon, contentDescription = label, tint = tint, modifier = Modifier.size(19.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.ExtraBold),
            color = tint,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}
