import Foundation
import AppIntents

// MARK: - Curio App Intents
//
// Direct port of `appfunctions/CurioFunctions.kt` — the six `@AppFunction`s that expose the Curio
// personal research index to on-device AI agents / system assistants. On Android these are
// `@AppFunction` methods on the `CurioFunctions` class, discovered through the AppFunctions service.
//
// iOS mapping (DESIGN tech-mapping row "AppFunctions → App Intents", DESIGN §11 Platform row, and
// CONVENTIONS §9 "App Intents"):
//   - Each `@AppFunction suspend fun …` → a distinct `struct … : AppIntent` whose `perform()` runs the
//     ported body and returns `& ReturnsValue<…>` (entities) / `& ProvidesDialog` where useful.
//   - The two return value types (`BookmarkSummary`, `BookmarkDetail`) are the `AppEntity`s defined in
//     `CurioFunctionModels.swift`; the `Bookmark → summary/detail` projection is reused verbatim from
//     there (`BookmarkSummary.from(_:)` / `BookmarkDetail.from(_:)`), so there is exactly one mapping.
//   - Dependencies (`BookmarkRepository`, `TokenStore`, `XaiKeyStore`) are injected through App Intents'
//     own `@Dependency` mechanism (App Intents cannot read `@Environment` — CONVENTIONS §2). They are
//     registered once at launch via `AppDependencyManager.shared.add { … }` in `CurioApp.init`.
//
// PORTED SEMANTICS (faithful to `CurioFunctions.kt`, CONVENTIONS §9):
//   - **Signed-in gate** (`requireUserId()`): every function that needs a user reads the current X
//     userId and throws a `LocalizedError` with the EXACT Android message
//     ("Not signed in. Open the Curio app and sign in with X to use these functions.") when absent.
//     `searchBookmarks`/`addBookmark`/`getBookmarkDetail` gate on it (matching current Android);
//     `addNoteToBookmark`/`toggleFavorite`/`exportCitation` operate on a `bookmarkId` and do NOT
//     call `requireUserId()` — that distinction is preserved.
//   - **Agent-write gate** (`requireAgentWritesAllowed`): Android replaced its old caller allowlist
//     with a user-controlled Settings toggle ("Allow assistants to modify my bookmarks", persisted in
//     `TokenStore`), because the platform does not expose the calling package to function code. The
//     same gate is ported here verbatim on the three *write* intents (`addBookmark`,
//     `addNoteToBookmark`, `toggleFavorite`); read-only discovery/detail functions are intentionally
//     not gated. The `authenticationPolicy = .requiresAuthentication` structural defence on
//     write/detail intents is kept in addition (device unlock is orthogonal to the user toggle).
//   - **Result caps / truncation**: `searchBookmarks` clamps `limit` to `1...50` (`coerceIn(1, 50)`),
//     filters by exact `category` equality when provided, then `prefix(cap)`; each result is the
//     300-char-truncated `BookmarkSummary`.
//   - **Blank-note-clears**: `addNoteToBookmark` stores `note` only when non-blank, else clears
//     (`note.takeIf { it.isNotBlank() }`), and returns the updated summary reflecting that nilled note.
//   - **toggleFavorite** defaults `favorite = true` and returns the updated summary, or nil if the id is
//     unknown.
//   - **Null-on-not-found**: detail/note/favorite/exportCitation return `nil` (an optional `AppEntity` /
//     optional `String`) when `getBookmarkById` yields nothing — mirroring the Kotlin `?: return null`.
//   - **addBookmark error wrapping**: a failed `addBookmark` rethrows as an "unknown app" style error
//     carrying "Failed to save bookmark: <message>" (Android `AppFunctionAppUnknownException`).
//
// These intents run only inside App-Intents execution, already iOS 26+ on this target, so `AppIntent`
// and friends need no extra availability gate.

// MARK: - Intent error model
//
// Ports the two Android exception types used by `CurioFunctions`:
//   - `AppFunctionDeniedException` — "not signed in" gate (and, on Android, the caller-allowlist
//     denial, which here is handled structurally by `authenticationPolicy`).
//   - `AppFunctionAppUnknownException` — the `addBookmark` failure wrapper.
// Each carries the EXACT user-facing message so an agent sees identical text on both platforms
// (CONVENTIONS §4 "Preserve exact user-facing strings", §9).

