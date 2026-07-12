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
import androidx.compose.ui.window.DialogProperties
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.Dp
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import kotlinx.coroutines.delay
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

/**
 * Within a [SlideUpCard], dismisses the card with its slide-down animation (rather than
 * tearing it down instantly). Read it inside the card body and use it for Cancel/confirm
 * buttons so every dismissal animates, e.g. `val dismiss = LocalSlideUpDismiss.current`.
 * Defaults to a no-op outside a card.
 */
val LocalSlideUpDismiss = compositionLocalOf<() -> Unit> { {} }

/**
 * A bottom-anchored card that slides up from the bottom of the screen — the app's
 * replacement for centered modal [Dialog]s. Renders inside a full-bleed [Dialog] so it
 * still owns the scrim and back handling, but the content animates up from the bottom edge
 * with a grab handle on top. Tapping the scrim (or back) plays the slide-out before
 * dismissing.
 *
 * Callers supply their content as a [ColumnScope] body — the card provides the surface,
 * handle, scroll, and insets, so callers should NOT add their own scroll/surface wrapper.
 * In-card buttons can animate their dismissal via [LocalSlideUpDismiss].
 */
@Composable
fun SlideUpCard(
    onDismissRequest: () -> Unit,
    tier: GlassTier,
    modifier: Modifier = Modifier,
    borderColor: Color = MaterialTheme.colorScheme.primary.copy(alpha = 0.25f),
    tint: Color = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f),
    contentPadding: Dp = 24.dp,
    verticalArrangement: Arrangement.Vertical = Arrangement.spacedBy(16.dp),
    horizontalAlignment: Alignment.Horizontal = Alignment.Start,
    content: @Composable ColumnScope.() -> Unit
) {
    var visible by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { visible = true }

    // Play the slide-out, then actually tear down the dialog.
    fun startDismiss() {
        scope.launch {
            visible = false
            delay(220)
            onDismissRequest()
        }
    }

    val maxHeight = (LocalConfiguration.current.screenHeightDp * 0.92f).dp

    Dialog(
        onDismissRequest = { startDismiss() },
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                // Tapping the dimmed area outside the card dismisses it.
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null
                ) { startDismiss() },
            contentAlignment = Alignment.BottomCenter
        ) {
            AnimatedVisibility(
                visible = visible,
                enter = slideInVertically(
                    initialOffsetY = { it },
                    animationSpec = tween(durationMillis = 320)
                ) + fadeIn(animationSpec = tween(durationMillis = 220)),
                exit = slideOutVertically(
                    targetOffsetY = { it },
                    animationSpec = tween(durationMillis = 220)
                ) + fadeOut(animationSpec = tween(durationMillis = 180))
            ) {
                CompositionLocalProvider(LocalSlideUpDismiss provides { startDismiss() }) {
                Column(
                    modifier = modifier
                        .fillMaxWidth()
                        // Swallow taps on the card so they don't reach the scrim.
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null
                        ) {}
                        .glassSurface(
                            tier = tier,
                            shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
                            tint = tint,
                            borderColor = borderColor
                        )
                        // Lift the whole card above the keyboard / nav bar.
                        .imePadding()
                        .navigationBarsPadding()
                        .heightIn(max = maxHeight)
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = contentPadding)
                        .padding(top = 10.dp, bottom = contentPadding),
                    verticalArrangement = verticalArrangement,
                    horizontalAlignment = horizontalAlignment
                ) {
                    // Grab handle.
                    Box(
                        modifier = Modifier
                            .align(Alignment.CenterHorizontally)
                            .size(width = 40.dp, height = 4.dp)
                            .background(
                                MaterialTheme.colorScheme.onSurface.copy(alpha = 0.22f),
                                RoundedCornerShape(2.dp)
                            )
                    )
                    content()
                }
                }
            }
        }
    }
}

