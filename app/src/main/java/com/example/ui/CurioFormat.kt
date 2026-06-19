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

/** Compact relative timestamp, X-style ("now", "5m", "3h", "2d", then date). */
internal fun relativeTime(epochMs: Long): String {
    val diff = System.currentTimeMillis() - epochMs
    if (diff < 0) return "now"
    val mins = diff / 60_000
    val hrs = diff / 3_600_000
    val days = diff / 86_400_000
    return when {
        mins < 1 -> "now"
        mins < 60 -> "${mins}m"
        hrs < 24 -> "${hrs}h"
        days < 7 -> "${days}d"
        else -> try {
            SimpleDateFormat("MMM d", Locale.getDefault()).format(java.util.Date(epochMs))
        } catch (e: Exception) { "${days}d" }
    }
}

/** Approximate reading time from word count (~200 wpm). Null for very short posts. */
internal fun readingTime(text: String): String? {
    val words = text.trim().split(Regex("\\s+")).count { it.isNotBlank() }
    if (words < 40) return null
    val mins = Math.max(1, Math.round(words / 200f))
    return "${mins} min read"
}

/** Display name for the post — the real tweet author when known, else the source. */
internal fun displayAuthor(b: Bookmark): String =
    b.authorName?.trim()?.takeIf { it.isNotEmpty() } ?: sourceDisplayName(b)

/** The single-letter avatar initial for a tweet author, or null for non-tweet sources. */
internal fun authorInitial(b: Bookmark): Char? {
    if (b.sourceType == SourceType.ARXIV || b.sourceType == SourceType.GITHUB || b.sourceType == SourceType.HUGGING_FACE) return null
    return b.authorName?.trim()?.firstOrNull { it.isLetterOrDigit() }?.uppercaseChar()
}

/** A human "author/handle" label for the post, derived from its source. */
internal fun sourceDisplayName(b: Bookmark): String = when (b.sourceType) {
    SourceType.ARXIV -> "arXiv"
    SourceType.GITHUB -> "GitHub"
    SourceType.HUGGING_FACE -> "Hugging Face"
    else -> {
        val host = b.url?.let {
            runCatching { java.net.URI(it).host?.removePrefix("www.") }.getOrNull()
        }
        host ?: "Curio"
    }
}

/** Strip a trailing URL so the snippet reads cleanly. */
internal fun cleanSnippet(text: String): String =
    text.replace("https?://\\S+".toRegex(), "").trim().ifBlank { text.trim() }

// Convert Epoch Milliseconds to human-readable date format
internal fun formatEpoch(epochMs: Long): String {
    return try {
        val sdf = SimpleDateFormat("MMM dd, yyyy - HH:mm", Locale.getDefault())
        sdf.format(java.util.Date(epochMs))
    } catch (e: Exception) {
        "Just now"
    }
}

// Category palette mapping
internal fun getCategoryColor(category: String): Color {
    val clean = category.trim().lowercase()
    return when (clean) {
        "work" -> Color(0xFF1E88E5) // Blue
        "personal" -> Color(0xFF43A047) // Green
        "reading list", "reading" -> Color(0xFF8E24AA) // Purple
        "development" -> Color(0xFF4CAF50)
        "design" -> Color(0xFF00BCD4)
        "marketing" -> Color(0xFF9C27B0)
        "crypto" -> Color(0xFFFF9800)
        "business" -> Color(0xFF3F51B5)
        "life" -> Color(0xFFE91E63)
        "tech" -> Color(0xFF009688)
        "education" -> Color(0xFFFFC107)
        "finance" -> Color(0xFF3F51B5)
        "health" -> Color(0xFF00E676)
        else -> {
            val hash = clean.hashCode()
            val colors = listOf(
                Color(0xFFE040FB), // Magenta
                Color(0xFFFF5722), // Deep Orange
                Color(0xFF9C27B0), // Purple
                Color(0xFF673AB7), // Deep Purple
                Color(0xFF3F51B5), // Indigo
                Color(0xFF2196F3), // Blue
                Color(0xFF03A9F4), // Light Blue
                Color(0xFF00BCD4), // Cyan
                Color(0xFF009688), // Teal
                Color(0xFF4CAF50), // Green
                Color(0xFFCDDC39), // Lime
                Color(0xFFFFC107), // Amber
                Color(0xFFFF9800), // Orange
                Color(0xFFE91E63)  // Pink
            )
            val index = Math.abs(hash) % colors.size
            colors[index]
        }
    }
}