/// Errors surfaced by the Curio App Intents. `LocalizedError` so the message reaches the
/// agent / Shortcuts UI verbatim (DESIGN tech-mapping; CONVENTIONS §9 "throwing a `LocalizedError`").
enum CurioIntentError: Error, LocalizedError, CustomLocalizedStringResourceConvertible {

    /// No signed-in X user (Android `AppFunctionDeniedException`, "Not signed in…").
    case notSignedIn
    /// The user has switched off assistant write access in Settings (Android
    /// `requireAgentWritesAllowed()` denial).
    case agentWritesDisabled
    /// The ChronosFlow companion app is not installed (Android `requireChronosFlow()` denial).
    case chronosFlowNotInstalled
    /// A write/CRUD failure wrapping the underlying cause (Android `AppFunctionAppUnknownException`).
    /// `message` is the FULL composed string ("Failed to save bookmark: …") to match Android exactly.
    case appUnknown(message: String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            // EXACT Android string from `requireUserId()`.
            return "Not signed in. Open the Curio app and sign in with X to use these functions."
        case .agentWritesDisabled:
            // EXACT Android string from `requireAgentWritesAllowed()`.
            return "Assistant modifications are turned off. Enable “Allow assistants to modify my "
                + "bookmarks” in Curio Settings to use this function."
        case .chronosFlowNotInstalled:
            // EXACT Android string from `requireChronosFlow()`.
            return "ChronosFlow is not installed. Install the ChronosFlow planner app to save reminders, "
                + "inbox captures, and tasks from Curio."
        case .appUnknown(let message):
            return message
        }
    }

    /// App Intents surfaces `LocalizedStringResource` for errors; forward the same exact text.
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notSignedIn:
            return "Not signed in. Open the Curio app and sign in with X to use these functions."
        case .agentWritesDisabled:
            return "Assistant modifications are turned off. Enable “Allow assistants to modify my bookmarks” in Curio Settings to use this function."
        case .chronosFlowNotInstalled:
            return "ChronosFlow is not installed. Install the ChronosFlow planner app to save reminders, inbox captures, and tasks from Curio."
        case .appUnknown(let message):
            return LocalizedStringResource(stringLiteral: message)
        }
    }
}

// MARK: - Shared signed-in gate
//
// Ports `CurioFunctions.requireUserId()`: reads the current X userId from `TokenStore` (the iOS
// analogue of `tokenStore.userIdFlow.first()`) and throws the "Not signed in" denial when absent.
// `TokenStore.getUserId()` is actor-isolated `async` (no throws) and reads the same Keychain slot the
// Android `userIdFlow` is backed by, so this is a faithful 1:1 replacement.

private func requireUserId(_ tokenStore: TokenStore) async throws -> String {
    if let userId = await tokenStore.getUserId() {
        return userId
    }
    throw CurioIntentError.notSignedIn
}

// MARK: - Shared agent-write gate
//
// Ports `CurioFunctions.requireAgentWritesAllowed()`: the write intents (add bookmark / add note /
// toggle favourite) are gated on the user-controlled Settings toggle "Allow assistants to modify my
// bookmarks" (persisted via `TokenStore`, default true). Read-only discovery/detail functions are
// intentionally not gated — this is the available defence given the platform does not expose the
// caller's identity to intent code.

private func requireAgentWritesAllowed(_ tokenStore: TokenStore) async throws {
    if await !tokenStore.isAgentWritesAllowed() {
        throw CurioIntentError.agentWritesDisabled
    }
}

// MARK: - 1. searchBookmarks
//
// Ports `CurioFunctions.searchBookmarks(query, category, limit)`. Read-only discovery function — does
// NOT enforce the caller allowlist on Android, so it stays freely discoverable here (default
// `authenticationPolicy`). Gates on the signed-in user (`requireUserId()`).

/// Search the personal research index by keyword.
///
/// Performs a case-insensitive substring search across tweet text, AI-generated title, summary, and
/// OCR-extracted text. Returns the most recent bookmarks when `query` is blank.
struct SearchBookmarksIntent: AppIntent {

    static let title: LocalizedStringResource = "Search Bookmarks"

    static let description = IntentDescription(
        """
        Search the personal research index by keyword. Performs a case-insensitive substring search \
        across tweet text, AI-generated title, summary, and OCR-extracted text. Returns the most \
        recent bookmarks when the query is blank. Maximum 50 results.
        """
    )