@Composable
fun ManualAddBookmarkDialog(
    onDismissRequest: () -> Unit,
    onAddBookmark: (String) -> Unit,
    tier: GlassTier,
    viewModel: BookmarkViewModel
) {
    var textInput by remember { mutableStateOf("") }
    var errorText by remember { mutableStateOf("") }
    var previewSummary by remember { mutableStateOf<String?>(null) }
    var isPreviewLoading by remember { mutableStateOf(false) }

    SlideUpCard(
        onDismissRequest = onDismissRequest,
        tier = tier,
        verticalArrangement = Arrangement.spacedBy(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
                val dismiss = LocalSlideUpDismiss.current
                Text(
                    text = "ADD SNIPPET OR URL",
                    style = MaterialTheme.typography.titleMedium.copy(
                        fontWeight = FontWeight.ExtraBold,
                        color = MaterialTheme.colorScheme.primary,
                        letterSpacing = 1.sp
                    )
                )

                Text(
                    text = "Enter a URL link or a plain text snippet. You can instantly preview the summary before committing the bookmark database save.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                    textAlign = TextAlign.Center
                )

                androidx.compose.material3.OutlinedTextField(
                    value = textInput,
                    onValueChange = {
                        textInput = it
                        if (it.isNotBlank()) errorText = ""
                    },
                    placeholder = {
                        Text(
                            text = "https://example.com/article\n\nOr type/paste your snippet to analyze here...",
                            style = MaterialTheme.typography.bodyMedium.copy(color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f))
                        )
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(140.dp)
                        .testTag("manual_bookmark_input"),
                    textStyle = MaterialTheme.typography.bodyMedium,
                    colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = MaterialTheme.colorScheme.primary,
                        unfocusedBorderColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.15f)
                    ),
                    shape = RoundedCornerShape(12.dp)
                )

                if (errorText.isNotEmpty()) {
                    Text(
                        text = errorText,
                        style = MaterialTheme.typography.labelSmall.copy(color = MaterialTheme.colorScheme.error)
                    )
                }

                // Instant Summarization Preview widget
                if (isPreviewLoading) {
                    androidx.compose.material3.CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.primary
                    )
                    Text("Architecting cognitive preview...", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                }

                previewSummary?.let { summary ->
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .glassSurface(tier = tier, shape = RoundedCornerShape(12.dp), tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.05f))
                            .padding(12.dp)
                    ) {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(
                                "INSTANT AI PREVIEW",
                                style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.primary)
                            )
                            Text(
                                text = summary,
                                style = MaterialTheme.typography.bodySmall.copy(lineHeight = 16.sp),
                                color = MaterialTheme.colorScheme.onSurface
                            )
                        }
                    }
                }

                // Preview Trigger Row Button
                if (textInput.isNotBlank() && !isPreviewLoading) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(44.dp)
                            .background(MaterialTheme.colorScheme.secondary.copy(alpha = 0.15f), RoundedCornerShape(14.dp))
                            .pressBounce {
                                isPreviewLoading = true
                                viewModel.getInstantSummaryPreview(textInput) { preview ->
                                    isPreviewLoading = false
                                    previewSummary = preview
                                }
                            }
                            .testTag("instant_preview_button"),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = "PREVIEW COGNITIVE SUMMARY",
                            style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.secondary)
                        )
                    }
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(48.dp)
                            .background(
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f),
                                shape = RoundedCornerShape(14.dp)
                            )
                            .pressBounce { dismiss() },
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = "CANCEL",
                            style = MaterialTheme.typography.labelMedium.copy(
                                fontWeight = FontWeight.Black,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                            )
                        )
                    }

                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(48.dp)
                            .background(
                                color = MaterialTheme.colorScheme.primary,
                                shape = RoundedCornerShape(14.dp)
                            )
                            .pressBounce {
                                if (textInput.isBlank()) {
                                    errorText = "Field cannot be empty"
                                } else {
                                    onAddBookmark(textInput)
                                    dismiss()
                                }
                            }
                            .testTag("manual_bookmark_submit"),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = "PROCESS & ADD",
                            style = MaterialTheme.typography.labelMedium.copy(
                                fontWeight = FontWeight.Black,
                                color = MaterialTheme.colorScheme.onPrimary
                            )
                        )
                    }
                }
    }
}

/**
 * Editor for a bookmark's personal note/annotation. Pre-fills [existingNote]; an empty save clears
 * the note (handled downstream). Local-only — notes never leave the device.
 */
