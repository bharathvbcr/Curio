//
//  CurioMarkdown.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/CurioMarkdown.kt
//         (MarkdownText, BulletRow, NumberRow, BlockQuote, CodeBlock, parseInline).
//
//  A hand-rolled markdown renderer for AI-generated copy (deep analysis, chat). Supports a
//  pragmatic subset: `# / ## / ### / ####` headings, `- / * / •` and numbered bullets, `>`
//  blockquotes, fenced ``` code blocks, blank-line spacing, and inline `**bold**`,
//  `*italic*`/`_italic_`, `~~strike~~`, `` `code` ``, `[label](url)` links, and bare
//  `http(s)://` autolinks. Links are tappable and open in the browser.
//
//  CONVENTIONS §10 (Markdown parser edge cases preserved):
//   - unmatched inline markers are appended literally;
//   - italic requires a later matching marker (`end > i+1`) else the marker is literal;
//   - autolink terminator set is exactly `)]},` plus whitespace;
//   - heading font multipliers `1.0 / 1.05 / 1.12 / 1.2` carried verbatim;
//   - block dispatch order (fence → blank → #### → ### → ## → # → quote → bullet →
//     numbered → paragraph) is preserved exactly so the same precedence applies.
//
//  The Kotlin renderer used Compose `AnnotatedString` + `LinkAnnotation.Url`. Here we build a
//  SwiftUI `AttributedString` with `.link`/`.font`/`.foregroundColor`/`.strikethroughStyle`
//  runs, and render each block as a `Text`. Indexing is done over a `[Character]` array so the
//  `i + 2`/`indexOf` offset arithmetic from Kotlin transfers 1:1 (operating on Characters, not
//  UTF-16 code units; the AI copy involved is plain text so this matches in practice — see
//  CONVENTIONS §10 char-count note).
//

import SwiftUI

/// Lightweight markdown renderer for AI-generated copy (deep analysis, chat).
///
/// Mirrors the Android `MarkdownText` composable. `style` supplies the base point size /
/// weight (Curio type role); `color` is the body color; `accent` tints headings, bullet
/// glyphs, numbered markers, links, and the quote bar.
struct MarkdownText: View {
    let markdown: String
    var style: CurioTextStyle = CurioFont.bodyMedium
    var color: Color? = nil
    var accent: Color? = nil

    @Environment(\.curioColors) private var colors

    private var resolvedColor: Color { color ?? colors.onSurface }
    private var resolvedAccent: Color { accent ?? colors.primary }
    private var codeColor: Color { colors.tertiary }

    var body: some View {
        // `markdown.trim().split("\n")` — Kotlin `split` keeps a trailing empty element; we
        // mirror that by splitting on "\n" without omitting empty subsequences.
        let lines = markdown
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 4) {
            blocks(from: lines)
        }
    }

    /// Walks the lines with the same `while`-loop / index advancement as the Kotlin version
    /// and emits a typed block per dispatch branch.
    @ViewBuilder
    private func blocks(from lines: [String]) -> some View {
        let parsed = Self.parseBlocks(
            lines: lines,
            accent: resolvedAccent,
            codeColor: codeColor,
            baseSize: style.size
        )
        ForEach(parsed) { block in
            blockView(block)
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .blank:
            Spacer().frame(height: 3)

        case let .code(text):
            CodeBlock(code: text, baseStyle: style, codeColor: codeColor)

        case let .heading(content, multiplier):
            // Headings are FontWeight.Black with the role size scaled by the multiplier.
            Text(content)
                .font(.system(size: style.size * multiplier, weight: .black))
                .tracking(style.tracking)
                .lineSpacing(style.lineSpacing)
                .foregroundStyle(resolvedColor)

        case let .quote(content):
            BlockQuote(content: content, style: style, color: resolvedColor, accent: resolvedAccent)

        case let .bullet(content):
            BulletRow(content: content, style: style, color: resolvedColor, accent: resolvedAccent)

        case let .numbered(number, content):
            NumberRow(number: number, content: content, style: style, color: resolvedColor, accent: resolvedAccent)

        case let .paragraph(content):
            Text(content)
                .curioText(style)
                .foregroundStyle(resolvedColor)
        }
    }
}

// MARK: - Block model

/// A parsed markdown block. The accompanying `content`/`number` are already inline-parsed
/// into `AttributedString` (headings keep their multiplier so the View applies the font).
private struct MarkdownBlock: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case blank
        case code(String)
        /// Inline content + heading font-size multiplier (`1.2 / 1.12 / 1.05 / 1.0`).
        case heading(AttributedString, multiplier: CGFloat)
        case quote(AttributedString)
        case bullet(AttributedString)
        case numbered(String, AttributedString)
        case paragraph(AttributedString)
    }
}

extension MarkdownText {