    // Read-only discovery — discoverable without authentication (Android skipped `requireAllowedCaller`):
    // no `authenticationPolicy` override, so it keeps the default `.requiresAuthentication`-free behavior.

    @Parameter(
        title: "Query",
        description: "Keyword or phrase to find (e.g. \"diffusion models\", \"RLHF\"). Pass blank to get recent bookmarks."
    )
    var query: String

    @Parameter(
        title: "Category",
        description: "Optional research category to restrict results (e.g. \"Deep Learning\"). Leave empty to search all categories."
    )
    var category: String?

    @Parameter(
        title: "Limit",
        description: "Maximum results to return. Capped at 50.",
        default: 10
    )
    var limit: Int

    @Dependency private var bookmarkRepository: any BookmarkRepository
    @Dependency private var tokenStore: TokenStore

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[BookmarkSummary]> {
        let userId = try await requireUserId(tokenStore)
        // `limit.coerceIn(1, 50)` — Kotlin clamps to the closed range [1, 50].
        let cap = min(max(limit, 1), 50)
        let results = await bookmarkRepository.searchBookmarks(userId: userId, query: query)
            .filter { category == nil || $0.category == category }
            .prefix(cap)
            .map { BookmarkSummary.from($0) }
        return .result(value: Array(results))
    }
}

// MARK: - 2. addBookmark
//
// Ports `CurioFunctions.addBookmark(text)`. Write function — allowlist-gated on Android, so here it
// `requiresAuthentication`. Gates on the signed-in user, then maps the `Result<Bookmark>` failure to
// the "Failed to save bookmark: …" unknown-app error.

/// Save a new item to the research index.
///
/// Accepts raw tweet text, a URL, or any research-related text snippet. The saved bookmark is queued
/// for AI enrichment; summary, tags, and category fields populate the next time the Curio app is opened.
struct AddBookmarkIntent: AppIntent {

    static let title: LocalizedStringResource = "Add Bookmark"

    static let description = IntentDescription(
        """
        Save a new item to the research index. Accepts raw tweet text, a URL, or any research-related \
        text snippet. The saved bookmark is queued for AI enrichment; summary, tags, and category \
        fields populate the next time the Curio app is opened.
        """
    )

    /// Write function — was caller-allowlisted on Android. Approximated with required authentication.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(
        title: "Text",
        description: "The tweet content, URL, or research snippet to save."
    )
    var text: String

    @Dependency private var bookmarkRepository: any BookmarkRepository
    @Dependency private var tokenStore: TokenStore

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<BookmarkSummary> {
        try await requireAgentWritesAllowed(tokenStore)
        let userId = try await requireUserId(tokenStore)
        do {
            let bookmark = try await bookmarkRepository.addBookmark(userId: userId, text: text)
            return .result(value: BookmarkSummary.from(bookmark))
        } catch {
            // Android: `getOrElse { throw AppFunctionAppUnknownException("Failed to save bookmark: ${it.message}") }`.
            // Kotlin `it.message` is the throwable's message (may be null → "null" in interpolation); the
            // Swift analogue uses `localizedDescription`, which is always non-nil.
            throw CurioIntentError.appUnknown(message: "Failed to save bookmark: \(error.localizedDescription)")
        }
    }
}

// MARK: - 3. getBookmarkDetail
//
// Ports `CurioFunctions.getBookmarkDetail(bookmarkId)`. Detail read — gated on the signed-in user
// (`requireUserId()`, matching Android's replacement of the old caller allowlist) plus
// `requiresAuthentication`. Returns nil when the id is unknown.

/// Retrieve the full detail record for a single bookmark, including AI analysis and annotations.
///
/// Required workflow: Call Search Bookmarks first to obtain a valid bookmark id.
struct GetBookmarkDetailIntent: AppIntent {

    static let title: LocalizedStringResource = "Get Bookmark Detail"

    static let description = IntentDescription(
        """
        Retrieve the full detail record for a single bookmark, including AI analysis and annotations. \
        Call Search Bookmarks first to obtain a valid bookmark id. Returns nothing if the id is not found.
        """
    )

    /// Detail-level read — was caller-allowlisted on Android. Approximated with required authentication.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(
        title: "Bookmark ID",
        description: "The unique identifier returned by Search Bookmarks."
    )
    var bookmarkId: String

    @Dependency private var bookmarkRepository: any BookmarkRepository
    @Dependency private var tokenStore: TokenStore

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<BookmarkDetail?> {
        // Android: `requireUserId()` (signed-in gate; the returned id itself is unused here).
        _ = try await requireUserId(tokenStore)
        let detail = await bookmarkRepository.getBookmarkById(id: bookmarkId).map { BookmarkDetail.from($0) }
        return .result(value: detail)
    }
}