@Composable
fun NotesEditorDialog(
    existingNote: String?,
    tier: GlassTier,
    onDismiss: () -> Unit,
    onSave: (String?) -> Unit
) {
    var noteInput by remember { mutableStateOf(existingNote.orEmpty()) }

    SlideUpCard(
        onDismissRequest = onDismiss,
        tier = tier,
        borderColor = MaterialTheme.colorScheme.tertiary.copy(alpha = 0.25f),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
                val dismiss = LocalSlideUpDismiss.current
                Text(
                    text = if (existingNote.isNullOrBlank()) "ADD A NOTE" else "EDIT NOTE",
                    style = MaterialTheme.typography.titleMedium.copy(
                        fontWeight = FontWeight.ExtraBold,
                        color = MaterialTheme.colorScheme.tertiary,
                        letterSpacing = 1.sp
                    )
                )

                Text(
                    text = "Your private annotation for this entry — thoughts, why you saved it, follow-ups. Stays on this device.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                    textAlign = TextAlign.Center
                )

                androidx.compose.material3.OutlinedTextField(
                    value = noteInput,
                    onValueChange = { noteInput = it },
                    placeholder = {
                        Text(
                            text = "Type your note here…",
                            style = MaterialTheme.typography.bodyMedium.copy(color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f))
                        )
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(160.dp)
                        .testTag("note_editor_input"),
                    textStyle = MaterialTheme.typography.bodyMedium,
                    colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = MaterialTheme.colorScheme.tertiary,
                        unfocusedBorderColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.15f)
                    ),
                    shape = RoundedCornerShape(12.dp)
                )

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(48.dp)
                            .background(
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.05f),
                                shape = RoundedCornerShape(14.dp)
                            )
                            .pressBounce { dismiss() },
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = "CANCEL",
                            style = MaterialTheme.typography.labelMedium.copy(
                                fontWeight = FontWeight.Black,
                                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                            )
                        )
                    }

                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(48.dp)
                            .background(
                                color = MaterialTheme.colorScheme.tertiary,
                                shape = RoundedCornerShape(14.dp)
                            )
                            .pressBounce { onSave(noteInput.trim().ifEmpty { null }) }
                            .testTag("note_editor_save"),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = if (noteInput.isBlank() && !existingNote.isNullOrBlank()) "CLEAR" else "SAVE",
                            style = MaterialTheme.typography.labelMedium.copy(
                                fontWeight = FontWeight.Black,
                                color = MaterialTheme.colorScheme.onTertiary
                            )
                        )
                    }
                }
    }
}

@Composable
fun CurioEmptyState(tier: GlassTier, onActionClick: () -> Unit = {}) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 40.dp, horizontal = 8.dp),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp),
            modifier = Modifier
                .fillMaxWidth()
                .glassSurface(
                    tier = tier,
                    shape = RoundedCornerShape(32.dp),
                    tint = MaterialTheme.colorScheme.surface.copy(alpha = 0.4f),
                    borderColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
                )
                .padding(32.dp)
        ) {
            // Glowing orbital sphere representing an offline index
            Box(
                modifier = Modifier
                    .size(100.dp)
                    .background(
                        brush = Brush.radialGradient(
                            colors = listOf(
                                MaterialTheme.colorScheme.primary.copy(alpha = 0.25f),
                                MaterialTheme.colorScheme.secondary.copy(alpha = 0.05f),
                                Color.Transparent
                            )
                        ),
                        shape = RoundedCornerShape(50.dp)
                    ),
                contentAlignment = Alignment.Center
            ) {
                // Frosted central shield orb
                Box(
                    modifier = Modifier
                        .size(64.dp)
                        .glassSurface(
                            tier = tier,
                            shape = RoundedCornerShape(20.dp),
                            tint = MaterialTheme.colorScheme.surface.copy(alpha = 0.6f),
                            borderColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.3f)
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Default.Bookmarks,
                        contentDescription = "No bookmarks",
                        modifier = Modifier.size(28.dp),
                        tint = MaterialTheme.colorScheme.primary
                    )
                }
            }

            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = "YOUR CURIO ARCHIVE IS EMPTY",
                    style = MaterialTheme.typography.titleMedium.copy(
                        fontWeight = FontWeight.ExtraBold,
                        color = MaterialTheme.colorScheme.onSurface,
                        letterSpacing = 1.sp
                    )
                )
                Text(
                    text = "Sync down recent bookmarks from your X timeline, or manually input text snippets and web links to build your curated, searchable database.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                    textAlign = TextAlign.Center,
                    lineHeight = 18.sp,
                    modifier = Modifier.padding(horizontal = 12.dp)
                )
            }

            Box(
                modifier = Modifier
                    .background(
                        color = MaterialTheme.colorScheme.primary,
                        shape = RoundedCornerShape(16.dp)
                    )
                    .pressBounce { onActionClick() }
                    .padding(horizontal = 24.dp, vertical = 12.dp)
                    .testTag("empty_state_action"),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "INITIALIZE RETRIEVAL SYNC",
                    style = MaterialTheme.typography.labelSmall.copy(
                        fontWeight = FontWeight.Black,
                        color = MaterialTheme.colorScheme.onPrimary,
                        letterSpacing = 0.5.sp
                    )
                )
            }
        }
    }
}