internal fun copyToClipboard(context: android.content.Context, text: String, label: String = "Curio") {
    try {
        val clipboard = context.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
        val clip = android.content.ClipData.newPlainText(label, text)
        clipboard.setPrimaryClip(clip)
        android.widget.Toast.makeText(context, "Copied details to clipboard!", android.widget.Toast.LENGTH_SHORT).show()
    } catch (e: Exception) {
        android.widget.Toast.makeText(context, "Failed to copy context", android.widget.Toast.LENGTH_SHORT).show()
    }
}

/**
 * The canonical X/Twitter permalink for a bookmark that originated as a tweet.
 * Synced tweets use the numeric tweet id as their bookmark id; manual and
 * source-resolved entries don't, so those return null (no tweet to view).
 */
internal fun tweetUrl(bookmark: Bookmark): String? {
    val id = bookmark.id
    if (id.isBlank() || !id.all { it.isDigit() }) return null
    val handle = bookmark.authorUsername?.trim()?.removePrefix("@")?.takeIf { it.isNotEmpty() } ?: "i/web"
    return "https://x.com/$handle/status/$id"
}

/** Opens a URL in the device browser, normalising a bare host to https. */
internal fun openUrl(context: android.content.Context, rawUrl: String?) {
    val url = rawUrl?.trim()?.takeIf { it.isNotEmpty() } ?: run {
        android.widget.Toast.makeText(context, "No link on this bookmark", android.widget.Toast.LENGTH_SHORT).show()
        return
    }
    val normalized = if (url.startsWith("http://") || url.startsWith("https://")) url else "https://$url"
    try {
        val intent = android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(normalized))
            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    } catch (e: Exception) {
        android.widget.Toast.makeText(context, "Couldn't open link", android.widget.Toast.LENGTH_SHORT).show()
    }
}

internal fun shareBookmark(context: android.content.Context, text: String) {
    try {
        val intent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
            this.type = "text/plain"
            this.putExtra(android.content.Intent.EXTRA_TEXT, text)
        }
        context.startActivity(android.content.Intent.createChooser(intent, "Share Curio Metadata"))
    } catch (e: Exception) {
        android.widget.Toast.makeText(context, "Failed to share context", android.widget.Toast.LENGTH_SHORT).show()
    }
}

internal fun exportBackupJson(bookmarks: List<Bookmark>): String {
    val s = java.lang.StringBuilder()
    s.append("[\n")
    bookmarks.forEachIndexed { i, b ->
        val cleanText = b.text.replace("\"", "\\\"").replace("\n", " ")
        val cleanOcr = (b.ocrText ?: "").replace("\"", "\\\"").replace("\n", " ")
        val cleanSummary = (b.summary ?: "").replace("\"", "\\\"").replace("\n", " ")
        val cleanCategory = b.category ?: ""
        val tagsJoined = b.tags.joinToString(",") { "\"$it\"" }

        s.append("  {\n")
        s.append("    \"id\": \"${b.id}\",\n")
        s.append("    \"text\": \"$cleanText\",\n")
        s.append("    \"createdAt\": ${b.createdAt},\n")
        s.append("    \"ocrText\": \"$cleanOcr\",\n")
        s.append("    \"summary\": \"$cleanSummary\",\n")
        s.append("    \"category\": \"$cleanCategory\",\n")
        s.append("    \"tags\": [$tagsJoined]\n")
        s.append("  }")
        if (i < bookmarks.size - 1) s.append(",")
        s.append("\n")
    }
    s.append("]")
    return s.toString()
}

internal fun exportBackupCsv(bookmarks: List<Bookmark>): String {
    val s = java.lang.StringBuilder()
    s.append("id,text,createdAt,ocrText,summary,category,tags\n")
    bookmarks.forEach { b ->
        val cleanId = b.id.replace("\"", "\"\"")
        val cleanText = b.text.replace("\"", "\"\"").replace("\n", " ")
        val cleanOcr = (b.ocrText ?: "").replace("\"", "\"\"").replace("\n", " ")
        val cleanSummary = (b.summary ?: "").replace("\"", "\"\"").replace("\n", " ")
        val cleanCategory = (b.category ?: "Uncategorized").replace("\"", "\"\"")
        val tagsJoined = b.tags.joinToString(";") { it.replace("\"", "\"\"") }

        s.append("\"$cleanId\",\"$cleanText\",${b.createdAt},\"$cleanOcr\",\"$cleanSummary\",\"$cleanCategory\",\"$tagsJoined\"\n")
    }
    return s.toString()
}
