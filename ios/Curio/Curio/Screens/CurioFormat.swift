//
//  CurioFormat.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/CurioFormat.kt (all internal top-level helpers).
//
//  DESIGN §10 (Screens): `enum CurioFormat`: relativeTime, readingTime, displayAuthor,
//  authorInitial, sourceDisplayName, cleanSnippet, formatEpoch, getCategoryColor
//  (**stable Java-hashCode reimpl** for fallback), copyToClipboard, tweetUrl, openUrl,
//  shareBookmark, exportBackupJson, exportBackupCsv.
//
//  CONVENTIONS:
//  - §1 "Enums as namespaces": caseless `enum CurioFormat` (never instantiated).
//  - §10 "Java String.hashCode reimplementation is REQUIRED" for `getCategoryColor`'s fallback
//    palette — Swift `String.hashValue` is randomized per run, so we reimplement the JVM
//    `31 * h + c` accumulation with Int32 overflow so colors stay STABLE across launches. The
//    fallback index then mirrors Kotlin `Math.abs(hash) % colors.size` EXACTLY (including the
//    `Int.MIN_VALUE` edge where `abs` overflows back to a negative — see `javaStringHashCode`).
//  - §8 "ARGB": colours are built with the single `Color(argb:)` boundary helper (Theme),
//    carrying every `Color(0xFF…)` literal verbatim per the Kotlin palette.
//  - §10 "Regexes ported with identical patterns": `cleanSnippet` strips `https?://\S+`;
//    `readingTime` splits on `\s+`.
//  - The Android clipboard/share/open + Toast paths become iOS `UIPasteboard` / share sheet /
//    `UIApplication.open`; Toasts are dropped at this layer (the call sites surface a transient
//    SwiftUI overlay per CONVENTIONS §"Clipboard / Share / Open URL"). The functions return a
//    `Bool`/optional where the Kotlin signalled success via a Toast so callers can drive the
//    overlay. Exact backup byte-formats (`exportBackupJson`/`exportBackupCsv`) are preserved.
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Pure formatting + system-interaction helpers for the feed/reader UI. Caseless namespace
/// (CONVENTIONS §1). Direct port of the `internal fun`s in `CurioFormat.kt`.
enum CurioFormat {

    // MARK: - Relative / absolute time

    /// Compact relative timestamp, X-style ("now", "5m", "3h", "2d", then date). Port of
    /// `relativeTime(epochMs)`.
    ///
    /// `epochMs` is Unix epoch **milliseconds** (`Bookmark.createdAt`). A future timestamp
    /// (`diff < 0`) reads "now", matching the Kotlin guard. The terminal date uses the
    /// device-locale "MMM d" format; any formatting failure falls back to `"<days>d"`.
    static func relativeTime(_ epochMs: Int64) -> String {
        let diff = nowMillis() - epochMs
        if diff < 0 { return "now" }
        let mins = diff / 60_000
        let hrs = diff / 3_600_000
        let days = diff / 86_400_000
        if mins < 1 {
            return "now"
        } else if mins < 60 {
            return "\(mins)m"
        } else if hrs < 24 {
            return "\(hrs)h"
        } else if days < 7 {
            return "\(days)d"
        } else {
            // SimpleDateFormat("MMM d", Locale.getDefault()) over Date(epochMs).
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.dateFormat = "MMM d"
            let date = Date(timeIntervalSince1970: Double(epochMs) / 1000.0)
            let formatted = formatter.string(from: date)
            // Mirror the Kotlin `try { … } catch { "<days>d" }`: DateFormatter never throws, but if
            // it ever produced an empty string we keep the same fallback shape.
            return formatted.isEmpty ? "\(days)d" : formatted
        }
    }