// MARK: - 4. addNoteToBookmark
//
// Ports `CurioFunctions.addNoteToBookmark(bookmarkId, note)`. Write — `requiresAuthentication`. Stores
// the note only when non-blank (else clears), and returns the updated summary with the (possibly
// nilled) note applied. Returns nil when the id is unknown.

/// Add or replace the personal annotation note on a bookmark.
///
/// Required workflow: Call Search Bookmarks first to obtain a valid bookmark id.
struct AddNoteToBookmarkIntent: AppIntent {

    static let title: LocalizedStringResource = "Add Note To Bookmark"

    static let description = IntentDescription(
        """
        Add or replace the personal annotation note on a bookmark. Pass an empty string to clear an \
        existing note. Call Search Bookmarks first to obtain a valid bookmark id. Returns nothing if \
        the id is not found.
        """
    )

    /// Write function — was caller-allowlisted on Android. Approximated with required authentication.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(
        title: "Bookmark ID",
        description: "The unique identifier returned by Search Bookmarks."
    )
    var bookmarkId: String

    @Parameter(
        title: "Note",
        description: "The note text to attach. Pass an empty string to clear an existing note."
    )
    var note: String

    @Dependency private var bookmarkRepository: any BookmarkRepository
    @Dependency private var tokenStore: TokenStore

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<BookmarkSummary?> {
        try await requireAgentWritesAllowed(tokenStore)
        // Android: `val stored = getBookmarkById(bookmarkId) ?: return@withContext null`.
        guard let stored = await bookmarkRepository.getBookmarkById(id: bookmarkId) else {
            return .result(value: nil)
        }
        // `note.takeIf { it.isNotBlank() }` — blank (whitespace-only) clears to nil.
        let cleaned = note.isBlankNote ? nil : note
        await bookmarkRepository.updateNotes(id: bookmarkId, notes: cleaned)
        // `stored.copy(notes = cleaned).toSummary()` — note is not part of the summary projection, but
        // the copy is faithfully reproduced so any future summary field derived from notes stays correct.
        let updated = stored.copyingNotes(cleaned)
        return .result(value: BookmarkSummary.from(updated))
    }
}

// MARK: - 5. toggleFavorite
//
// Ports `CurioFunctions.toggleFavorite(bookmarkId, favorite = true)`. Write — `requiresAuthentication`.
// Sets the favorite flag and returns the updated summary, or nil if the id is unknown.

/// Star or unstar a bookmark.
///
/// Required workflow: Call Search Bookmarks first to obtain a valid bookmark id.
struct ToggleFavoriteIntent: AppIntent {

    static let title: LocalizedStringResource = "Toggle Favorite"

    static let description = IntentDescription(
        """
        Star or unstar a bookmark. Call Search Bookmarks first to obtain a valid bookmark id. Returns \
        nothing if the id is not found.
        """
    )

    /// Write function — was caller-allowlisted on Android. Approximated with required authentication.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(
        title: "Bookmark ID",
        description: "The unique identifier returned by Search Bookmarks."
    )
    var bookmarkId: String

    @Parameter(
        title: "Favorite",
        description: "True to star; false to remove the star.",
        default: true
    )
    var favorite: Bool

    @Dependency private var bookmarkRepository: any BookmarkRepository
    @Dependency private var tokenStore: TokenStore

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<BookmarkSummary?> {
        try await requireAgentWritesAllowed(tokenStore)
        guard let stored = await bookmarkRepository.getBookmarkById(id: bookmarkId) else {
            return .result(value: nil)
        }
        await bookmarkRepository.setFavorite(id: bookmarkId, isFavorite: favorite)
        // `stored.copy(isFavorite = favorite).toSummary()`.
        let updated = stored.copyingFavorite(favorite)
        return .result(value: BookmarkSummary.from(updated))
    }
}

// MARK: - 6. exportCitation
//
// Ports `CurioFunctions.exportCitation(bookmarkId)`. Export function — NOT allowlist-gated on Android
// (it never called `requireAllowedCaller`), so it stays freely discoverable (default
// `authenticationPolicy`). Returns the BibTeX string, or nil for tweet-only / unresolved sources.

