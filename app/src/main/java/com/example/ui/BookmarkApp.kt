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
import androidx.compose.material.icons.filled.CloudSync
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Psychology
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
import androidx.compose.material.icons.outlined.Workspaces
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
import androidx.compose.foundation.layout.consumeWindowInsets
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material.icons.filled.Article
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Hub
import androidx.compose.material.icons.automirrored.filled.MenuBook
import java.text.SimpleDateFormat
import java.util.Locale

/**
 * Main application container that coordinates theme options, navigation,
 * and high-fidelity glass scaffold layouts.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun BookmarkApp(authViewModel: AuthViewModel, bookmarkViewModel: BookmarkViewModel) {
    val authState by authViewModel.authState.collectAsStateWithLifecycle()
    var currentRoute by remember { mutableStateOf(CurioDestination.Bookmarks) }
    var useDynamicColor by remember { mutableStateOf(true) }
    var glassTierOverride by remember { mutableStateOf<GlassTier?>(null) }
    var showInputForm by remember { mutableStateOf(false) }

    // Theme collection supporting the system-aware toggle configuration
    val themeSetting by bookmarkViewModel.themeSetting.collectAsStateWithLifecycle()
    val sysDark = isSystemInDarkTheme()
    val darkTheme = remember(themeSetting, sysDark) {
        when (themeSetting) {
            AppThemeSetting.SYSTEM -> sysDark
            AppThemeSetting.LIGHT -> false
            AppThemeSetting.DARK -> true
        }
    }

    // Re-evaluate glass tier based on automatic resolution and manual overrides
    val resolvedTier = rememberGlassTier(glassTierOverride)
    val context = LocalContext.current

    if (authState !is AuthState.SignedIn) {
        BookmarkTheme(
            darkTheme = darkTheme,
            dynamicColor = useDynamicColor
        ) {
            LoginScreen(
                state = authState,
                tier = resolvedTier,
                onLoginClick = {
                    authViewModel.onLoginClick { url ->
                        (context as? MainActivity)?.launchOAuthBrowser(url)
                    }
                }
            )
        }
        return
    }

    val signedInState = authState as AuthState.SignedIn
    // Set the user context in the BookmarkViewModel once upon rendering
    LaunchedEffect(signedInState.userId) {
        bookmarkViewModel.setUserId(signedInState.userId)
    }

    var activeReaderBookmark by remember { mutableStateOf<Bookmark?>(null) }
    val isKeyboardOpen = WindowInsets.isImeVisible
    val drawerState = androidx.compose.material3.rememberDrawerState(androidx.compose.material3.DrawerValue.Closed)
    val coroutineScope = rememberCoroutineScope()

    BookmarkTheme(
        darkTheme = darkTheme,
        dynamicColor = useDynamicColor
    ) {
        androidx.compose.material3.ModalNavigationDrawer(
            drawerState = drawerState,
            drawerContent = {
                androidx.compose.material3.ModalDrawerSheet(
                    modifier = Modifier
                        .width(310.dp)
                        .fillMaxHeight(),
                    drawerContainerColor = MaterialTheme.colorScheme.background,
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .statusBarsPadding()
                            .padding(20.dp)
                            .verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        // Brand + signed-in identity header
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .glassSurface(tier = resolvedTier, shape = RoundedCornerShape(16.dp))
                                .padding(16.dp)
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp)
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(44.dp)
                                        .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f), CircleShape),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        imageVector = Icons.Filled.Bookmarks,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.primary,
                                        modifier = Modifier.size(24.dp)
                                    )
                                }
                                Column(modifier = Modifier.weight(1f)) {
                                    Text("Curio", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black))
                                    Text(
                                        "Your research index",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                            }
                        }

                        // Divider line
                        Box(modifier = Modifier.fillMaxWidth().height(1.dp).background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)))

                        Text(
                            "WORKSPACE",
                            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.ExtraBold, letterSpacing = 1.2.sp),
                            color = MaterialTheme.colorScheme.primary
                        )

                        val navigate: (CurioDestination) -> Unit = { dest ->
                            currentRoute = dest
                            coroutineScope.launch { drawerState.close() }
                        }

                        DrawerNavRow(
                            icon = Icons.Filled.Bookmarks,
                            label = "My Bookmarks",
                            selected = currentRoute == CurioDestination.Bookmarks,
                            onClick = { navigate(CurioDestination.Bookmarks) }
                        )
                        DrawerNavRow(
                            icon = Icons.Filled.Workspaces,
                            label = "Spaces",
                            selected = currentRoute == CurioDestination.Spaces,
                            onClick = { navigate(CurioDestination.Spaces) }
                        )
                        DrawerNavRow(
                            icon = Icons.Filled.BarChart,
                            label = "Insights",
                            selected = currentRoute == CurioDestination.Insights,
                            onClick = { navigate(CurioDestination.Insights) }
                        )
                        DrawerNavRow(
                            icon = Icons.Filled.Psychology,
                            label = "Curio AI Chat",
                            selected = currentRoute == CurioDestination.Chat,
                            onClick = { navigate(CurioDestination.Chat) }
                        )

                        Spacer(modifier = Modifier.weight(1f))

                        // Divider line
                        Box(modifier = Modifier.fillMaxWidth().height(1.dp).background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)))

                        // Settings sits at the bottom, just above the connected account
                        DrawerNavRow(
                            icon = Icons.Filled.Settings,
                            label = "Settings",
                            selected = currentRoute == CurioDestination.Settings,
                            onClick = { navigate(CurioDestination.Settings) }
                        )

                        // Connected X account — tap to manage the session (sign out lives in Settings)
                        XAccountCard(
                            name = signedInState.name,
                            username = signedInState.username,
                            userId = signedInState.userId,
                            tier = resolvedTier,
                            onClick = { navigate(CurioDestination.Settings) }
                        )
                    }
                }
            }
        ) {
            // Aesthetic layered radial color effect for premium background depth
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        brush = Brush.verticalGradient(
                            colors = listOf(
                                MaterialTheme.colorScheme.background,
                                MaterialTheme.colorScheme.inverseOnSurface.copy(alpha = 0.5f)
                            )
                        )
                    )
            ) {
                val navItems = listOf(
                    GlassNavigationItem(
                        selectedIcon = Icons.Filled.Bookmarks,
                        unselectedIcon = Icons.Outlined.Bookmarks,
                        label = "Bookmarks",
                        route = "bookmarks"
                    ),
                    GlassNavigationItem(
                        selectedIcon = Icons.Filled.Workspaces,
                        unselectedIcon = Icons.Outlined.Workspaces,
                        label = "Spaces",
                        route = "spaces"
                    ),
                    GlassNavigationItem(
                        selectedIcon = Icons.Filled.Psychology,
                        unselectedIcon = Icons.Filled.Psychology,
                        label = "Curio AI",
                        route = "chatbot"
                    )
                )

                GlassScaffold(
                    topBar = { tier ->
                        // The bookmarks feed embeds its own merged search header (menu + search),
                        // so we skip the separate title bar there to reclaim vertical space.
                        if (currentRoute != CurioDestination.Bookmarks) {
                            GlassTopBar(
                                title = currentRoute.title,
                                tier = resolvedTier,
                                navigationIcon = {
                                    IconButton(onClick = { coroutineScope.launch { drawerState.open() } }) {
                                        Icon(
                                            imageVector = Icons.Default.Menu,
                                            contentDescription = "Open side workspace menu",
                                            tint = MaterialTheme.colorScheme.primary
                                        )
                                    }
                                }
                            )
                        }
                    },
                    bottomBar = { tier ->
                        if (!isKeyboardOpen) {
                            GlassBottomBar(
                                items = navItems,
                                currentRoute = currentRoute.id,
                                tier = resolvedTier,
                                onNavigate = { currentRoute = CurioDestination.fromId(it) }
                            )
                        }
                    },
                    floatingActionButton = { tier ->
                        if (currentRoute == CurioDestination.Bookmarks) {
                            LiquidGlassFab(
                                onClick = { showInputForm = true },
                                tier = resolvedTier,
                                icon = {
                                    Icon(
                                        imageVector = Icons.Default.Add,
                                        contentDescription = "Add manual bookmark",
                                        tint = MaterialTheme.colorScheme.primary,
                                        modifier = Modifier.size(24.dp).testTag("fab_add_bookmark")
                                    )
                                }
                            )
                        }
                    }
                ) { innerPadding, tier ->
                    if (showInputForm) {
                        ManualAddBookmarkDialog(
                            onDismissRequest = { showInputForm = false },
                            onAddBookmark = { text ->
                                bookmarkViewModel.addManualBookmark(text) { result ->
                                    result.onSuccess { newBookmark ->
                                        bookmarkViewModel.runAiAnalysis(newBookmark)
                                    }
                                }
                            },
                            tier = resolvedTier,
                            viewModel = bookmarkViewModel
                        )
                    }

                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(innerPadding)
                            .consumeWindowInsets(innerPadding)
                    ) {
                        when (currentRoute) {
                            CurioDestination.Bookmarks -> BookmarkFeedScreen(
                                viewModel = bookmarkViewModel,
                                tier = resolvedTier,
                                onBookmarkClick = { activeReaderBookmark = it },
                                onOpenMenu = { coroutineScope.launch { drawerState.open() } }
                            )
                            CurioDestination.Spaces -> CurioSpacesScreen(
                                viewModel = bookmarkViewModel,
                                tier = resolvedTier,
                                onOpenSpace = { space ->
                                    bookmarkViewModel.selectSpace(space.id)
                                    currentRoute = CurioDestination.Bookmarks
                                }
                            )
                            CurioDestination.Insights -> CurioInsightsScreen(
                                viewModel = bookmarkViewModel,
                                tier = resolvedTier,
                                onNavigateToFeed = { currentRoute = CurioDestination.Bookmarks }
                            )
                            CurioDestination.Chat -> CurioChatScreen(
                                viewModel = bookmarkViewModel,
                                tier = resolvedTier
                            )
                            CurioDestination.Settings -> SettingsScreen(
                                useDynamicColor = useDynamicColor,
                                onToggleDynamicColor = { useDynamicColor = it },
                                glassTierOverride = glassTierOverride,
                                onSetGlassTierOverride = { glassTierOverride = it },
                                resolvedTier = resolvedTier,
                                onLogout = { authViewModel.onLogout() },
                                viewModel = bookmarkViewModel
                            )
                        }
                    }
                }
            }
        }
    }

    activeReaderBookmark?.let { b ->
        ReaderViewScreen(
            bookmark = b,
            onClose = { activeReaderBookmark = null },
            tier = resolvedTier,
            darkTheme = darkTheme,
            dynamicColor = useDynamicColor
        )
    }
}

/**
 * A single navigation row inside the workspace drawer. Highlights itself when [selected]
 * and falls back to a neutral tint otherwise. Pass [tint] to force an accent colour
 * (e.g. destructive actions such as Sign Out).
 */
