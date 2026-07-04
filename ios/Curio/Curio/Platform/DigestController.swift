import Foundation
import Observation
import os

/// Owns the weekly AI digest: its own `DigestUiState` and the Grok-backed generation over the last 7
/// days of saves. Ported 1:1 from `ui/DigestController.kt`.
///
/// Self-contained (its state isn't shared with sync/analysis), so it extracts cleanly out of
/// `BookmarkViewModel`; the VM facades it so the UI is unchanged.
///
/// CONVENTIONS §4: `@MainActor @Observable final class`; `scope.launch` → `Task`; sealed UI state →
/// a Swift `enum` with associated values switched exhaustively by the view (exact user-facing strings
/// preserved).
@MainActor
@Observable
final class DigestController {

    // MARK: - Injected dependencies

    @ObservationIgnored private let aiAnalyzer: XAiAnalyzer
    @ObservationIgnored private let rawBookmarks: @MainActor () -> [Bookmark]
    /// Mirrors the digest lifecycle into Curio's unified Live Activity ("Preparing your digest…" →
    /// "Your weekly digest is ready"). Optional so tests / previews can omit it.
    @ObservationIgnored private let liveActivityManager: LiveActivityManager?

    // MARK: - Published state

    private(set) var digestState: DigestUiState = .idle

    @ObservationIgnored private var generateTask: Task<Void, Never>?

    @ObservationIgnored private static let logger = Logger(subsystem: "com.curio.app", category: "DigestController")
    /// Last 7 days. Port of `DIGEST_WINDOW_MS = 7L * 24 * 60 * 60 * 1000`.
    @ObservationIgnored private static let digestWindowMs: Int64 = 7 * 24 * 60 * 60 * 1000
    /// Cap tokens/cost per digest. Port of `DIGEST_MAX_ITEMS = 40`.
    @ObservationIgnored private static let digestMaxItems = 40

    init(
        aiAnalyzer: XAiAnalyzer,
        rawBookmarks: @escaping @MainActor () -> [Bookmark],
        liveActivityManager: LiveActivityManager? = nil
    ) {
        self.aiAnalyzer = aiAnalyzer
        self.rawBookmarks = rawBookmarks
        self.liveActivityManager = liveActivityManager
    }

    /// Generates a themed markdown digest of the last 7 days of saves via Grok. Surfaces an explicit
    /// Empty state when nothing was saved this week so the UI never shows a misleading blank digest.
    /// Port of `generate()`.
    func generate() {
        generateTask = Task { [weak self] in
            guard let self else { return }
            self.digestState = .loading
            self.liveActivityManager?.taskStarted(.digest)
            let cutoff = Self.nowMillis() - Self.digestWindowMs
            let recent = self.rawBookmarks().filter { $0.createdAt >= cutoff }
            if recent.isEmpty {
                self.digestState = .empty("No saves in the last 7 days — come back after you've bookmarked something new.")
                self.liveActivityManager?.taskFinished(.digest)
                return
            }
            // itemsBlock: one line per item, capped at DIGEST_MAX_ITEMS, joined by "\n".
            let itemsBlock = recent.prefix(Self.digestMaxItems).map { b -> String in
                // Kotlin: sourceTitle?.takeIf { isNotBlank } ?: title?.takeIf { isNotBlank } ?: text.take(80).trim()
                let title: String
                if let st = b.sourceTitle, !st.isBlankDigest {
                    title = st
                } else if let t = b.title, !t.isBlankDigest {
                    title = t
                } else {
                    // CONVENTIONS §10 char-count: Kotlin `take(80)` is UTF-16 code units; `prefix(80)` on
                    // Character is acceptable for this short, non-byte-sensitive snippet.
                    title = String(b.text.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let cat = (b.category.flatMap { $0.isBlankDigest ? nil : " [\($0)]" }) ?? ""
                let summary = (b.summary.flatMap { $0.isBlankDigest ? nil : " — \($0)" }) ?? ""
                return "- \(title)\(cat)\(summary)"
            }.joined(separator: "\n")

            do {
                let markdown = try await self.aiAnalyzer.generateWeeklyDigest(itemsBlock, count: recent.count)
                self.digestState = .ready(markdown: markdown, count: recent.count)
                self.liveActivityManager?.taskFinished(.digest)
                self.liveActivityManager?.digestReady(itemCount: recent.count)
            } catch {
                Self.logger.warning("Weekly digest failed: \(error.localizedDescription, privacy: .public)")
                self.digestState = .error(humanReadableError(error, context: .ai))
                self.liveActivityManager?.taskFinished(.digest)
            }
        }
    }

    /// Resets the digest card back to its idle (un-generated) state. Port of `dismiss()`.
    func dismiss() { digestState = .idle }

    /// Cancels the in-flight digest generation, if any. On Android the coroutine ran in
    /// `viewModelScope` and was cancelled structurally on VM clear; the owning VM's `close()`
    /// calls this to reproduce that teardown.
    func close() {
        generateTask?.cancel()
        generateTask = nil
    }

    /// `System.currentTimeMillis()` — Unix epoch milliseconds.
    private static func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}

// MARK: - Digest UI state (owned here; the VM/UI read it)
//
// DESIGN lists `DigestUiState` on the BookmarkViewModel surface, but it is wholly owned by the digest
// controller, so it lives here once. `BookmarkViewModel.swift` must NOT redefine it.

/// Sealed state machine for the weekly digest card. Port of the Kotlin `sealed class DigestUiState`.
/// User-facing strings are produced by the controller / surfaced verbatim (CONVENTIONS §4).
enum DigestUiState: Sendable, Equatable {
    case idle
    case loading
    /// Nothing saved in the 7-day window (carries the explanatory message).
    case empty(String)
    /// Generated markdown digest + the number of items it summarised.
    case ready(markdown: String, count: Int)
    /// Generation failed (carries the user-facing error message).
    case error(String)
}

private extension String {
    /// Mirrors Kotlin `String.isBlank()` (whitespace-only ⇒ blank). Named distinctly to avoid
    /// colliding with blank helpers in sibling modules.
    var isBlankDigest: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