/// Export a BibTeX citation for a resolved academic source.
///
/// Only bookmarks with a resolved primary source (arXiv, DOI, GitHub, Hugging Face) produce BibTeX
/// output. Tweet-only bookmarks return nothing. Required workflow: Call Search Bookmarks first.
struct ExportCitationIntent: AppIntent {

    static let title: LocalizedStringResource = "Export Citation"

    static let description = IntentDescription(
        """
        Export a BibTeX citation for a resolved academic source. Only bookmarks with a resolved \
        primary source (arXiv, DOI, GitHub, Hugging Face) produce BibTeX output. Tweet-only bookmarks \
        return nothing. Call Search Bookmarks first to obtain a valid bookmark id.
        """
    )

    @Parameter(
        title: "Bookmark ID",
        description: "The unique identifier returned by Search Bookmarks."
    )
    var bookmarkId: String

    @Dependency private var bookmarkRepository: any BookmarkRepository

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String?> {
        // Android: `val bookmark = getBookmarkById(bookmarkId) ?: return@withContext null;
        //           BibtexExporter.toBibtex(bookmark)`.
        guard let bookmark = await bookmarkRepository.getBookmarkById(id: bookmarkId) else {
            return .result(value: nil)
        }
        return .result(value: BibtexExporter.toBibtex(bookmark))
    }
}

// MARK: - 7–9. ChronosFlow handoff intents
//
// Ports the three ChronosFlow `@AppFunction`s added to `CurioFunctions.kt` (`remindToReadLater`,
// `captureToChronosInbox`, `createChronosTask`). Each is write-gated (`requireAgentWritesAllowed`),
// requires ChronosFlow to be installed (`requireChronosFlow`), and hands the bookmark to the
// companion planner app through `ChronosFlowBridge`.
//
// Result mapping: Android returns a structured `ChronosHandoffResult(success, message, reminderAt)`.
// App Intents' natural analogue is the outcome sentence (returned + spoken via `ProvidesDialog`),
// with denials thrown as `LocalizedError`s — the same information reaches the agent, including the
// ISO-8601 reminder instant, which is embedded in the returned message when a reminder was set.
// The not-found case returns `nil`, mirroring the Kotlin `?: return null`.

/// Shared availability gate — Android `requireChronosFlow()`.
@MainActor
private func requireChronosFlow() throws {
    if !ChronosFlowBridge.isAvailable() {
        throw CurioIntentError.chronosFlowNotInstalled
    }
}

/// Best URL to hand off: the bookmark's link, else its raw text (Android `Bookmark.bestUrl()`).
private func chronosBestUrl(_ bookmark: Bookmark) -> String? {
    bookmark.url.flatMap { $0.isBlankNote ? nil : $0 }
        ?? (bookmark.text.isBlankNote ? nil : bookmark.text)
}

/// Best title to hand off (Android `Bookmark.bestTitle()`).
private func chronosBestTitle(_ bookmark: Bookmark) -> String? {
    (bookmark.sourceTitle ?? bookmark.title).flatMap { $0.isBlankNote ? nil : $0 }
}

/// Save a bookmark to ChronosFlow's reading list ("remind me to read later").
///
/// Required workflow: Call Search Bookmarks first to obtain a valid bookmark id.
struct RemindToReadLaterIntent: AppIntent {

    static let title: LocalizedStringResource = "Remind Me To Read Later"

    static let description = IntentDescription(
        """
        Save a bookmark to the ChronosFlow planner's reading list. When Remind In Minutes is \
        provided, ChronosFlow also schedules a reminder notification that many minutes from now \
        (e.g. 60 for "in an hour", 1440 for "tomorrow"). Requires the ChronosFlow app. Call Search \
        Bookmarks first to obtain a valid bookmark id. Returns nothing if the id is not found.
        """
    )

