package com.example.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Lightweight markdown renderer for AI-generated copy (deep analysis, chat).
 * Supports a pragmatic subset: `# / ## / ### / ####` headings, `- / * / •` and numbered
 * bullets, `>` blockquotes, ```` ``` ```` fenced code blocks, blank-line spacing, and
 * inline `**bold**`, `*italic*`/`_italic_`, `~~strike~~`, `` `code` ``, `[label](url)`
 * links, and bare `https://` autolinks. Links are tappable and open in the browser.
 * No third-party dependency — the model output is small.
 */
@Composable
internal fun MarkdownText(
    markdown: String,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.bodyMedium,
    color: Color = MaterialTheme.colorScheme.onSurface,
    accent: Color = MaterialTheme.colorScheme.primary
) {
    val codeColor = MaterialTheme.colorScheme.tertiary
    val lines = markdown.trim().split("\n")
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        var i = 0
        while (i < lines.size) {
            val raw = lines[i]
            val line = raw.trim()
            when {
                // Fenced code block: gobble lines until the closing fence.
                line.startsWith("```") -> {
                    val sb = StringBuilder()
                    i++
                    while (i < lines.size && !lines[i].trim().startsWith("```")) {
                        sb.appendLine(lines[i])
                        i++
                    }
                    CodeBlock(sb.toString().trimEnd(), style, codeColor)
                }

                line.isBlank() -> Spacer(Modifier.height(3.dp))

                line.startsWith("#### ") -> Text(
                    parseInline(line.removePrefix("#### "), accent, codeColor),
                    style = style.copy(fontWeight = FontWeight.Black),
                    color = color
                )
                line.startsWith("### ") -> Text(
                    parseInline(line.removePrefix("### "), accent, codeColor),
                    style = style.copy(fontWeight = FontWeight.Black, fontSize = style.fontSize * 1.05f),
                    color = color
                )
                line.startsWith("## ") -> Text(
                    parseInline(line.removePrefix("## "), accent, codeColor),
                    style = style.copy(fontWeight = FontWeight.Black, fontSize = style.fontSize * 1.12f),
                    color = color
                )
                line.startsWith("# ") -> Text(
                    parseInline(line.removePrefix("# "), accent, codeColor),
                    style = style.copy(fontWeight = FontWeight.Black, fontSize = style.fontSize * 1.2f),
                    color = color
                )

                line.startsWith("> ") -> BlockQuote(parseInline(line.removePrefix("> ").trim(), accent, codeColor), style, color, accent)

                line.startsWith("- ") || line.startsWith("* ") || line.startsWith("• ") ->
                    BulletRow(parseInline(line.drop(2).trim(), accent, codeColor), style, color, accent)

                NUMBERED.matchEntire(line) != null -> {
                    val m = NUMBERED.matchEntire(line)!!
                    NumberRow(m.groupValues[1], parseInline(m.groupValues[2], accent, codeColor), style, color, accent)
                }

                else -> Text(parseInline(line, accent, codeColor), style = style, color = color)
            }
            i++
        }
    }
}

private val NUMBERED = Regex("^(\\d+)\\.\\s+(.*)")

@Composable
private fun BulletRow(content: AnnotatedString, style: TextStyle, color: Color, accent: Color) {
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(
            modifier = Modifier
                .padding(top = 7.dp)
                .size(5.dp)
                .background(accent, CircleShape)
        )
        Text(content, style = style, color = color)
    }
}

@Composable
private fun NumberRow(number: String, content: AnnotatedString, style: TextStyle, color: Color, accent: Color) {
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            "$number.",
            style = style.copy(fontWeight = FontWeight.Black),
            color = accent,
            modifier = Modifier.width(18.dp)
        )
        Text(content, style = style, color = color)
    }
}

@Composable
private fun BlockQuote(content: AnnotatedString, style: TextStyle, color: Color, accent: Color) {
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(
            modifier = Modifier
                .padding(vertical = 2.dp)
                .width(3.dp)
                .height(18.dp)
                .background(accent.copy(alpha = 0.6f), RoundedCornerShape(2.dp))
        )
        Text(content, style = style.copy(fontStyle = FontStyle.Italic), color = color.copy(alpha = 0.85f))
    }
}

@Composable
private fun CodeBlock(code: String, style: TextStyle, codeColor: Color) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f))
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 12.dp, vertical = 10.dp)
    ) {
        Text(
            code,
            style = style.copy(fontFamily = FontFamily.Monospace, fontSize = 13.sp),
            color = codeColor
        )
    }
}

/**
 * Parses inline markdown into an AnnotatedString: `**bold**`, `*italic*`/`_italic_`,
 * `~~strike~~`, `` `code` ``, `[label](url)` links, and bare `http(s)://` autolinks.
 */
private fun parseInline(text: String, accent: Color, codeColor: Color): AnnotatedString = buildAnnotatedString {
    val linkStyles = TextLinkStyles(
        style = SpanStyle(color = accent, textDecoration = TextDecoration.Underline)
    )
    var i = 0
    val n = text.length
    while (i < n) {
        when {
            text.startsWith("**", i) -> {
                val end = text.indexOf("**", i + 2)
                if (end != -1) {
                    withStyle(SpanStyle(fontWeight = FontWeight.Black)) { append(text.substring(i + 2, end)) }
                    i = end + 2
                } else { append(text[i]); i++ }
            }
            text.startsWith("~~", i) -> {
                val end = text.indexOf("~~", i + 2)
                if (end != -1) {
                    withStyle(SpanStyle(textDecoration = TextDecoration.LineThrough)) { append(text.substring(i + 2, end)) }
                    i = end + 2
                } else { append(text[i]); i++ }
            }
            text[i] == '`' -> {
                val end = text.indexOf('`', i + 1)
                if (end != -1) {
                    withStyle(SpanStyle(fontFamily = FontFamily.Monospace, color = codeColor, fontSize = 13.sp)) {
                        append(text.substring(i + 1, end))
                    }
                    i = end + 1
                } else { append(text[i]); i++ }
            }
            // [label](url)
            text[i] == '[' -> {
                val close = text.indexOf(']', i + 1)
                val open = if (close != -1) close + 1 else -1
                if (close != -1 && open < n && text[open] == '(') {
                    val urlEnd = text.indexOf(')', open + 1)
                    if (urlEnd != -1) {
                        val label = text.substring(i + 1, close)
                        val url = text.substring(open + 1, urlEnd).trim()
                        withLink(LinkAnnotation.Url(url, linkStyles)) { append(label) }
                        i = urlEnd + 1
                    } else { append(text[i]); i++ }
                } else { append(text[i]); i++ }
            }
            // bare https:// or http:// autolink
            text.startsWith("http://", i) || text.startsWith("https://", i) -> {
                var end = i
                while (end < n && !text[end].isWhitespace() && text[end] !in ")]},") end++
                val url = text.substring(i, end)
                withLink(LinkAnnotation.Url(url, linkStyles)) { append(url) }
                i = end
            }
            (text[i] == '*' || text[i] == '_') -> {
                val marker = text[i]
                val end = text.indexOf(marker, i + 1)
                if (end != -1 && end > i + 1) {
                    withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(text.substring(i + 1, end)) }
                    i = end + 1
                } else { append(text[i]); i++ }
            }
            else -> { append(text[i]); i++ }
        }
    }
}