@Composable
private fun DrawerNavRow(
    icon: ImageVector,
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    tint: Color? = null
) {
    val contentTint = tint
        ?: if (selected) MaterialTheme.colorScheme.primary
        else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.12f) else Color.Transparent)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(icon, contentDescription = null, tint = contentTint)
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium.copy(
                color = tint ?: MaterialTheme.colorScheme.onSurface,
                fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal
            )
        )
    }
}

/**
 * Compact card showing the connected X (Twitter) account at the bottom of the drawer.
 * Falls back gracefully when only the numeric user id is known (e.g. a session restored
 * from before the handle was persisted). Tapping it opens Settings, where the session can
 * be signed out.
 */
@Composable
private fun XAccountCard(
    name: String?,
    username: String?,
    userId: String,
    tier: GlassTier,
    onClick: () -> Unit
) {
    val displayName = name?.takeIf { it.isNotBlank() } ?: "X Account"
    val handle = username?.takeIf { it.isNotBlank() }?.let { "@$it" } ?: "ID $userId"
    val initial = (name ?: username ?: "X").trim().firstOrNull()?.uppercaseChar()?.toString() ?: "X"
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .glassSurface(tier = tier, shape = RoundedCornerShape(16.dp))
            .clickable(onClick = onClick)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Text(
                initial,
                style = MaterialTheme.typography.titleMedium.copy(
                    fontWeight = FontWeight.Black,
                    color = MaterialTheme.colorScheme.primary
                )
            )
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                displayName,
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                handle,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        Text(
            "𝕏",
            style = MaterialTheme.typography.titleMedium.copy(
                fontWeight = FontWeight.Black,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.45f)
            )
        )
    }
}
