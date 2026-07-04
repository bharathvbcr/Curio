import Foundation
import AppIntents

// MARK: - App Intent value types
//
// Direct port of `appfunctions/CurioFunctionModels.kt` — the two `@AppFunctionSerializable`
// data classes that Curio exposes to on-device AI agents / Android system assistants.
//
// On Android these are `BookmarkSummary` (a condensed list/search projection) and
// `BookmarkDetail` (the full record). The KDoc on every Kotlin field is load-bearing
// (`isDescribedByKDoc = true`) — the agent reads it to understand the schema — so each
// property comment is carried over verbatim and surfaced to App Intents through
// `TypeDisplayRepresentation` / per-property `DisplayRepresentation` where the framework
// exposes it.
//
// iOS mapping (see DESIGN §11 "Platform" row `CurioFunctionModels.swift` and the tech-mapping
// table row "AppFunctions → App Intents"):
//   - `@AppFunctionSerializable` data class  → `struct … : AppEntity` (a transferable value the
//     intents return). App Intents requires every entity to carry a stable `id` plus a
//     `displayRepresentation`; both Kotlin types already have a string `id`, reused as the
//     `EntityIdentifier`.
//   - Kotlin `List<String> tags` → Swift `[String]` (default `[]` — never `nil`; matches the
//     Kotlin non-null `List<String>` with "empty list if not yet analysed").
//   - Kotlin nullable `String?` fields stay `String?` (sentinel parity: `nil` == not yet analysed,
//     mirroring the Android `null`).
//   - `sourceType` is carried as the **raw uppercase `.name` string** on the wire (`ARXIV`,
//     `GITHUB`, `HUGGING_FACE`, `DOI`, `TWEET`) exactly as `sourceType?.name` produced it on
//     Android — it is a persistence/agent key and must never be localised or renamed
//     (CONVENTIONS §1 persistence-key stability).
//   - `createdAt` is the ISO-8601 **UTC** rendering of the epoch-millis `createdAt`, produced to
//     match `java.time.Instant.ofEpochMilli(createdAt).toString()` byte-for-byte (always a
//     trailing `Z`, fractional `.SSS` only when the millisecond component is non-zero).
//
// The mapping logic (`Bookmark → BookmarkSummary/BookmarkDetail`, including the **300-char text
// truncation on the summary**, the blank-note-clears semantics, and the `sourceType?.name`
// projection) is the `Bookmark.toSummary()` / `Bookmark.toDetail()` extensions in
// `CurioFunctions.kt`; they are ported here as static factories so both `CurioFunctionModels`
// and `CurioIntents` share one source of truth.
//
// NOTE: these are App-Intents value types and are exercised only inside intent execution, which
// is already iOS 26+ on this target; `AppEntity` and friends need no extra availability gate.

/// Condensed view of a bookmark for search results and list responses.
///
/// Direct port of `BookmarkSummary` in `CurioFunctionModels.kt`.
struct BookmarkSummary: AppEntity, Identifiable, Hashable, Sendable {

    /// Unique identifier; required by getBookmarkDetail, addNoteToBookmark, toggleFavorite, and exportCitation.
    let id: String
    /// Raw tweet text or manually added content (first 300 characters).
    let text: String
    /// AI-generated short title, or null if not yet analysed.
    let title: String?
    /// AI-generated one-paragraph summary, or null if not yet analysed.
    let summary: String?
    /// Research tags, e.g. ["attention", "transformers"]. Empty list if not yet analysed.
    let tags: [String]
    /// Research category such as "Deep Learning" or "NLP". Null if not yet analysed.
    let category: String?
    /// Title of the resolved primary source (arXiv paper, GitHub repo, etc.), or null.
    let sourceTitle: String?
    /// True when the user has starred this bookmark.
    let isFavorite: Bool
    /// ISO-8601 UTC timestamp of when the bookmark was saved.
    let createdAt: String

    init(
        id: String,
        text: String,
        title: String?,
        summary: String?,
        tags: [String],
        category: String?,
        sourceTitle: String?,
        isFavorite: Bool,
        createdAt: String
    ) {
        self.id = id
        self.text = text
        self.title = title
        self.summary = summary
        self.tags = tags
        self.category = category
        self.sourceTitle = sourceTitle
        self.isFavorite = isFavorite
        self.createdAt = createdAt
    }

    // MARK: AppEntity conformance

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Bookmark")

