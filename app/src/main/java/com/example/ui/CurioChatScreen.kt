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
import androidx.compose.material.icons.filled.ErrorOutline
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
import com.example.ui.theme.minTouchTarget
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
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
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Hub
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.filled.Article
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.AlternateEmail
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.outlined.ThumbDown
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.AnnotatedString
import java.text.SimpleDateFormat
import java.util.Locale

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun CurioChatScreen(
    viewModel: BookmarkViewModel,
    tier: GlassTier,
    onNavigateToBookmarks: () -> Unit = {},
    onNavigateToSettings: () -> Unit = {}
) {
    val messages by viewModel.chatMessages.collectAsStateWithLifecycle()
    val isLoading by viewModel.isChatLoading.collectAsStateWithLifecycle()
    val activeSources by viewModel.chatSources.collectAsStateWithLifecycle()
    val stats by viewModel.stats.collectAsStateWithLifecycle()
    val xaiKeyConfigured by viewModel.xaiKeyConfigured.collectAsStateWithLifecycle()
    var textInput by remember { mutableStateOf("") }
    var showClearConfirm by remember { mutableStateOf(false) }
    val lazyListState = rememberLazyListState()
    val clipboard = LocalClipboardManager.current
    val context = LocalContext.current
    val haptics = androidx.compose.ui.platform.LocalHapticFeedback.current

    LaunchedEffect(messages.size) {
        val target = messages.size - 1 + (if (isLoading) 1 else 0)
        if (target >= 0) runCatching { lazyListState.animateScrollToItem(target) }
    }

    val suggestions = listOf(
        "Summarize my recent bookmarks",
        "What topics am I reading most?",
        "Find papers about attention",
        "Suggest a paper to read next"
    )

    // Clearing a whole research conversation is destructive and irreversible — confirm first.
    if (showClearConfirm) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { showClearConfirm = false },
            icon = { Icon(Icons.Default.DeleteSweep, contentDescription = null, tint = MaterialTheme.colorScheme.error) },
            title = { Text("Clear conversation?") },
            text = { Text("This removes every message in this chat. Your saved bookmarks aren't affected.") },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = {
                    showClearConfirm = false
                    viewModel.clearChat()
                }) { Text("Clear", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                androidx.compose.material3.TextButton(onClick = { showClearConfirm = false }) { Text("Cancel") }
            }
        )
    }

    Box(modifier = Modifier.fillMaxSize().imePadding().padding(horizontal = 16.dp)) {
        Column(modifier = Modifier.fillMaxSize().padding(bottom = 132.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Spacer(Modifier.height(4.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(
                    modifier = Modifier.size(34.dp).clip(CircleShape).background(curioAccentBrush(MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.tertiary)),
                    contentAlignment = Alignment.Center
                ) { Icon(Icons.Default.AutoAwesome, contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp)) }
                Column(modifier = Modifier.weight(1f)) {
                    Text("Curio AI", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black))
                    Text("Grounded in your saved research", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                AnimatedVisibility(visible = messages.isNotEmpty(), enter = fadeIn(), exit = fadeOut()) {
                    IconButton(
                        onClick = { showClearConfirm = true },
                        modifier = Modifier.testTag("chat_clear_button")
                    ) {
                        Icon(
                            Icons.Default.DeleteSweep,
                            contentDescription = "Clear conversation",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }

            if (messages.isEmpty()) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(
                        modifier = Modifier.size(76.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)),
                        contentAlignment = Alignment.Center
                    ) { Icon(Icons.Default.Psychology, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(38.dp)) }
                    Spacer(Modifier.height(16.dp))
                    when {
                        !xaiKeyConfigured -> {
                            Text("Connect your xAI key", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black), textAlign = TextAlign.Center)
                            Text("Add your API key in Settings to chat with Grok about your saved research.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 12.dp))
                            Spacer(Modifier.height(16.dp))
                            Box(
                                modifier = Modifier.glassSurface(tier = tier, shape = RoundedCornerShape(16.dp)).pressBounce(onClick = onNavigateToSettings).padding(horizontal = 20.dp, vertical = 12.dp)
                            ) {
                                Text("OPEN SETTINGS", style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Black), color = MaterialTheme.colorScheme.primary)
                            }
                        }
                        stats.totalCount == 0 -> {
                            Text("Your index is empty", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black), textAlign = TextAlign.Center)
                            Text("Sync bookmarks from X first, then ask Curio to summarize or explore them.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 12.dp))
                            Spacer(Modifier.height(16.dp))
                            Box(
                                modifier = Modifier.glassSurface(tier = tier, shape = RoundedCornerShape(16.dp)).pressBounce(onClick = onNavigateToBookmarks).padding(horizontal = 20.dp, vertical = 12.dp)
                            ) {
                                Text("GO TO BOOKMARKS", style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Black), color = MaterialTheme.colorScheme.primary)
                            }
                        }
                        else -> {
                            Text("Ask anything about your index", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black), textAlign = TextAlign.Center)
                            Text("I read across everything you've saved.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), textAlign = TextAlign.Center)
                            Spacer(Modifier.height(20.dp))
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth(), maxItemsInEachRow = 2) {
                                suggestions.forEach { s ->
                                    Box(
                                        modifier = Modifier
                                            .glassSurface(tier = tier, shape = RoundedCornerShape(16.dp))
                                            .pressBounce(enabled = !isLoading) { viewModel.sendChatMessage(s) }
                                            .padding(horizontal = 14.dp, vertical = 12.dp)
                                    ) {
                                        Text(s, style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold), color = MaterialTheme.colorScheme.onSurface)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                androidx.compose.foundation.lazy.LazyColumn(state = lazyListState, modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    items(messages, key = { it.id }) { msg ->
                        val isAi = msg.sender == com.example.ui.ChatSender.AI
                        val isError = msg.isError
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = if (isAi) Arrangement.Start else Arrangement.End, verticalAlignment = Alignment.Top) {
                            if (isAi) {
                                Box(
                                    modifier = Modifier
                                        .size(28.dp)
                                        .clip(CircleShape)
                                        .then(
                                            if (isError) Modifier.background(MaterialTheme.colorScheme.error.copy(alpha = 0.2f))
                                            else Modifier.background(curioAccentBrush(MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.tertiary))
                                        ),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        if (isError) Icons.Default.ErrorOutline else Icons.Default.AutoAwesome,
                                        contentDescription = null,
                                        tint = if (isError) MaterialTheme.colorScheme.error else Color.White,
                                        modifier = Modifier.size(15.dp)
                                    )
                                }
                                Spacer(Modifier.width(8.dp))
                            }
                            Column(
                                modifier = Modifier.widthIn(max = 300.dp),
                                horizontalAlignment = if (isAi) Alignment.Start else Alignment.End,
                                verticalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                ChatBubble(
                                    text = msg.text,
                                    isAi = isAi,
                                    isError = isError,
                                    tier = tier,
                                    modifier = Modifier.testTag("chat_msg_bubble_${msg.id}"),
                                    onLongPress = {
                                        haptics.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.LongPress)
                                        clipboard.setText(AnnotatedString(msg.text))
                                        CurioNotifier.notify(context, "Copied to clipboard")
                                    }
                                )
                                if (isError && msg.retryPrompt != null) {
                                    Box(
                                        modifier = Modifier
                                            .glassSurface(tier = tier, shape = RoundedCornerShape(12.dp), tint = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.2f))
                                            .pressBounce { viewModel.retryChatMessage(msg.id) }
                                            .padding(horizontal = 12.dp, vertical = 8.dp)
                                            .testTag("chat_retry_${msg.id}")
                                    ) {
                                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                            Icon(Icons.Default.Refresh, contentDescription = null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(14.dp))
                                            Text("Retry", style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black), color = MaterialTheme.colorScheme.error)
                                        }
                                    }
                                }
                                if (isAi && !isError && msg.semanticCacheHit) {
                                    Text(
                                        "Cached",
                                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.45f),
                                        modifier = Modifier.testTag("chat_cached_badge_${msg.id}")
                                    )
                                }
                                if (isAi && !isError && msg.showsSemanticFeedback) {
                                    SemanticFeedbackRow(
                                        messageId = msg.id,
                                        onFeedback = { accepted -> viewModel.submitSemanticFeedback(msg.id, accepted) }
                                    )
                                } else if (isAi && !isError && msg.semanticFeedbackAccepted != null) {
                                    Text(
                                        if (msg.semanticFeedbackAccepted) "Thanks for the feedback" else "Feedback noted",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.45f)
                                    )
                                }
                                if (isAi && !isError && msg.citations.isNotEmpty()) {
                                    CitationStrip(msg.citations, context)
                                }
                            }
                        }
                    }
                    if (isLoading) {
                        item {
                            val loadingLabel = when {
                                ChatSource.LIBRARY in activeSources && activeSources.size == 1 -> "Searching your library…"
                                activeSources.any { it != ChatSource.LIBRARY } -> "Searching live sources…"
                                else -> "Thinking…"
                            }
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Box(modifier = Modifier.size(28.dp).clip(CircleShape).background(curioAccentBrush(MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.tertiary)), contentAlignment = Alignment.Center) {
                                    Icon(Icons.Default.AutoAwesome, contentDescription = null, tint = Color.White, modifier = Modifier.size(15.dp))
                                }
                                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Box(modifier = Modifier.glassSurface(tier = tier, shape = RoundedCornerShape(18.dp)).padding(horizontal = 16.dp, vertical = 14.dp)) {
                                        TypingDots(MaterialTheme.colorScheme.primary)
                                    }
                                    Text(loadingLabel, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold), color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f))
                                }
                            }
                        }
                    }
                }
            }
        }

        // Source chips + liquid-glass composer — sits flush above the keyboard (no buffer)
        Column(
            modifier = Modifier.fillMaxWidth().align(Alignment.BottomCenter),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            SourceChipRow(
                activeSources = activeSources,
                onToggle = { viewModel.toggleChatSource(it) },
                tier = tier,
                enabled = !isLoading
            )
            Box(modifier = Modifier.fillMaxWidth().glassSurface(tier = tier, shape = RoundedCornerShape(24.dp)).padding(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    androidx.compose.material3.TextField(
                        value = textInput,
                        onValueChange = { textInput = it },
                        enabled = !isLoading,
                        placeholder = { Text("Ask Curio anything…", style = MaterialTheme.typography.bodyMedium.copy(color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f))) },
                        modifier = Modifier.weight(1f).testTag("chatbot_text_input"),
                        textStyle = MaterialTheme.typography.bodyMedium,
                        colors = androidx.compose.material3.TextFieldDefaults.colors(
                            focusedContainerColor = Color.Transparent,
                            unfocusedContainerColor = Color.Transparent,
                            disabledContainerColor = Color.Transparent,
                            focusedIndicatorColor = Color.Transparent,
                            unfocusedIndicatorColor = Color.Transparent
                        ),
                        singleLine = true
                    )
                    val sendEnabled = textInput.isNotBlank() && !isLoading
                    Box(
                        modifier = Modifier
                            .size(48.dp)
                            .clip(RoundedCornerShape(16.dp))
                            .background(if (textInput.isBlank()) MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f) else Color.Transparent)
                            .then(if (textInput.isNotBlank()) Modifier.background(curioAccentBrush(MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.tertiary), RoundedCornerShape(16.dp)) else Modifier)
                            // Tell TalkBack the button is unavailable when there's nothing to send / a reply is streaming.
                            .semantics { if (!sendEnabled) disabled() }
                            .pressBounce(enabled = sendEnabled) {
                                if (sendEnabled) { viewModel.sendChatMessage(textInput); textInput = "" }
                            }
                            .testTag("chatbot_send_button"),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Send message", tint = if (textInput.isBlank()) MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f) else Color.White, modifier = Modifier.size(20.dp))
                    }
                }
            }
        }
    }
}