    /// Approximate reading time from word count (~200 wpm). Returns `nil` for very short posts
    /// (< 40 words). Port of `readingTime(text)`.
    ///
    /// Word count splits on the `\s+` regex (identical pattern) and counts non-blank tokens; the
    /// minutes are `max(1, round(words / 200))`.
    static func readingTime(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" || $0.isWhitespace })
        // `count { it.isNotBlank() }` — a split on `\s+` can still surface blank tokens at the
        // edges (leading/trailing), so filter them out exactly like Kotlin.
        let words = tokens.filter { !$0.allSatisfy { $0.isWhitespace } }.count
        if words < 40 { return nil }
        // Math.max(1, Math.round(words / 200f)). `Math.round(Float)` rounds half up to the nearest
        // Int — Swift `(Float).rounded(.toNearestOrAwayFromZero)` matches for the non-negative range.
        let mins = max(1, Int((Float(words) / 200.0).rounded(.toNearestOrAwayFromZero)))
        return "\(mins) min read"
    }

    /// Convert Epoch Milliseconds to human-readable date format. Port of `formatEpoch(epochMs)`
    /// (`SimpleDateFormat("MMM dd, yyyy - HH:mm")`); failure → "Just now".
    static func formatEpoch(_ epochMs: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM dd, yyyy - HH:mm"
        let date = Date(timeIntervalSince1970: Double(epochMs) / 1000.0)
        let formatted = formatter.string(from: date)
        return formatted.isEmpty ? "Just now" : formatted
    }

    // MARK: - Author / source display