    /// Use the AI-generated title when present, else the (already-truncated) text, mirroring the
    /// "title falls back to the snippet" presentation used throughout the Curio UI. Never displays
    /// the AI `category` (UI invariant — category seeds Spaces only).
    var displayRepresentation: DisplayRepresentation {
        let primary: String = {
            if let title, !title.isEmpty { return title }
            let snippet = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return snippet.isEmpty ? "Untitled Curio" : snippet
        }()
        if let summary, !summary.isEmpty {
            return DisplayRepresentation(title: "\(primary)", subtitle: "\(summary)")
        }
        return DisplayRepresentation(title: "\(primary)")
    }
}

/// Full detail record for a single bookmark including all AI analysis and user annotations.
///
/// Direct port of `BookmarkDetail` in `CurioFunctionModels.kt`.
struct BookmarkDetail: AppEntity, Identifiable, Hashable, Sendable {

    /// Unique identifier.
    let id: String
    /// Full raw text content of the bookmark.
    let text: String
    /// AI-generated short title, or null.
    let title: String?
    /// AI-generated one-paragraph summary, or null.
    let summary: String?
    /// Structured AI deep-analysis (contributions, significance, limitations), or null.
    let deepSummary: String?
    /// Research tags.
    let tags: [String]
    /// Research category, or null.
    let category: String?
    /// JSON with extracted entities: {"models":[], "methods":[], "datasets":[], "metrics":[]}.
    let entities: String?
    /// User's personal annotation note, or null.
    let notes: String?
    /// Source type: ARXIV, GITHUB, HUGGING_FACE, DOI, or TWEET. Null if unresolved.
    let sourceType: String?
    /// Source identifier (arXiv ID, GitHub "owner/repo", DOI).
    let sourceId: String?
    /// Resolved primary-source title.
    let sourceTitle: String?
    /// Comma-separated author names.
    let sourceAuthors: String?
    /// Primary-source abstract text.
    let sourceAbstract: String?
    /// True when starred by the user.
    let isFavorite: Bool
    /// True when saved for later reading.
    let isSavedForLater: Bool
    /// ISO-8601 UTC timestamp of when the bookmark was saved.
    let createdAt: String

    init(
        id: String,
        text: String,
        title: String?,
        summary: String?,
        deepSummary: String?,
        tags: [String],
        category: String?,
        entities: String?,
        notes: String?,
        sourceType: String?,
        sourceId: String?,
        sourceTitle: String?,
        sourceAuthors: String?,
        sourceAbstract: String?,
        isFavorite: Bool,
        isSavedForLater: Bool,
        createdAt: String
    ) {
        self.id = id
        self.text = text
        self.title = title
        self.summary = summary
        self.deepSummary = deepSummary
        self.tags = tags
        self.category = category
        self.entities = entities
        self.notes = notes
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.sourceTitle = sourceTitle
        self.sourceAuthors = sourceAuthors
        self.sourceAbstract = sourceAbstract
        self.isFavorite = isFavorite
        self.isSavedForLater = isSavedForLater
        self.createdAt = createdAt
    }

    // MARK: AppEntity conformance

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Bookmark Detail")

    var displayRepresentation: DisplayRepresentation {
        let primary: String = {
            if let title, !title.isEmpty { return title }
            let snippet = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return snippet.isEmpty ? "Untitled Curio" : snippet
        }()
        if let summary, !summary.isEmpty {
            return DisplayRepresentation(title: "\(primary)", subtitle: "\(summary)")
        }
        return DisplayRepresentation(title: "\(primary)")
    }
}

// MARK: - Bookmark → App-Intent value mappers
//
// Ports the `Bookmark.toSummary()` / `Bookmark.toDetail()` private extensions from
// `CurioFunctions.kt`. Kept here (next to the value types) so `CurioIntents` and any future caller
// share one mapping. Every projection rule is preserved exactly:
//   - `text.take(300)` on the summary (Kotlin `take` counts UTF-16 code units; see below).
//   - full `text` on the detail (no truncation).
//   - `sourceType?.name` → the raw uppercase enum name (or `nil`).
//   - `Instant.ofEpochMilli(createdAt).toString()` → `CurioInstant.iso8601(fromEpochMillis:)`.

extension BookmarkSummary {

    /// Ports `Bookmark.toSummary()`.
    static func from(_ bookmark: Bookmark) -> BookmarkSummary {
        BookmarkSummary(
            id: bookmark.id,
            text: CurioInstant.take(bookmark.text, 300),
            title: bookmark.title,
            summary: bookmark.summary,
            tags: bookmark.tags,
            category: bookmark.category,
            sourceTitle: bookmark.sourceTitle,
            isFavorite: bookmark.isFavorite,
            createdAt: CurioInstant.iso8601(fromEpochMillis: bookmark.createdAt)
        )
    }
}

extension BookmarkDetail {

