import Foundation
import os

/// Background stale-link cleanup. Direct port of `background/BookmarkSweeperWorker.kt` (scheduled by
/// `BookmarkSweeperScheduler` — Android replaced its old foreground `Service` loop with a periodic
/// WorkManager job, explicitly mirroring this iOS BGTask design).
///
/// This `actor` performs **exactly one bounded cycle** per invocation and `BackgroundTaskCoordinator`
/// re-arms the next cycle via a self-resubmitted BGTask (+6h) — the same "periodicity owned by the
/// scheduler, not an in-process loop" shape as the Android worker's 6h `PeriodicWorkRequest`.
///
/// What a cycle does (preserved verbatim):
/// - reads **all** bookmarks on the device, across users (a deliberately device-wide sweep — the
///   Android service used `getAllBookmarksDirect()`, CONVENTIONS §6 "device-wide sweeps");
/// - keeps only rows with a non-blank URL, capped at `MAX_CHECKS_PER_CYCLE = 50`, paced by
///   `INTER_REQUEST_DELAY_MS = 250` between requests so a large library can't fire a burst of HEADs;
/// - issues a quick HEAD request per URL with a 5s connect/read timeout;
/// - **deletes a bookmark ONLY on a DEFINITIVE dead link (HTTP 404 or 410)**. Any thrown error /
///   connection failure / other status leaves the bookmark intact — a transient offline blip must
///   never silently delete the user's data (CONVENTIONS §9 "Definitive-vs-transient deletion");
/// - mirrors each deletion to Firestore (best-effort; a Firestore failure is logged, not fatal).
///
/// PRIVACY RULE (CONVENTIONS §9): NO AI enrichment (summarize / classify / tag) runs here — that calls
/// the xAI Grok cloud API and may only run in the foreground with the user present. This actor performs
/// offline maintenance only, with no third-party content processing.
///
/// `actor` per CONVENTIONS §5; never logs secrets / bodies (§3).
actor LinkSweeper {

    /// Cloud-delete seam so the sweeper can be exercised in tests with an in-memory store and no
    /// Firestore handle. `FirebaseSyncManager` conforms for production.
    protocol CloudMirror: Sendable {
        func deleteBookmarks(ids: [String]) async
    }

    private let store: BookmarkStore
    private let cloudMirror: CloudMirror
    private let session: URLSession

    private static let logger = Logger(subsystem: "com.curio.app", category: "BookmarkSweeper")

    // MARK: - Constants (companion object)

    /// Bound the work per cycle so a large library can't fire a burst of HEADs.
    private static let maxChecksPerCycle = 50
    /// Pace requests between HEAD checks. Mirrors `INTER_REQUEST_DELAY_MS = 250L`.
    private static let interRequestDelayMs: UInt64 = 250
    /// Quick HEAD-check connect/read timeout. Mirrors OkHttp `connectTimeout(5s)` / `readTimeout(5s)`.
    private static let requestTimeout: TimeInterval = 5

    init(store: BookmarkStore, firebaseSyncManager: FirebaseSyncManager) {
        self.init(store: store, cloudMirror: firebaseSyncManager)
    }

    /// Test seam: inject the cloud mirror and session directly.
    init(
        store: BookmarkStore,
        cloudMirror: CloudMirror,
        session: URLSession? = nil
    ) {
        self.store = store
        self.cloudMirror = cloudMirror

        // A dedicated session mirroring the sweeper's own short-timeout OkHttpClient (independent of
        // the app's primary/metadata sessions). HEAD checks are cheap; 5s connect + 5s overall.
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = Self.requestTimeout
            config.timeoutIntervalForResource = Self.requestTimeout
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    /// Performs one bounded sweep cycle. Port of the body of `startSweeperLoop`'s `while` block (a
    /// single iteration). The 6h cadence is handled by the BGTask scheduler, not here.
    ///
    /// - Parameter isStopped: cancellation probe (the Android service's `isRunning` flag); checked at
    ///   the head of each iteration so the cycle stops promptly when the BGTask expires.
    func runOneCycle(
        isStopped: @Sendable () -> Bool = { false },
        onProgress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) async {
        Self.logger.debug("Background bookmarks sweeping and link validation cycle started…")

        // Bound the work: only rows with a URL, capped per cycle, paced between requests. Device-wide
        // (all users) exactly like the Android `getAllBookmarksDirect()` sweep.
        let toCheck = Array(await store.getAllBookmarksDirect()
            .filter { bookmark in
                // Mirrors Kotlin `!it.url.isNullOrBlank()` — nil OR blank (whitespace-only) is skipped.
                guard let u = bookmark.url else { return false }
                return !u.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .prefix(Self.maxChecksPerCycle))

        let total = toCheck.count
        for (index, entity) in toCheck.enumerated() {
            if isStopped() { break }
            onProgress(index, total)
            guard let urlString = entity.url else { continue }

            // Only delete on a DEFINITIVE dead link (404/410). A connection failure is usually
            // transient (device offline / DNS hiccup) and must NOT delete the user's bookmark — doing
            // so was silent data loss whenever the device was offline.
            if await checkUrlIsBroken(urlString) {
                Self.logger.warning("Dead bookmark link (404/410 on HEAD and GET). Removing.")
                await store.deleteBookmarks(ids: [entity.id])
                // Best-effort cloud mirror of the deletion; a Firestore failure is logged, not fatal.
                await cloudMirror.deleteBookmarks(ids: [entity.id])

                // NOTE: AI enrichment (summarize / classify / tag) is intentionally NOT run here. It
                // calls the xAI Grok cloud API, so per Curio's privacy model it must only run on a
                // visible screen with the user present — never from background work. Enrichment is
                // triggered from the foreground. This sweep performs offline maintenance only.
            }

            // Pace between requests so a large library can't fire a burst of HEADs.
            try? await Task.sleep(nanoseconds: Self.interRequestDelayMs * 1_000_000)
        }
    }

    /// Returns `true` ONLY for a link confirmed dead by BOTH a HEAD and a confirming GET on
    /// HTTP 404/410. Any transport error (connection refused / unresolved host / offline) is
    /// TRANSIENT and treated as intact (`false`) so a temporary network blip never deletes the
    /// user's bookmark. Port of `checkUrlIsBroken`.
    ///
    /// The GET confirmation exists because some servers/CDNs answer 404 to HEAD while serving
    /// GET normally — deletion is irreversible, so a single ambiguous verdict must not decide it.
    ///
    /// Resilient: never throws — logs + returns `false` on any failure (CONVENTIONS §3).
    private func checkUrlIsBroken(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        guard await headVerdict(url) == true else { return false }

        // HEAD said 404/410 — confirm with a GET before destroying data.
        var get = URLRequest(url: url)
        get.httpMethod = "GET"
        get.timeoutInterval = Self.requestTimeout
        do {
            // Inspect the status only; the byte stream is dropped without draining, so large
            // bodies transfer nothing meaningful.
            let (bytes, response) = try await session.bytes(for: get)
            guard let http = response as? HTTPURLResponse else { return false }
            if (200..<300).contains(http.statusCode) || http.statusCode == 206 { return false }
            let confirmed = http.statusCode == 404 || http.statusCode == 410
            if !confirmed { return false }
            _ = bytes // stream abandoned; connection closes when the sequence deallocates
            return true
        } catch {
            // A failing GET after a dead HEAD is ambiguous — keep the bookmark.
            Self.logger.debug("GET confirmation failed for dead-link check; keeping bookmark.")
            return false
        }
    }

    /// HEAD probe: `true` only for 404/410, `false` for anything else (including transport errors).
    private func headVerdict(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = Self.requestTimeout

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            let code = http.statusCode
            return code == 404 || code == 410
        } catch {
            // Connection refused / unresolved host / offline are TRANSIENT — treat as intact.
            return false
        }
    }
}

extension FirebaseSyncManager: LinkSweeper.CloudMirror {}