    /// Block-level state machine — a faithful transliteration of the Kotlin `while (i < lines.size)`
    /// dispatch (CONVENTIONS §10: order and index advancement preserved exactly).
    fileprivate static func parseBlocks(
        lines: [String],
        accent: Color,
        codeColor: Color,
        baseSize: CGFloat
    ) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var i = 0
        while i < lines.count {
            let raw = lines[i]
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                // Fenced code block: gobble lines until the closing fence.
                var collected: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    collected.append(lines[i])
                    i += 1
                }
                // Kotlin `appendLine` joins each with "\n" (including a trailing "\n"), then
                // `trimEnd()` removes trailing whitespace/newlines.
                var code = collected.map { $0 + "\n" }.joined()
                code = String(code.reversed().drop(while: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }).reversed())
                blocks.append(MarkdownBlock(kind: .code(code)))
            } else if line.isBlank {
                blocks.append(MarkdownBlock(kind: .blank))
            } else if line.hasPrefix("#### ") {
                let content = parseInline(String(line.dropFirst(5)), accent: accent, codeColor: codeColor)
                blocks.append(MarkdownBlock(kind: .heading(content, multiplier: 1.0)))
            } else if line.hasPrefix("### ") {
                let content = parseInline(String(line.dropFirst(4)), accent: accent, codeColor: codeColor)
                blocks.append(MarkdownBlock(kind: .heading(content, multiplier: 1.05)))
            } else if line.hasPrefix("## ") {
                let content = parseInline(String(line.dropFirst(3)), accent: accent, codeColor: codeColor)
                blocks.append(MarkdownBlock(kind: .heading(content, multiplier: 1.12)))
            } else if line.hasPrefix("# ") {
                let content = parseInline(String(line.dropFirst(2)), accent: accent, codeColor: codeColor)
                blocks.append(MarkdownBlock(kind: .heading(content, multiplier: 1.2)))
            } else if line.hasPrefix("> ") {
                let body = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                blocks.append(MarkdownBlock(kind: .quote(parseInline(body, accent: accent, codeColor: codeColor))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                // Kotlin `line.drop(2)` drops the first 2 characters then trims.
                let body = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                blocks.append(MarkdownBlock(kind: .bullet(parseInline(body, accent: accent, codeColor: codeColor))))
            } else if let m = matchNumbered(line) {
                blocks.append(MarkdownBlock(kind: .numbered(m.number, parseInline(m.body, accent: accent, codeColor: codeColor))))
            } else {
                blocks.append(MarkdownBlock(kind: .paragraph(parseInline(line, accent: accent, codeColor: codeColor))))
            }
            i += 1
        }
        return blocks
    }

    /// Ports `private val NUMBERED = Regex("^(\\d+)\\.\\s+(.*)")` with `matchEntire`.
    /// Returns the captured number string + remaining body, or nil if the whole line does
    /// not match the pattern.
    private static func matchNumbered(_ line: String) -> (number: String, body: String)? {
        // `^(\d+)\.\s+(.*)` anchored to the whole string (matchEntire).
        guard let regex = numberedRegex else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.range == range,
              let numRange = Range(match.range(at: 1), in: line),
              let bodyRange = Range(match.range(at: 2), in: line)
        else { return nil }
        return (String(line[numRange]), String(line[bodyRange]))
    }

    private static let numberedRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: "^(\\d+)\\.\\s+(.*)$", options: [])
}

// MARK: - Inline parser

extension MarkdownText {

    /// Parses inline markdown into an `AttributedString`: `**bold**`, `*italic*`/`_italic_`,
    /// `~~strike~~`, `` `code` ``, `[label](url)` links, and bare `http(s)://` autolinks.
    ///
    /// Direct transliteration of the Kotlin `parseInline` `while`-loop. Operates over a
    /// `[Character]` array so the `indexOf`/`startsWith`/`substring(i+2, end)` offset
    /// arithmetic transfers one-for-one. Unmatched markers are appended literally; italic
    /// requires `end > i + 1` (CONVENTIONS §10).
    static func parseInline(_ text: String, accent: Color, codeColor: Color) -> AttributedString {
        let chars = Array(text)
        let n = chars.count
        var result = AttributedString("")
        var i = 0

        // Appends a plain (unstyled) string run.
        func appendPlain(_ s: String) {
            result.append(AttributedString(s))
        }

        while i < n {
            if startsWith(chars, "**", at: i) {
                if let end = indexOf(chars, "**", from: i + 2) {
                    // `inlinePresentationIntent` composes with the base Text font, so the bold
                    // run keeps the role size — matching Compose `SpanStyle(fontWeight = Black)`.
                    var run = AttributedString(String(chars[(i + 2)..<end]))
                    run.inlinePresentationIntent = .stronglyEmphasized
                    result.append(run)
                    i = end + 2
                } else { appendPlain(String(chars[i])); i += 1 }
            } else if startsWith(chars, "~~", at: i) {
                if let end = indexOf(chars, "~~", from: i + 2) {
                    var run = AttributedString(String(chars[(i + 2)..<end]))
                    run.inlinePresentationIntent = .strikethrough
                    result.append(run)
                    i = end + 2
                } else { appendPlain(String(chars[i])); i += 1 }
            } else if chars[i] == "`" {
                if let end = indexOfChar(chars, "`", from: i + 1) {
                    var run = AttributedString(String(chars[(i + 1)..<end]))
                    run.font = .system(size: 13, weight: .regular, design: .monospaced)
                    run.foregroundColor = codeColor
                    result.append(run)
                    i = end + 1
                } else { appendPlain(String(chars[i])); i += 1 }
            } else if chars[i] == "[" {
                // [label](url)
                let close = indexOfChar(chars, "]", from: i + 1)
                let open = (close != nil) ? close! + 1 : -1
                if let close, open < n, chars[open] == "(" {
                    if let urlEnd = indexOfChar(chars, ")", from: open + 1) {
                        let label = String(chars[(i + 1)..<close])
                        let url = String(chars[(open + 1)..<urlEnd]).trimmingCharacters(in: .whitespaces)
                        var run = AttributedString(label)
                        run.foregroundColor = accent
                        run.underlineStyle = .single
                        if let parsed = URL(string: url) { run.link = parsed }
                        result.append(run)
                        i = urlEnd + 1
                    } else { appendPlain(String(chars[i])); i += 1 }
                } else { appendPlain(String(chars[i])); i += 1 }
            } else if startsWith(chars, "http://", at: i) || startsWith(chars, "https://", at: i) {
                // bare https:// or http:// autolink
                var end = i
                while end < n && !chars[end].isWhitespace && !"]},)".contains(chars[end]) { end += 1 }
                let url = String(chars[i..<end])
                var run = AttributedString(url)
                run.foregroundColor = accent
                run.underlineStyle = .single
                if let parsed = URL(string: url) { run.link = parsed }
                result.append(run)
                i = end
            } else if chars[i] == "*" || chars[i] == "_" {
                let marker = chars[i]
                if let end = indexOfChar(chars, marker, from: i + 1), end > i + 1 {
                    var run = AttributedString(String(chars[(i + 1)..<end]))
                    run.inlinePresentationIntent = .emphasized
                    result.append(run)
                    i = end + 1
                } else { appendPlain(String(chars[i])); i += 1 }
            } else {
                appendPlain(String(chars[i])); i += 1
            }
        }
        return result
    }