/** A tappable chat bubble with markdown rendering and long-press-to-copy. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ChatBubble(
    text: String,
    isAi: Boolean,
    isError: Boolean = false,
    tier: GlassTier,
    modifier: Modifier = Modifier,
    onLongPress: () -> Unit
) {
    Box(
        modifier = modifier
            .glassSurface(
                tier = tier,
                shape = RoundedCornerShape(topStart = 18.dp, topEnd = 18.dp, bottomStart = if (isAi) 4.dp else 18.dp, bottomEnd = if (isAi) 18.dp else 4.dp),
                tint = when {
                    isError -> MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.35f)
                    isAi -> MaterialTheme.colorScheme.surface.copy(alpha = 0.55f)
                    else -> MaterialTheme.colorScheme.primary.copy(alpha = 0.2f)
                },
                borderColor = when {
                    isError -> MaterialTheme.colorScheme.error.copy(alpha = 0.35f)
                    isAi -> Color.Transparent
                    else -> MaterialTheme.colorScheme.primary.copy(alpha = 0.35f)
                }
            )
            .combinedClickable(onClick = {}, onLongClick = onLongPress)
            .padding(13.dp)
    ) {
        MarkdownText(
            markdown = text,
            style = MaterialTheme.typography.bodyMedium.copy(lineHeight = 21.sp),
            color = MaterialTheme.colorScheme.onSurface,
            accent = MaterialTheme.colorScheme.primary
        )
    }
}

/** Thumbs up/down for sidecar-served assistant replies. */
@Composable
private fun SemanticFeedbackRow(
    messageId: String,
    onFeedback: (Boolean) -> Unit
) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(
            onClick = { onFeedback(true) },
            modifier = Modifier
                .size(36.dp)
                .testTag("chat_feedback_up_$messageId")
        ) {
            Icon(
                Icons.Outlined.ThumbUp,
                contentDescription = "Helpful response",
                tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f),
                modifier = Modifier.size(16.dp)
            )
        }
        IconButton(
            onClick = { onFeedback(false) },
            modifier = Modifier
                .size(36.dp)
                .testTag("chat_feedback_down_$messageId")
        ) {
            Icon(
                Icons.Outlined.ThumbDown,
                contentDescription = "Unhelpful response",
                tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f),
                modifier = Modifier.size(16.dp)
            )
        }
    }
}