    /// Write-equivalent handoff — gated like the other write intents.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(
        title: "Bookmark ID",
        description: "The unique identifier returned by Search Bookmarks."
    )
    var bookmarkId: String

    @Parameter(
        title: "Remind In Minutes",
        description: "Optional minutes from now to fire a read-later reminder. Leave empty for no reminder."
    )
    var remindInMinutes: Int?

    @Dependency private var bookmarkRepository: any BookmarkRepository
    @Dependency private var tokenStore: TokenStore
    @Dependency private var chronosFlowBridge: ChronosFlowBridge

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String?> {
        try await requireAgentWritesAllowed(tokenStore)
        try requireChronosFlow()
        guard let bookmark = await bookmarkRepository.getBookmarkById(id: bookmarkId) else {
            return .result(value: nil)
        }
        guard let url = chronosBestUrl(bookmark) else {
            return .result(value: "This bookmark has no link to read later.")
        }
        // Android: `remindInMinutes?.takeIf { it > 0 }?.let { now + it * 60_000L }`.
        let reminderAt: Int64? = remindInMinutes
            .flatMap { $0 > 0 ? $0 : nil }
            .map { Int64(Date().timeIntervalSince1970 * 1000) + Int64($0) * 60_000 }
        do {
            try await chronosFlowBridge.sendToReadingList(
                url: url,
                title: chronosBestTitle(bookmark),
                reminderAtEpochMillis: reminderAt,
                notes: bookmark.notes
            )
            let message: String
            if let reminderAt {
                let iso = ISO8601DateFormatter().string(
                    from: Date(timeIntervalSince1970: Double(reminderAt) / 1000)
                )
                message = "Saved to ChronosFlow reading list with a reminder at \(iso)."
            } else {
                message = "Saved to ChronosFlow reading list."
            }
            return .result(value: message)
        } catch {
            return .result(value: "ChronosFlow declined the item: \(error.localizedDescription)")
        }
    }
}

/// Capture a bookmark into ChronosFlow's quick-capture inbox for later triage.
///
/// Required workflow: Call Search Bookmarks first to obtain a valid bookmark id.
struct CaptureToChronosInboxIntent: AppIntent {

    static let title: LocalizedStringResource = "Capture To ChronosFlow Inbox"

    static let description = IntentDescription(
        """
        Capture a bookmark into the ChronosFlow planner's quick-capture inbox for later triage. \
        Requires the ChronosFlow app. Call Search Bookmarks first to obtain a valid bookmark id. \
        Returns nothing if the id is not found.
        """
    )

    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(
        title: "Bookmark ID",
        description: "The unique identifier returned by Search Bookmarks."
    )
    var bookmarkId: String

    @Dependency private var bookmarkRepository: any BookmarkRepository
    @Dependency private var tokenStore: TokenStore
    @Dependency private var chronosFlowBridge: ChronosFlowBridge

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String?> {
        try await requireAgentWritesAllowed(tokenStore)
        try requireChronosFlow()
        guard let bookmark = await bookmarkRepository.getBookmarkById(id: bookmarkId) else {
            return .result(value: nil)
        }
        // Android: `listOfNotNull(bestTitle, bestUrl ?: text).distinct().joinToString("\n").ifBlank { text }`.
        var parts: [String] = []
        if let title = chronosBestTitle(bookmark) { parts.append(title) }
        parts.append(chronosBestUrl(bookmark) ?? bookmark.text)
        var seen = Set<String>()
        let joined = parts.filter { seen.insert($0).inserted }.joined(separator: "\n")
        let text = joined.isBlankNote ? bookmark.text : joined
        do {
            try await chronosFlowBridge.captureToInbox(text)
            return .result(value: "Captured to ChronosFlow inbox.")
        } catch {
            return .result(value: "ChronosFlow declined the item: \(error.localizedDescription)")
        }
    }
}

/// Create a follow-up task in ChronosFlow from a bookmark (e.g. "follow up on this paper").
///
/// Required workflow: Call Search Bookmarks first to obtain a valid bookmark id.
struct CreateChronosTaskIntent: AppIntent {

    static let title: LocalizedStringResource = "Create ChronosFlow Task"

    static let description = IntentDescription(
        """
        Create a follow-up task in the ChronosFlow planner from a bookmark. The task title defaults \
        to the bookmark's title when omitted. Requires the ChronosFlow app. Call Search Bookmarks \
        first to obtain a valid bookmark id. Returns nothing if the id is not found.
        """
    )

    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(
        title: "Bookmark ID",
        description: "The unique identifier returned by Search Bookmarks."
    )
    var bookmarkId: String

    @Parameter(
        title: "Title",
        description: "Optional task title. Defaults to the bookmark's title when omitted."
    )
    var title: String?