    /// Display name for the post — the real tweet author when known, else the source. Port of
    /// `displayAuthor(b)`.
    static func displayAuthor(_ b: Bookmark) -> String {
        if let trimmed = b.authorName?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            return trimmed
        }
        return sourceDisplayName(b)
    }

    /// The single-letter avatar initial for a tweet author, or `nil` for non-tweet sources. Port of
    /// `authorInitial(b)`.
    ///
    /// Kotlin: returns null unless the source is a tweet (or unset); then the first letter-or-digit
    /// of the trimmed author name, uppercased.
    static func authorInitial(_ b: Bookmark) -> Character? {
        if b.sourceType != nil && b.sourceType != .TWEET { return nil }
        guard let name = b.authorName?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        guard let firstAlnum = name.first(where: { $0.isLetter || $0.isNumber }) else { return nil }
        // `Char.uppercaseChar()` uppercases a single character (locale-independent). `uppercased()`
        // on a Character can yield multiple scalars (e.g. ß → SS); we take the first scalar's
        // character form to keep it a single Char, matching the Kotlin `Char` return.
        let upper = String(firstAlnum).uppercased()
        return upper.first
    }

    /// A human "author/handle" label for the post, derived from its source. Port of
    /// `sourceDisplayName(b)`.
    ///
    /// For tweets / unset sources it derives the URL host (stripping a leading `www.`), falling back
    /// to "Curio". `runCatching { URI(it).host }` becomes a tolerant `URLComponents`/`URL` host read.
    static func sourceDisplayName(_ b: Bookmark) -> String {
        switch b.sourceType {
        case .ARXIV: return "arXiv"
        case .GITHUB: return "GitHub"
        case .HUGGING_FACE: return "Hugging Face"
        case .DOI: return "DOI"
        case .TWEET, nil:
            let host: String? = {
                guard let raw = b.url else { return nil }
                // `java.net.URI(it).host` — parse and read the host; any failure → nil (runCatching).
                guard let comps = URLComponents(string: raw), let h = comps.host else { return nil }
                if h.hasPrefix("www.") {
                    return String(h.dropFirst("www.".count))
                }
                return h
            }()
            return host ?? "Curio"
        }
    }

    /// Strip a trailing URL so the snippet reads cleanly. Port of `cleanSnippet(text)`.
    ///
    /// Replaces every `https?://\S+` match with "", trims, and — if that empties the string —
    /// falls back to the trimmed original (`ifBlank { text.trim() }`).
    static func cleanSnippet(_ text: String) -> String {
        let stripped = urlStripRegex.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return stripped
    }

    /// `"https?://\\S+"` — identical pattern to the Kotlin `cleanSnippet` regex (CONVENTIONS §10).
    private static let urlStripRegex: NSRegularExpression = {
        // Force-try is safe: the pattern is a compile-time constant known to be valid.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "https?://\\S+", options: [])
    }()

    // MARK: - Category palette

    /// Category palette aligned with `CategorySpaces` so card accents match suggestion pills.
    static func getCategoryColor(_ category: String) -> Color {
        Color(packedARGB: CategorySpaces.forCategory(category).color)
    }

    /// Reimplements `java.lang.String.hashCode()`: `s[0]*31^(n-1) + s[1]*31^(n-2) + … + s[n-1]`,
    /// accumulated as `h = 31*h + c` over the string's **UTF-16 code units** with Int32 (two's
    /// complement) overflow. This is the deterministic value the Kotlin `getCategoryColor` fallback
    /// relied on (CONVENTIONS §10). Swift's `String.hashValue` is salted per-run and would break
    /// colour stability, so it must NOT be used here.
    static func javaStringHashCode(_ s: String) -> Int32 {
        var h: Int32 = 0
        // Java iterates UTF-16 code units, not Unicode scalars — `String.utf16` matches that.
        for u in s.utf16 {
            h = 31 &* h &+ Int32(u)
        }
        return h
    }

    /// `Math.abs(Int)` with the JVM's overflow behaviour: `Math.abs(Int.min) == Int.min`.
    private static func javaAbs(_ v: Int32) -> Int32 {
        if v == Int32.min { return Int32.min } // overflow preserved (matches JVM)
        return v < 0 ? -v : v
    }

    // MARK: - Clipboard / share / open

    #if canImport(UIKit)
    /// Copies `text` to the system pasteboard. Port of `copyToClipboard(context, text, label)`.
    /// The Android `ClipData.newPlainText(label, …)` label has no iOS pasteboard analogue for plain
    /// strings, so `label` is accepted (default "Curio") for signature parity but unused. Returns
    /// `true` on success — the call site drives the "Copied details to clipboard!" overlay (the
    /// Android Toast). Any failure returns `false` (the "Failed to copy context" Toast analogue).
    @discardableResult
    @MainActor
    static func copyToClipboard(_ text: String, label: String = "Curio") -> Bool {
        UIPasteboard.general.string = text
        return true
    }
    #endif

    /// The canonical X/Twitter permalink for a bookmark that originated as a tweet. Port of
    /// `tweetUrl(bookmark)`.
    ///
    /// Synced tweets use the numeric tweet id as their bookmark id; manual / source-resolved entries
    /// don't, so those return `nil`. The handle strips a leading `@` and falls back to `i/web`.
    static func tweetUrl(_ bookmark: Bookmark) -> String? {
        let id = bookmark.id
        // `id.isBlank() || !id.all { it.isDigit() }`.
        if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        if !id.allSatisfy({ $0.isASCII && $0.isNumber }) { return nil }
        let handle: String = {
            guard let raw = bookmark.authorUsername?.trimmingCharacters(in: .whitespacesAndNewlines) else { return "i/web" }
            let stripped = raw.hasPrefix("@") ? String(raw.dropFirst()) : raw
            return stripped.isEmpty ? "i/web" : stripped
        }()
        return "https://x.com/\(handle)/status/\(id)"
    }

    #if canImport(UIKit)
    /// Opens a URL in the device browser, normalising a bare host to https. Port of
    /// `openUrl(context, rawUrl)`.
    ///
    /// Returns `.noLink` when the URL is blank ("No link on this bookmark"), `.failed` when the URL
    /// cannot be opened ("Couldn't open link"), or `.opened` on success — the call site maps these
    /// to the matching transient overlays the Android Toasts produced.
    enum OpenUrlResult: Sendable, Equatable { case opened, noLink, failed }

    @MainActor
    @discardableResult
    static func openUrl(_ rawUrl: String?) -> OpenUrlResult {
        guard let trimmed = rawUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return .noLink
        }
        let normalized = (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"))
            ? trimmed
            : "https://\(trimmed)"
        guard let url = URL(string: normalized) else { return .failed }
        guard UIApplication.shared.canOpenURL(url) else { return .failed }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return .opened
    }
    #endif

    #if canImport(UIKit)
    /// Presents the system share sheet for `text`. Port of `shareBookmark(context, text)`
    /// (`ACTION_SEND` + `createChooser("Share Curio Metadata")`).
    ///
    /// The Android chooser title has no direct `UIActivityViewController` analogue and is dropped.
    /// The sheet is presented from the key window's top-most view controller (the iOS equivalent of
    /// `context.startActivity`); on a failure to find a presenter the call returns `false` so the
    /// call site can surface the "Failed to share context" overlay.
    @MainActor
    @discardableResult
    static func shareBookmark(_ text: String) -> Bool {
        guard let presenter = topViewController() else { return false }
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        // iPad popover anchoring — present from the presenter's view centre so it never crashes on
        // regular-width devices (UIKit requires a source for popovers).
        if let pop = activity.popoverPresentationController {
            pop.sourceView = presenter.view
            pop.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        presenter.present(activity, animated: true, completion: nil)
        return true
    }

    /// Resolves the top-most presented view controller in the foreground active scene.
    @MainActor
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let keyWindow = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
    #endif

    // MARK: - Backup exports (byte-faithful)

    /// Exports the library as a hand-rolled JSON array. **Byte-faithful** port of
    /// `exportBackupJson(bookmarks)` (CONVENTIONS §10 export byte-fidelity).
    ///
    /// The escaping is exactly the Kotlin's: `"` → `\"`, newlines → space, for text/ocr/summary;
    /// `category` is emitted raw (empty string when nil); tags are quoted and comma-joined. The
    /// whitespace/indentation/trailing-comma layout is preserved character-for-character.
    static func exportBackupJson(_ bookmarks: [Bookmark]) -> String {
        var s = ""
        s.append("[\n")
        for (i, b) in bookmarks.enumerated() {
            let cleanText = b.text.replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: " ")
            let cleanOcr = (b.ocrText ?? "").replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: " ")
            let cleanSummary = (b.summary ?? "").replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: " ")
            let cleanCategory = b.category ?? ""
            let tagsJoined = b.tags.map { "\"\($0)\"" }.joined(separator: ",")

            s.append("  {\n")
            s.append("    \"id\": \"\(b.id)\",\n")
            s.append("    \"text\": \"\(cleanText)\",\n")
            s.append("    \"createdAt\": \(b.createdAt),\n")
            s.append("    \"ocrText\": \"\(cleanOcr)\",\n")
            s.append("    \"summary\": \"\(cleanSummary)\",\n")
            s.append("    \"category\": \"\(cleanCategory)\",\n")
            s.append("    \"tags\": [\(tagsJoined)]\n")
            s.append("  }")
            if i < bookmarks.count - 1 { s.append(",") }
            s.append("\n")
        }
        s.append("]")
        return s
    }

    /// Exports the library as CSV. **Byte-faithful** port of `exportBackupCsv(bookmarks)`.
    ///
    /// Doubles `"` → `""` (CSV quoting) for every field, collapses newlines to spaces in
    /// text/ocr/summary, defaults a nil category to "Uncategorized", and joins tags with `;`. The
    /// header row and per-field quoting are preserved exactly.
    static func exportBackupCsv(_ bookmarks: [Bookmark]) -> String {
        var s = ""
        s.append("id,text,createdAt,ocrText,summary,category,tags\n")
        for b in bookmarks {
            let cleanId = b.id.replacingOccurrences(of: "\"", with: "\"\"")
            let cleanText = b.text.replacingOccurrences(of: "\"", with: "\"\"")
                .replacingOccurrences(of: "\n", with: " ")
            let cleanOcr = (b.ocrText ?? "").replacingOccurrences(of: "\"", with: "\"\"")
                .replacingOccurrences(of: "\n", with: " ")
            let cleanSummary = (b.summary ?? "").replacingOccurrences(of: "\"", with: "\"\"")
                .replacingOccurrences(of: "\n", with: " ")
            let cleanCategory = (b.category ?? "Uncategorized").replacingOccurrences(of: "\"", with: "\"\"")
            let tagsJoined = b.tags.map { $0.replacingOccurrences(of: "\"", with: "\"\"") }.joined(separator: ";")

            s.append("\"\(cleanId)\",\"\(cleanText)\",\(b.createdAt),\"\(cleanOcr)\",\"\(cleanSummary)\",\"\(cleanCategory)\",\"\(tagsJoined)\"\n")
        }
        return s
    }

    // MARK: - Time source

    /// `System.currentTimeMillis()` — Unix epoch milliseconds.
    private static func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