/** Tappable source citations rendered under a grounded AI reply. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CitationStrip(citations: List<String>, context: android.content.Context) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        citations.take(8).forEachIndexed { index, url ->
            val host = remember(url) {
                runCatching { Uri.parse(url).host?.removePrefix("www.") }.getOrNull() ?: "source"
            }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                modifier = Modifier
                    .heightIn(min = 44.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.10f))
                    .semantics(mergeDescendants = true) { contentDescription = "Open source ${index + 1}: $host" }
                    .pressBounce(pressedScale = 0.92f) { openUrl(context, url) }
                    .padding(horizontal = 10.dp, vertical = 8.dp)
            ) {
                Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(12.dp))
                Text(
                    "${index + 1}. $host",
                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

/** Horizontally scrollable grounding-source toggles shown above the composer. */
@Composable
private fun SourceChipRow(
    activeSources: Set<ChatSource>,
    onToggle: (ChatSource) -> Unit,
    tier: GlassTier,
    enabled: Boolean = true
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .alpha(if (enabled) 1f else 0.55f),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ChatSource.entries.forEach { source ->
            val selected = source in activeSources
            val icon = when (source) {
                ChatSource.LIBRARY -> Icons.Default.Bookmarks
                ChatSource.WEB -> Icons.Default.Public
                ChatSource.X -> Icons.Default.AlternateEmail
                ChatSource.NEWS -> Icons.AutoMirrored.Filled.Article
            }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier
                    .heightIn(min = 44.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .then(
                        if (selected) Modifier.background(MaterialTheme.colorScheme.primary.copy(alpha = 0.18f))
                        else Modifier.glassSurface(tier = tier, shape = RoundedCornerShape(14.dp))
                    )
                    .border(
                        width = 1.dp,
                        color = if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.5f) else Color.Transparent,
                        shape = RoundedCornerShape(14.dp)
                    )
                    // A grounding source is an on/off toggle — announce its state to TalkBack.
                    .semantics { role = Role.Switch; stateDescription = if (selected) "On" else "Off" }
                    .pressBounce(enabled = enabled) { if (enabled) onToggle(source) }
                    .padding(horizontal = 12.dp, vertical = 8.dp)
                    .testTag("chat_source_${source.name}")
            ) {
                Icon(
                    icon,
                    contentDescription = null,
                    tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                    modifier = Modifier.size(15.dp)
                )
                Text(
                    source.label,
                    style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold),
                    color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.75f)
                )
                if (selected) {
                    Icon(Icons.Default.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(13.dp))
                }
            }
        }
    }
}