    // MARK: char helpers — Kotlin String.startsWith(prefix, index) / indexOf(string, from)

    /// Kotlin `text.startsWith(prefix, i)`: true when `prefix` occurs at offset `i`.
    private static func startsWith(_ chars: [Character], _ prefix: String, at i: Int) -> Bool {
        let p = Array(prefix)
        if i + p.count > chars.count { return false }
        for k in 0..<p.count where chars[i + k] != p[k] { return false }
        return true
    }

    /// Kotlin `text.indexOf(string, fromIndex)` for a multi-char needle; returns the start
    /// offset or nil. A `from` past the end yields nil.
    private static func indexOf(_ chars: [Character], _ needle: String, from: Int) -> Int? {
        let p = Array(needle)
        if p.isEmpty { return from }
        var i = max(0, from)
        while i + p.count <= chars.count {
            var match = true
            for k in 0..<p.count where chars[i + k] != p[k] { match = false; break }
            if match { return i }
            i += 1
        }
        return nil
    }

    /// Kotlin `text.indexOf(char, fromIndex)`; returns the offset or nil.
    private static func indexOfChar(_ chars: [Character], _ needle: Character, from: Int) -> Int? {
        var i = max(0, from)
        while i < chars.count {
            if chars[i] == needle { return i }
            i += 1
        }
        return nil
    }
}

// MARK: - Block sub-views

/// A bulleted line: an accent disc + the inline content (ports `BulletRow`).
private struct BulletRow: View {
    let content: AttributedString
    let style: CurioTextStyle
    let color: Color
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(accent)
                .frame(width: 5, height: 5)
                .padding(.top, 7)
            Text(content)
                .curioText(style)
                .foregroundStyle(color)
        }
    }
}

/// A numbered list line: an accent `N.` marker (fixed 18pt width) + the inline content
/// (ports `NumberRow`).
private struct NumberRow: View {
    let number: String
    let content: AttributedString
    let style: CurioTextStyle
    let color: Color
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.system(size: style.size, weight: .black))
                .tracking(style.tracking)
                .foregroundStyle(accent)
                .frame(width: 18, alignment: .leading)
            Text(content)
                .curioText(style)
                .foregroundStyle(color)
        }
    }
}

/// A blockquote line: a 3pt accent bar + italicised, slightly-dimmed content (ports `BlockQuote`).
private struct BlockQuote: View {
    let content: AttributedString
    let style: CurioTextStyle
    let color: Color
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent.opacity(0.6))
                .frame(width: 3, height: 18)
                .padding(.vertical, 2)
            Text(content)
                .font(.system(size: style.size, weight: style.weight).italic())
                .tracking(style.tracking)
                .lineSpacing(style.lineSpacing)
                .foregroundStyle(color.opacity(0.85))
        }
    }
}

/// A fenced code block: monospace 13pt, tertiary-tinted, on a subtle fill, horizontally
/// scrollable (ports `CodeBlock`).
private struct CodeBlock: View {
    let code: String
    let baseStyle: CurioTextStyle
    let codeColor: Color

    @Environment(\.curioColors) private var colors

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(.system(size: 13, weight: baseStyle.weight, design: .monospaced))
                .foregroundStyle(codeColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.onSurface.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