    /// Ports `Bookmark.toDetail()`.
    static func from(_ bookmark: Bookmark) -> BookmarkDetail {
        BookmarkDetail(
            id: bookmark.id,
            text: bookmark.text,
            title: bookmark.title,
            summary: bookmark.summary,
            deepSummary: bookmark.deepSummary,
            tags: bookmark.tags,
            category: bookmark.category,
            entities: bookmark.entities,
            notes: bookmark.notes,
            sourceType: bookmark.sourceType?.rawValue,
            sourceId: bookmark.sourceId,
            sourceTitle: bookmark.sourceTitle,
            sourceAuthors: bookmark.sourceAuthors,
            sourceAbstract: bookmark.sourceAbstract,
            isFavorite: bookmark.isFavorite,
            isSavedForLater: bookmark.isSavedForLater,
            createdAt: CurioInstant.iso8601(fromEpochMillis: bookmark.createdAt)
        )
    }
}

// MARK: - Instant / text helpers
//
// Small Foundation-only helpers shared by the App-Intent mappers. Determinism is load-bearing
// (CONVENTIONS §10): the ISO rendering and the truncation must match the Android output exactly so
// agents see identical payloads on both platforms.

enum CurioInstant {

    /// Reimplements Kotlin/Java `String.take(n)` (UTF-16 code-unit count) for the 300-char summary
    /// truncation in `Bookmark.toSummary()`.
    ///
    /// Kotlin `String.take(n)` returns the first `n` **UTF-16 code units** (or the whole string when
    /// shorter). Swift `String.prefix(n)` counts grapheme clusters, which diverges for emoji /
    /// combining sequences. To stay byte-faithful for downstream agents we operate on `utf16` and
    /// reconstruct, exactly mirroring the JVM semantics (a split through a surrogate pair yields the
    /// same lone surrogate the JVM would, and `String(utf16CodeUnits:)` rebuilds it identically).
    static func take(_ s: String, _ n: Int) -> String {
        if n <= 0 { return "" }
        let units = Array(s.utf16)
        if units.count <= n { return s }
        let slice = Array(units[0..<n])
        return String(utf16CodeUnits: slice, count: slice.count)
    }

    /// Renders epoch **milliseconds** as an ISO-8601 / RFC-3339 UTC string, matching
    /// `java.time.Instant.ofEpochMilli(ms).toString()` byte-for-byte.
    ///
    /// `Instant.toString()` rules we reproduce:
    ///   - Always UTC with a literal trailing `Z`.
    ///   - Always full `yyyy-MM-dd'T'HH:mm:ss`.
    ///   - A fractional component is appended **only when non-zero**. For epoch-millis input the
    ///     fraction is at most milliseconds, and Java emits it zero-padded to exactly 3 digits
    ///     (`.SSS`) — e.g. `2021-01-06T18:40:40.500Z`. When the millisecond remainder is 0 no
    ///     fraction is printed (`2021-01-06T18:40:40Z`).
    ///   - Years are zero-padded to at least 4 digits (e.g. `0001-…`); years ≥ 10000 gain a leading
    ///     `+`. We mirror this via the formatted-year fix-up below.
    ///
    /// `ISO8601DateFormatter` cannot conditionally include fractional seconds, so the seconds/whole
    /// part and the optional fraction are assembled manually from UTC calendar components.
    static func iso8601(fromEpochMillis ms: Int64) -> String {
        // Floor-division so a negative epoch (pre-1970) still maps to a non-negative millisecond
        // remainder, matching Java's `Math.floorMod` behaviour inside `Instant`.
        let totalMillis = ms
        var seconds = totalMillis / 1000
        var millis = totalMillis % 1000
        if millis < 0 {
            millis += 1000
            seconds -= 1
        }

        let date = Date(timeIntervalSince1970: TimeInterval(seconds))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )

        let year = c.year ?? 1970
        let yearString: String = {
            if year >= 0 && year <= 9999 {
                return String(format: "%04d", year)
            } else if year < 0 {
                // Java prints a leading '-' and zero-pads the magnitude to at least 4 digits.
                return String(format: "-%04d", -year)
            } else {
                // year >= 10000 → Java prefixes '+'.
                return String(format: "+%d", year)
            }
        }()

        let base = String(
            format: "%@-%02d-%02dT%02d:%02d:%02d",
            yearString,
            c.month ?? 1,
            c.day ?? 1,
            c.hour ?? 0,
            c.minute ?? 0,
            c.second ?? 0
        )

        if millis == 0 {
            return base + "Z"
        }
        return base + String(format: ".%03d", millis) + "Z"
    }
}