    @Dependency private var bookmarkRepository: any BookmarkRepository
    @Dependency private var tokenStore: TokenStore
    @Dependency private var chronosFlowBridge: ChronosFlowBridge

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String?> {
        try await requireAgentWritesAllowed(tokenStore)
        try requireChronosFlow()
        guard let bookmark = await bookmarkRepository.getBookmarkById(id: bookmarkId) else {
            return .result(value: nil)
        }
        // Android: `title?.trim()?.takeIf { it.isNotEmpty() } ?: bestTitle() ?: text.take(80)`.
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskTitle = (trimmedTitle?.isEmpty == false ? trimmedTitle! : nil)
            ?? chronosBestTitle(bookmark)
            ?? String(bookmark.text.prefix(80))
        do {
            try await chronosFlowBridge.createTask(
                title: taskTitle,
                notes: bookmark.summary ?? bookmark.notes,
                url: chronosBestUrl(bookmark)
            )
            return .result(value: "Created a task in ChronosFlow.")
        } catch {
            return .result(value: "ChronosFlow declined the item: \(error.localizedDescription)")
        }
    }
}

// MARK: - Entity queries (AppEntity.defaultQuery)
//
// `BookmarkSummary` / `BookmarkDetail` are declared `AppEntity` in `CurioFunctionModels.swift`, but
// `AppEntity` requires a `static var defaultQuery` — supplied here (DESIGN §11 Platform row
// `CurioIntents.swift` lists `BookmarkEntity` / `BookmarkQuery` as `EntityStringQuery`). The queries
// resolve an entity back from its stable string `id` (the same id `searchBookmarks` hands out), so the
// Shortcuts / Siri UI can round-trip a previously-returned bookmark into a later intent — the iOS
// analogue of the Android "call searchBookmarks first to obtain a valid bookmarkId" workflow.
//
// Both queries are backed by the same `BookmarkRepository.getBookmarkById(id:)` the intents use. They
// are read-only resolvers (no auth gate — id resolution is the discovery surface), mirroring the
// Android read paths. `suggestedEntities()` is intentionally NOT overridden: the Android functions
// never enumerated the whole index for suggestion, and doing so could leak the full library into the
// system UI — resolution stays id-driven only.

/// `EntityStringQuery` for `BookmarkSummary`: resolves summaries from their string ids. Ports the
/// implicit "id → bookmark" lookup the Android detail/note/favorite/export functions performed via
/// `getBookmarkById`.
struct BookmarkSummaryQuery: EntityStringQuery {

    @Dependency private var bookmarkRepository: any BookmarkRepository

    /// Resolve by exact `id` (`EntityQuery` requirement). Skips ids with no stored bookmark.
    func entities(for identifiers: [BookmarkSummary.ID]) async throws -> [BookmarkSummary] {
        var found: [BookmarkSummary] = []
        for id in identifiers {
            if let bookmark = await bookmarkRepository.getBookmarkById(id: id) {
                found.append(BookmarkSummary.from(bookmark))
            }
        }
        return found
    }

    /// Resolve by a free-text query string (`EntityStringQuery` requirement). Reuses the same
    /// keyword search the `SearchBookmarksIntent` exposes, scoped to the signed-in user; returns empty
    /// when signed out (resolution must never throw the user out of the Shortcuts editor).
    func entities(matching string: String) async throws -> [BookmarkSummary] {
        guard let userId = await tokenStore.getUserId() else { return [] }
        return await bookmarkRepository.searchBookmarks(userId: userId, query: string)
            .map { BookmarkSummary.from($0) }
    }

    @Dependency private var tokenStore: TokenStore
}

/// `EntityStringQuery` for `BookmarkDetail`: resolves full detail records from their string ids.
struct BookmarkDetailQuery: EntityStringQuery {

    @Dependency private var bookmarkRepository: any BookmarkRepository

    func entities(for identifiers: [BookmarkDetail.ID]) async throws -> [BookmarkDetail] {
        var found: [BookmarkDetail] = []
        for id in identifiers {
            if let bookmark = await bookmarkRepository.getBookmarkById(id: id) {
                found.append(BookmarkDetail.from(bookmark))
            }
        }
        return found
    }

    func entities(matching string: String) async throws -> [BookmarkDetail] {
        guard let userId = await tokenStore.getUserId() else { return [] }
        return await bookmarkRepository.searchBookmarks(userId: userId, query: string)
            .map { BookmarkDetail.from($0) }
    }

    @Dependency private var tokenStore: TokenStore
}

