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
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.Bookmarks
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.TextButton
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.runtime.mutableStateMapOf
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
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import kotlin.math.roundToInt
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
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
import androidx.compose.foundation.text.ClickableText
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
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
internal fun SettingsScreen(
    onLogout: () -> Unit,
    viewModel: BookmarkViewModel
) {
    val context = LocalContext.current
    val scrollState = rememberScrollState()
    val scope = rememberCoroutineScope()
    val sectionOffsets = remember { mutableStateMapOf<String, Int>() }
    var showPurgeConfirm by remember { mutableStateOf(false) }
    var showModelDeleteConfirm by remember { mutableStateOf(false) }
    val useDynamicColor by viewModel.useDynamicColor.collectAsStateWithLifecycle()
    val glassTierOverride by viewModel.glassTierOverride.collectAsStateWithLifecycle()
    val resolvedTier = rememberGlassTier(glassTierOverride)
    val sectionChips = listOf(
        "Look" to "appearance",
        "Keys" to "keys",
        "Agent" to "agent",
        "Session" to "session",
        "Data" to "data",
        "AI Tools" to "intel",
        "Model" to "model"
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(scrollState)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            sectionChips.forEach { (label, key) ->
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f))
                        .pressBounce {
                            scope.launch {
                                scrollState.animateScrollTo(sectionOffsets[key] ?: 0)
                            }
                        }
                        .padding(horizontal = 14.dp, vertical = 8.dp)
                ) {
                    Text(
                        label,
                        style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold),
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }
        }

        // Aesthetics & Colors Card
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .onGloballyPositioned { sectionOffsets["appearance"] = it.positionInParent().y.roundToInt() }
                .glassSurface(tier = resolvedTier)
                .padding(16.dp)
        ) {
            Column {
                Text(
                    text = "Aesthetics & Colors",
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)
                )
                Spacer(modifier = Modifier.height(8.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "Material You Theme",
                            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold)
                        )
                        Text(
                            text = "Toggle wallpaper-based dynamic colors (Android only)",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                        )
                    }
                    Switch(
                        checked = useDynamicColor,
                        onCheckedChange = { viewModel.setUseDynamicColor(it) },
                        modifier = Modifier.testTag("dynamic_color_switch")
                    )
                }

                Spacer(modifier = Modifier.height(12.dp))
                androidx.compose.material3.HorizontalDivider(color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f))
                Spacer(modifier = Modifier.height(12.dp))

                Text(
                    text = "OS Dark Style Preference",
                    style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold)
                )
                Spacer(modifier = Modifier.height(6.dp))

                val themeSetting by viewModel.themeSetting.collectAsStateWithLifecycle()

                listOf(
                    AppThemeSetting.SYSTEM to "System Aware (Follow OS Theme)",
                    AppThemeSetting.LIGHT to "Liquid Glass Frost Light",
                    AppThemeSetting.DARK to "Liquid Glass Charcoal Dark"
                ).forEach { (themeOption, optionTitle) ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .pressBounce { viewModel.setThemeSetting(themeOption) }
                            .padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        RadioButton(
                            selected = themeSetting == themeOption,
                            onClick = { viewModel.setThemeSetting(themeOption) }
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = optionTitle,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                    }
                }
            }
        }

        // xAI API Key Card — BYOK: Curio ships without any built-in key.
        // Users must supply their own key from console.x.ai to unlock AI features.
        // The key is stored AES-GCM-encrypted via TokenStore (never leaves the device).
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .onGloballyPositioned { sectionOffsets["keys"] = it.positionInParent().y.roundToInt() }
                .glassSurface(tier = resolvedTier)
                .padding(16.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                val keyStatus by viewModel.xaiKeyStatus.collectAsStateWithLifecycle()
                val keyConfigured = keyStatus is XaiKeyStatus.Present
                // Not using rememberSaveable intentionally: key input is transient; saved key is in TokenStore.
                val keyInput = androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf("") }
                Text(
                    text = "xAI API Key",
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)
                )
                // Live status line: tells the user whether a key is present, WHERE it came from
                // (loaded from encrypted storage vs just saved), and whether it is actually live —
                // verified against xAI's key-introspection endpoint — rather than merely stored.
                val neutral = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                val presentOrigin = (keyStatus as? XaiKeyStatus.Present)
                val originLabel = when (presentOrigin?.origin) {
                    XaiKeyOrigin.JUST_SAVED -> "Key saved"
                    else -> "Key loaded from encrypted storage"
                }
                val (statusColor, statusText) = when (val s = keyStatus) {
                    XaiKeyStatus.Unknown -> neutral to "Checking for a saved key…"
                    XaiKeyStatus.NotSet -> MaterialTheme.colorScheme.error to "No key set — AI features are off."
                    is XaiKeyStatus.Present -> when (val c = s.check) {
                        XaiKeyCheck.Checking -> neutral to "$originLabel — verifying with xAI…"
                        XaiKeyCheck.Live -> Color(0xFF4CAF50) to "$originLabel — live ✓ verified with xAI."
                        is XaiKeyCheck.Invalid -> MaterialTheme.colorScheme.error to "$originLabel — not working: ${c.reason}."
                        XaiKeyCheck.Unreachable -> Color(0xFFFFA000) to "$originLabel — couldn't reach xAI to verify it."
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("xai_key_status")) {
                    if (presentOrigin?.check == XaiKeyCheck.Checking || keyStatus == XaiKeyStatus.Unknown) {
                        CircularProgressIndicator(modifier = Modifier.size(10.dp), strokeWidth = 1.5.dp)
                    } else {
                        Box(
                            modifier = Modifier
                                .size(10.dp)
                                .background(statusColor, CircleShape)
                        )
                    }
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = statusText,
                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                        color = statusColor,
                        modifier = Modifier.weight(1f)
                    )
                    // Re-check is only offered when a check finished and could change: a failed
                    // verify (bad network) or a rejected key the user has since re-enabled.
                    if (presentOrigin != null &&
                        (presentOrigin.check is XaiKeyCheck.Invalid || presentOrigin.check == XaiKeyCheck.Unreachable)
                    ) {
                        Text(
                            text = "Retry",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier
                                .pressBounce { viewModel.verifyXaiKey() }
                                .padding(start = 8.dp)
                                .testTag("xai_key_retry")
                        )
                    }
                }
                val uriHandler = LocalUriHandler.current
                val linkColor = MaterialTheme.colorScheme.primary
                val labelStyle = MaterialTheme.typography.labelSmall
                // Guidance + console.x.ai link stays visible in BOTH states: when unconfigured it
                // tells the user a key is required; when configured it's still the place to grab a
                // replacement key to rotate. Leading text and colour vary by state.
                val xaiText = buildAnnotatedString {
                    val baseColor = if (keyConfigured) {
                        MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                    } else {
                        MaterialTheme.colorScheme.error.copy(alpha = 0.8f)
                    }
                    if (keyConfigured) {
                        withStyle(SpanStyle(color = baseColor)) {
                            // Presence/liveness now lives in the status line above; this line is
                            // just the rotation pointer.
                            append("AI analysis, chat, and image generation use this key. Rotate it anytime at ")
                        }
                    } else {
                        withStyle(SpanStyle(color = baseColor)) { append("Required. Get a free key at ") }
                    }
                    pushStringAnnotation("URL", "https://console.x.ai")
                    withStyle(SpanStyle(color = linkColor, textDecoration = TextDecoration.Underline)) {
                        append("console.x.ai")
                    }
                    pop()
                    withStyle(SpanStyle(color = baseColor)) { append(" → API Keys. Stored encrypted on this device only.") }
                }
                ClickableText(
                    text = xaiText,
                    style = labelStyle,
                    onClick = { offset ->
                        xaiText.getStringAnnotations("URL", offset, offset)
                            .firstOrNull()?.let { uriHandler.openUri(it.item) }
                    }
                )
                androidx.compose.material3.OutlinedTextField(
                    value = keyInput.value,
                    onValueChange = { keyInput.value = it },
                    label = { Text("xai-…") },
                    singleLine = true,
                    visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation(),
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                        keyboardType = androidx.compose.ui.text.input.KeyboardType.Password
                    ),
                    modifier = Modifier.fillMaxWidth().testTag("xai_key_input")
                )
                androidx.compose.material3.Button(
                    onClick = {
                        viewModel.saveXaiKey(keyInput.value)
                        keyInput.value = ""
                    },
                    enabled = keyInput.value.isNotBlank(),
                    modifier = Modifier.testTag("xai_key_save")
                ) { Text("Save key") }
            }
        }

        // X OAuth Client ID Card — BYOK for bookmark sync. The built-in client ID is a shared
        // default; users whose sync fails with "authentication failed" can create their own X app
        // and paste its OAuth 2.0 client ID here. Tokens are minted per-client, so changing the ID
        // requires a fresh sign-in (the status line says so).
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .glassSurface(tier = resolvedTier)
                .padding(16.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                val clientIdStatus by viewModel.xClientIdStatus.collectAsStateWithLifecycle()
                val clientIdInput = androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf("") }
                Text(
                    text = "X API Client ID",
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)
                )
                val (idColor, idText) = when (clientIdStatus) {
                    XClientIdStatus.BUILT_IN ->
                        MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f) to
                            "Using Curio's built-in client ID."
                    XClientIdStatus.CUSTOM_LOADED ->
                        Color(0xFF4CAF50) to "Your client ID is loaded and in use."
                    XClientIdStatus.CUSTOM_SAVED ->
                        Color(0xFF4CAF50) to "Your client ID is saved — sign out and back in to activate it."
                }
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("x_client_id_status")) {
                    Box(
                        modifier = Modifier
                            .size(10.dp)
                            .background(idColor, CircleShape)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = idText,
                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                        color = idColor
                    )
                }
                val uriHandler = LocalUriHandler.current
                val linkColor = MaterialTheme.colorScheme.primary
                val clientIdHelp = buildAnnotatedString {
                    val baseColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                    withStyle(SpanStyle(color = baseColor)) {
                        append(
                            "If bookmark sync fails with “authentication failed”, create a free X app at "
                        )
                    }
                    pushStringAnnotation("URL", "https://developer.x.com")
                    withStyle(SpanStyle(color = linkColor, textDecoration = TextDecoration.Underline)) {
                        append("developer.x.com")
                    }
                    pop()
                    withStyle(SpanStyle(color = baseColor)) {
                        append(
                            " and paste its OAuth 2.0 client ID here. Leave blank and save to go back " +
                                "to the built-in ID. Changing it requires signing out and back in."
                        )
                    }
                }
                ClickableText(
                    text = clientIdHelp,
                    style = MaterialTheme.typography.labelSmall,
                    onClick = { offset ->
                        clientIdHelp.getStringAnnotations("URL", offset, offset)
                            .firstOrNull()?.let { uriHandler.openUri(it.item) }
                    }
                )
                androidx.compose.material3.OutlinedTextField(
                    value = clientIdInput.value,
                    onValueChange = { clientIdInput.value = it },
                    label = { Text("OAuth 2.0 Client ID") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().testTag("x_client_id_input")
                )
                androidx.compose.material3.Button(
                    onClick = {
                        viewModel.saveXClientId(clientIdInput.value)
                        clientIdInput.value = ""
                    },
                    modifier = Modifier.testTag("x_client_id_save")
                ) { Text("Save client ID") }
            }
        }

        // Assistant write-access Card — controls whether on-device AI agents / system assistants
        // may modify bookmarks via Curio's AppFunctions. The appfunctions alpha09 API does not
        // expose the calling package to function code, so this user toggle is the available
        // defence; read-only discovery stays enabled regardless. Gate lives in CurioFunctions.
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .onGloballyPositioned { sectionOffsets["agent"] = it.positionInParent().y.roundToInt() }
                .glassSurface(tier = resolvedTier)
                .padding(16.dp)
        ) {
            val allowAgentWrites by viewModel.allowAgentWrites.collectAsStateWithLifecycle()
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Allow assistants to modify my bookmarks",
                        style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)
                    )
                    Text(
                        text = "When off, AI agents and system assistants can still search and read " +
                            "your library, but can't add bookmarks, edit notes, or change favourites.",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                    )
                }
                Spacer(modifier = Modifier.width(12.dp))
                Switch(
                    checked = allowAgentWrites,
                    onCheckedChange = { viewModel.setAllowAgentWrites(it) },
                    modifier = Modifier.testTag("agent_writes_switch")
                )
            }
        }

        // Active Session Check & Clear Local Cache Card
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .onGloballyPositioned { sectionOffsets["session"] = it.positionInParent().y.roundToInt() }
                .glassSurface(tier = resolvedTier)
                .padding(16.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    text = "Account",
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)
                )

                val accountName by viewModel.accountName.collectAsStateWithLifecycle()
                val accountUsername by viewModel.accountUsername.collectAsStateWithLifecycle()
                val accountAvatarUrl by viewModel.accountAvatarUrl.collectAsStateWithLifecycle()
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // X hands back the tiny 48×48 "_normal" variant; swap in the 400×400 one so
                    // the avatar stays sharp on high-density screens.
                    val displayAvatarUrl = accountAvatarUrl?.replace("_normal", "_400x400")
                    if (displayAvatarUrl != null) {
                        coil.compose.AsyncImage(
                            model = displayAvatarUrl,
                            contentDescription = "X profile photo",
                            modifier = Modifier
                                .size(44.dp)
                                .clip(CircleShape)
                                .testTag("account_avatar")
                        )
                    } else {
                        Box(
                            modifier = Modifier
                                .size(44.dp)
                                .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.1f), CircleShape),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                Icons.Default.Person,
                                contentDescription = "X profile photo placeholder",
                                modifier = Modifier.size(20.dp),
                                tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                            )
                        }
                    }
                    Spacer(modifier = Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = accountName ?: "Signed in with X",
                            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold)
                        )
                        Text(
                            text = accountUsername?.let { "@$it" }
                                ?: "Locally encrypted security token handles active",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                        )
                    }
                    Box(
                        modifier = Modifier
                            .background(
                                color = MaterialTheme.colorScheme.error.copy(alpha = 0.15f),
                                shape = RoundedCornerShape(12.dp)
                            )
                            .pressBounce { onLogout() }
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                            .testTag("logout_button")
                    ) {
                        Text(
                            text = "SIGN OUT",
                            style = MaterialTheme.typography.labelSmall.copy(
                                color = MaterialTheme.colorScheme.error,
                                fontWeight = FontWeight.ExtraBold
                            )
                        )
                    }
                }

                Spacer(modifier = Modifier.height(8.dp))
                HorizontalDivider(color = MaterialTheme.colorScheme.error.copy(alpha = 0.2f))
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "DANGER ZONE",
                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Black, letterSpacing = 1.sp),
                    color = MaterialTheme.colorScheme.error.copy(alpha = 0.8f)
                )
                Spacer(modifier = Modifier.height(4.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "Purge Local Database",
                            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold)
                        )
                        Text(
                            text = "Clears cached bookmark lists and OCR records safely",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                        )
                    }
                    Box(
                        modifier = Modifier
                            .background(
                                color = MaterialTheme.colorScheme.error.copy(alpha = 0.12f),
                                shape = RoundedCornerShape(12.dp)
                            )
                            .pressBounce { showPurgeConfirm = true }
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Icon(Icons.Default.DeleteSweep, contentDescription = "Purge DB icon", modifier = Modifier.size(16.dp), tint = MaterialTheme.colorScheme.error)
                            Text(
                                text = "PURGE CACHE",
                                style = MaterialTheme.typography.labelSmall.copy(
                                    fontWeight = FontWeight.ExtraBold,
                                    color = MaterialTheme.colorScheme.error
                                )
                            )
                        }
                    }
                }
            }
        }

        if (showPurgeConfirm) {
            androidx.compose.material3.AlertDialog(
                onDismissRequest = { showPurgeConfirm = false },
                title = { Text("Purge local cache?") },
                text = {
                    Text(
                        "Clears cached bookmark lists and OCR records. Your X session and cloud sync are unaffected.",
                        style = MaterialTheme.typography.bodySmall
                    )
                },
                confirmButton = {
                    TextButton(onClick = {
                        showPurgeConfirm = false
                        viewModel.clearAllData()
                        CurioNotifier.notify(context, "Local cache cleared")
                    }) {
                        Text("Purge cache", color = MaterialTheme.colorScheme.error, fontWeight = FontWeight.Bold)
                    }
                },
                dismissButton = {
                    TextButton(onClick = { showPurgeConfirm = false }) {
                        Text("Cancel")
                    }
                }
            )
        }

        if (showModelDeleteConfirm) {
            androidx.compose.material3.AlertDialog(
                onDismissRequest = { showModelDeleteConfirm = false },
                title = { Text("Delete on-device model?") },
                text = {
                    Text(
                        "Removes the downloaded semantic-search model (~25MB). AI search falls back to keyword search until you download it again.",
                        style = MaterialTheme.typography.bodySmall
                    )
                },
                confirmButton = {
                    TextButton(onClick = {
                        showModelDeleteConfirm = false
                        viewModel.deleteEmbeddingModel()
                    }) {
                        Text("Delete", color = MaterialTheme.colorScheme.error, fontWeight = FontWeight.Bold)
                    }
                },
                dismissButton = {
                    TextButton(onClick = { showModelDeleteConfirm = false }) {
                        Text("Cancel")
                    }
                }
            )
        }

        // Backup & Data Portability Card (Phase 6)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .onGloballyPositioned { sectionOffsets["data"] = it.positionInParent().y.roundToInt() }
                .glassSurface(tier = resolvedTier)
                .padding(16.dp)
        ) {
            val rawBookmarks by viewModel.rawBookmarks.collectAsStateWithLifecycle()
            val context = LocalContext.current
            
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    text = "Data Portability & Porting",
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)
                )
                
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "Backup & Export JSON",
                            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold)
                        )
                        Text(
                            text = "Extracts all offline stored bookmarks, screen extractions and AI curation tags securely",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                        )
                    }
                    Box(
                        modifier = Modifier
                            .background(
                                color = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f),
                                shape = RoundedCornerShape(12.dp)
                            )
                            .pressBounce {
                                if (rawBookmarks.isEmpty()) {
                                    CurioNotifier.notify(context, "No local bookmarks to export")
                                } else {
                                    val jsonString = exportBackupJson(rawBookmarks)
                                    copyToClipboard(context, jsonString, "Curio Backup JSON", notify = false)
                                    shareBookmark(context, jsonString, notify = false)
                                    CurioNotifier.notify(context, "Backup copied — share sheet opened")
                                }
                            }
                            .padding(horizontal = 16.dp, vertical = 8.dp)
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Icon(Icons.Default.CloudSync, contentDescription = "Export JSON backup icon", modifier = Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                            Text(
                                text = "BACKUP JSON",
                                style = MaterialTheme.typography.labelSmall.copy(
                                    fontWeight = FontWeight.ExtraBold,
                                    color = MaterialTheme.colorScheme.primary
                                )
                            )
                        }
                    }
                }
            }
        }

        // Research Intelligence Card (Phases 8-11)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .onGloballyPositioned { sectionOffsets["intel"] = it.positionInParent().y.roundToInt() }
                .glassSurface(tier = resolvedTier)
                .padding(16.dp)
        ) {
            val context = LocalContext.current
            // Embed/Resolve/Dedup all report through syncState; surface it here (where the buttons
            // live) so the user sees live progress and the final result without leaving Settings.
            val researchStatus by viewModel.syncState.collectAsStateWithLifecycle()
            var embeddingBackend by remember {
                mutableStateOf(com.example.data.embedding.EmbeddingPreference.get(context))
            }
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    text = "Research Intelligence",
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)
                )

                // Embedding engine chooser. Lets the user force which backend "Embed All" and search
                // use, so a "0 embedded" result is explainable: On-device requires the EmbeddingGemma
                // model downloaded below; xAI has no public embeddings endpoint yet (usually returns 0).
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Embedding engine", style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        val options = listOf(
                            com.example.data.embedding.EmbeddingBackend.AUTO to "Auto",
                            com.example.data.embedding.EmbeddingBackend.ON_DEVICE to "On-device",
                            com.example.data.embedding.EmbeddingBackend.XAI to "xAI"
                        )
                        options.forEach { (backend, label) ->
                            val selected = embeddingBackend == backend
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .background(
                                        if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.18f)
                                        else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f),
                                        RoundedCornerShape(12.dp)
                                    )
                                    .pressBounce {
                                        embeddingBackend = backend
                                        com.example.data.embedding.EmbeddingPreference.set(context, backend)
                                    }
                                    .padding(vertical = 10.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Text(
                                    label,
                                    style = MaterialTheme.typography.labelMedium.copy(
                                        fontWeight = if (selected) FontWeight.ExtraBold else FontWeight.Medium
                                    ),
                                    color = if (selected) MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                                )
                            }
                        }
                    }
                    Text(
                        when (embeddingBackend) {
                            com.example.data.embedding.EmbeddingBackend.AUTO -> "On-device when the model is downloaded, otherwise xAI cloud."
                            com.example.data.embedding.EmbeddingBackend.ON_DEVICE -> "Private, on-device only. Requires the EmbeddingGemma model (download below)."
                            com.example.data.embedding.EmbeddingBackend.XAI -> "xAI cloud. Note: xAI has no public embeddings endpoint yet, so this often returns nothing."
                        },
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                    )
                }

                androidx.compose.material3.HorizontalDivider(color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f))

                // Embed All
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Embed All Bookmarks", style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold))
                        Text(
                            when (embeddingBackend) {
                                com.example.data.embedding.EmbeddingBackend.AUTO ->
                                    "Generate semantic vectors (on-device when model ready, else xAI cloud)."
                                com.example.data.embedding.EmbeddingBackend.ON_DEVICE ->
                                    "Generate semantic vectors on-device only (requires downloaded model)."
                                com.example.data.embedding.EmbeddingBackend.XAI ->
                                    "Generate semantic vectors via xAI cloud."
                            },
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                        )
                    }
                    Box(
                        modifier = Modifier
                            .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f), RoundedCornerShape(12.dp))
                            .pressBounce {
                                viewModel.embedAllBookmarks()
                                CurioNotifier.notify(context, "Generating embeddings…")
                            }
                            .padding(horizontal = 14.dp, vertical = 8.dp)
                    ) {
                        Text("EMBED ALL", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.primary))
                    }
                }

                androidx.compose.material3.HorizontalDivider(color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f))

                // Resolve New Sources
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Resolve New Sources", style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold))
                        Text("Fetch arXiv/GitHub/HF metadata for unresolved bookmarks (up to 10)", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    }
                    Box(
                        modifier = Modifier
                            .background(MaterialTheme.colorScheme.secondary.copy(alpha = 0.15f), RoundedCornerShape(12.dp))
                            .pressBounce {
                                viewModel.resolveNewSources()
                                CurioNotifier.notify(context, "Resolving sources…")
                            }
                            .padding(horizontal = 14.dp, vertical = 8.dp)
                    ) {
                        Text("RESOLVE", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.secondary))
                    }
                }

                androidx.compose.material3.HorizontalDivider(color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f))

                // Deduplicate Sources
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Deduplicate Sources", style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold))
                        Text("Merge bookmarks pointing to the same paper/repo into one entry", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    }
                    Box(
                        modifier = Modifier
                            .background(MaterialTheme.colorScheme.error.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
                            .pressBounce {
                                viewModel.deduplicateBySource()
                                CurioNotifier.notify(context, "Deduplicating…")
                            }
                            .padding(horizontal = 14.dp, vertical = 8.dp)
                    ) {
                        Text("DEDUP", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.error))
                    }
                }

                // Live status line for the three actions above.
                when (val s = researchStatus) {
                    is SyncUiState.Loading -> s.message?.let { msg ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            androidx.compose.material3.CircularProgressIndicator(
                                modifier = Modifier.size(16.dp), strokeWidth = 2.dp
                            )
                            Text(msg, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.8f))
                        }
                    }
                    is SyncUiState.Success -> Text(
                        "✓ ${s.message}",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary
                    )
                    is SyncUiState.Error -> Text(
                        s.error,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.error
                    )
                    else -> {}
                }
            }
        }

        // On-Device Embedding (EmbeddingGemma) Card
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .onGloballyPositioned { sectionOffsets["model"] = it.positionInParent().y.roundToInt() }
                .glassSurface(tier = resolvedTier)
                .padding(16.dp)
        ) {
            val context = LocalContext.current
            val modelState by viewModel.embeddingModelState.collectAsStateWithLifecycle()
            // Transient HF token entry for the first (gated) download. Blank → reuse the token
            // already saved in TokenStore, so returning users never have to re-enter it.
            var embedHfToken by remember { mutableStateOf("") }
            var indexWhileCharging by remember {
                mutableStateOf(com.example.background.EmbeddingIndexScheduler.isEnabled(context))
            }

            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Default.Psychology, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
                    Text(
                        text = "On-Device Embedding",
                        style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)
                    )
                }
                Text(
                    text = "Private semantic indexing with EmbeddingGemma — vectors are computed entirely on your device, no cloud. ${com.example.data.embedding.EmbeddingModelManager.APPROX_SIZE_LABEL} download.",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                )

                // EmbeddingGemma is Gemma-license-gated on Hugging Face, so the first download needs
                // a free HF token. Surface the link + guidance + an (optional) token field here so the
                // download is self-sufficient from Settings — no bare 401, no bouncing to the feed
                // sheet. A blank field reuses the token already saved in TokenStore.
                if (modelState !is com.example.data.embedding.EmbeddingModelManager.State.Ready) {
                    val hfUriHandler = LocalUriHandler.current
                    val hfLinkColor = MaterialTheme.colorScheme.primary
                    val hfText = buildAnnotatedString {
                        val base = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                        withStyle(SpanStyle(color = base)) { append("First download needs a free Hugging Face token — get one at ") }
                        pushStringAnnotation("URL", "https://huggingface.co/settings/tokens")
                        withStyle(SpanStyle(color = hfLinkColor, textDecoration = TextDecoration.Underline)) {
                            append("huggingface.co/settings/tokens")
                        }
                        pop()
                        withStyle(SpanStyle(color = base)) { append(", then accept the Gemma license on the model page. Stored encrypted on this device.") }
                    }
                    ClickableText(
                        text = hfText,
                        style = MaterialTheme.typography.labelSmall,
                        onClick = { offset ->
                            hfText.getStringAnnotations("URL", offset, offset)
                                .firstOrNull()?.let { hfUriHandler.openUri(it.item) }
                        }
                    )
                    androidx.compose.material3.OutlinedTextField(
                        value = embedHfToken,
                        onValueChange = { embedHfToken = it },
                        label = { Text("Hugging Face token (optional if already saved)") },
                        singleLine = true,
                        visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation(),
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                            keyboardType = androidx.compose.ui.text.input.KeyboardType.Password
                        ),
                        modifier = Modifier.fillMaxWidth().testTag("embed_hf_token_input")
                    )
                }

                // Model status + download/delete controls (state-driven)
                when (val s = modelState) {
                    is com.example.data.embedding.EmbeddingModelManager.State.Absent -> {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text("Model not downloaded", style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold))
                            Box(
                                modifier = Modifier
                                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f), RoundedCornerShape(12.dp))
                                    .pressBounce { viewModel.downloadEmbeddingModel(embedHfToken) }
                                    .padding(horizontal = 14.dp, vertical = 8.dp)
                                    .testTag("download_model_button")
                            ) {
                                Text("DOWNLOAD", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.primary))
                            }
                        }
                    }
                    is com.example.data.embedding.EmbeddingModelManager.State.Downloading -> {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(s.label, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary))
                            if (s.fraction > 0f) {
                                LinearProgressIndicator(progress = { s.fraction }, modifier = Modifier.fillMaxWidth())
                            } else {
                                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                            }
                        }
                    }
                    is com.example.data.embedding.EmbeddingModelManager.State.Ready -> {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Icon(Icons.Default.Check, contentDescription = null, tint = Color(0xFF4CAF50), modifier = Modifier.size(16.dp))
                                Text("Model ready · on-device", style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold, color = Color(0xFF4CAF50)))
                            }
                            Box(
                                modifier = Modifier
                                    .background(MaterialTheme.colorScheme.error.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
                                    .pressBounce { showModelDeleteConfirm = true }
                                    .padding(horizontal = 14.dp, vertical = 8.dp)
                            ) {
                                Text("DELETE", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.error))
                            }
                        }
                        Text(
                            "Uses the seq256 on-device model (256-token window). If embedding failed before updating, tap Clear embeddings below then Embed All.",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f)
                        )
                        // Build the index immediately (foreground, on-device) — handy right after download.
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
                                .pressBounce {
                                    com.example.background.EmbeddingIndexScheduler.runNow(context)
                                    CurioNotifier.notify(context, "Building on-device index…")
                                }
                                .padding(horizontal = 14.dp, vertical = 10.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text("BUILD INDEX NOW", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.primary))
                        }
                    }
                    is com.example.data.embedding.EmbeddingModelManager.State.Failed -> {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(s.message, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.error)
                            Box(
                                modifier = Modifier
                                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f), RoundedCornerShape(12.dp))
                                    .pressBounce { viewModel.downloadEmbeddingModel(embedHfToken) }
                                    .padding(horizontal = 14.dp, vertical = 8.dp)
                            ) {
                                Text("RETRY", style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.primary))
                            }
                        }
                    }
                }

                androidx.compose.material3.HorizontalDivider(color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f))

                // Index-while-charging toggle
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Index while charging", style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold))
                        Text("Backfill embeddings on-device only when plugged in & battery isn't low", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    }
                    Switch(
                        checked = indexWhileCharging,
                        onCheckedChange = {
                            indexWhileCharging = it
                            com.example.background.EmbeddingIndexScheduler.setEnabled(context, it)
                        },
                        modifier = Modifier.testTag("index_while_charging_switch")
                    )
                }
            }
        }

        // Liquid-Glass Render Engine
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .glassSurface(tier = resolvedTier)
                .padding(16.dp)
        ) {
            Column {
                Text(
                    text = "Liquid-Glass Render Engine",
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold)
                )
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = "Currently resolved: ${resolvedTier.name.uppercase()}",
                    style = MaterialTheme.typography.labelLarge.copy(
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.Bold
                    )
                )
                Spacer(modifier = Modifier.height(12.dp))

                listOf(
                    null to "Auto (Auto-detect features & RAM)",
                    GlassTier.Full to "Full (RenderEffect Blur + Sheen)",
                    GlassTier.Blur to "Blur (Frosted Alpha overlay)",
                    GlassTier.Solid to "Solid (Translucent fill - Low RAM / Battery safe)"
                ).forEach { (tierOption, label) ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .pressBounce { viewModel.setGlassTierOverride(tierOption) }
                            .padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        RadioButton(
                            selected = glassTierOverride == tierOption,
                            onClick = { viewModel.setGlassTierOverride(tierOption) }
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = label,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface
                        )
                    }
                }
            }
        }
    }
}