extension BookmarkSummary {
    /// Satisfies the `AppEntity` requirement left open by `CurioFunctionModels.swift`.
    static var defaultQuery: BookmarkSummaryQuery { BookmarkSummaryQuery() }
}

extension BookmarkDetail {
    /// Satisfies the `AppEntity` requirement left open by `CurioFunctionModels.swift`.
    static var defaultQuery: BookmarkDetailQuery { BookmarkDetailQuery() }
}

// MARK: - App Shortcuts provider
//
// Surfaces the discovery / write intents to Spotlight / Siri / Shortcuts. The phrases are concise
// English triggers; `\(.applicationName)` ties them to Curio. Mirrors the "operational patterns" KDoc
// on `CurioFunctions` (search first to obtain an id, then act on it). Named `CurioShortcuts` per
// DESIGN §11 Platform row.

struct CurioShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SearchBookmarksIntent(),
            phrases: [
                "Search \(.applicationName)",
                "Search my \(.applicationName) bookmarks",
                "Find research in \(.applicationName)"
            ],
            shortTitle: "Search Bookmarks",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: AddBookmarkIntent(),
            phrases: [
                "Add a bookmark to \(.applicationName)",
                "Save this to \(.applicationName)"
            ],
            shortTitle: "Add Bookmark",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: ExportCitationIntent(),
            phrases: [
                "Export a citation from \(.applicationName)",
                "Get a BibTeX citation from \(.applicationName)"
            ],
            shortTitle: "Export Citation",
            systemImageName: "text.quote"
        )
    }
}

// MARK: - Domain copy helpers
//
// `Bookmark` is an immutable value type with a single explicit memberwise `init`. Kotlin's `copy(...)`
// is reproduced here for the exact two fields the intents mutate (`notes`, `isFavorite`), preserving the
// `stored.copy(...).toSummary()` semantics from `CurioFunctions.kt`. Kept `fileprivate` so they don't
// leak a partial `copy` surface into the rest of the app (the full domain `Bookmark` has 30 fields).

private extension Bookmark {

    /// Reproduces `bookmark.copy(notes = newNotes)`.
    func copyingNotes(_ newNotes: String?) -> Bookmark {
        Bookmark(
            id: id, text: text, createdAt: createdAt, userId: userId,
            title: title, url: url, summary: summary, tags: tags, category: category,
            imageUrl: imageUrl, ocrText: ocrText, isOcrScheduled: isOcrScheduled, isAnalyzed: isAnalyzed,
            sourceType: sourceType, sourceId: sourceId, sourceTitle: sourceTitle,
            sourceAuthors: sourceAuthors, sourceAbstract: sourceAbstract, sourceExtra: sourceExtra,
            referenceCount: referenceCount, entities: entities, isDeepAnalyzed: isDeepAnalyzed,
            deepSummary: deepSummary, isFavorite: isFavorite, isSavedForLater: isSavedForLater,
            authorName: authorName, authorUsername: authorUsername, imageAltText: imageAltText,
            spaceId: spaceId, notes: newNotes
        )
    }

    /// Reproduces `bookmark.copy(isFavorite = newFavorite)`.
    func copyingFavorite(_ newFavorite: Bool) -> Bookmark {
        Bookmark(
            id: id, text: text, createdAt: createdAt, userId: userId,
            title: title, url: url, summary: summary, tags: tags, category: category,
            imageUrl: imageUrl, ocrText: ocrText, isOcrScheduled: isOcrScheduled, isAnalyzed: isAnalyzed,
            sourceType: sourceType, sourceId: sourceId, sourceTitle: sourceTitle,
            sourceAuthors: sourceAuthors, sourceAbstract: sourceAbstract, sourceExtra: sourceExtra,
            referenceCount: referenceCount, entities: entities, isDeepAnalyzed: isDeepAnalyzed,
            deepSummary: deepSummary, isFavorite: newFavorite, isSavedForLater: isSavedForLater,
            authorName: authorName, authorUsername: authorUsername, imageAltText: imageAltText,
            spaceId: spaceId, notes: notes
        )
    }
}

// MARK: - Blank-string helper
//
// Mirrors Kotlin `String.isNotBlank()` (whitespace-only counts as blank) for the
// `note.takeIf { it.isNotBlank() }` clear semantics. Named distinctly to avoid colliding with the
// `isBlankQuery` helper in `SearchController.swift`.

private extension String {
    /// `true` when the string is empty or only whitespace (Kotlin `isBlank()`).
    var isBlankNote: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
