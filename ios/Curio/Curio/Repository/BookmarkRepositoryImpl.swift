import Foundation
import Combine
import os

/// Offline-first single source of truth for bookmarks + Spaces. Direct port of
/// `class BookmarkRepositoryImpl : BookmarkRepository` in `data/repo/BookmarkRepositoryImpl.kt`.
///
/// This is the heaviest data-layer file: reactive streams, the 3-phase X sync (Firebase pull → X
/// paginated fetch → Firebase push), the serialized OAuth refresh, 429 backoff, best-effort cloud
/// mirror, Spaces / Smart-Spaces, source persistence, embeddings, deep analysis, and curation.
///
/// Concurrency model (CONVENTIONS §5, §11; DESIGN §7):
/// - The repository is an **`actor`**. Its isolation replaces the Kotlin `Mutex` (OAuth refresh)
///   and `ConcurrentHashMap` (`cursors`) — both become plain actor-isolated state.
/// - Heavy stores/clients are themselves actors (`BookmarkStore`/`SpaceStore` are `@ModelActor`s,
///   the API clients and `FirebaseSyncManager` are actors), so this actor mostly orchestrates.
/// - Reactive reads (`getBookmarksFlow` / `getSpacesFlow`) are exposed as Combine `AnyPublisher`s
///   backed by per-`userId` `CurrentValueSubject`s that re-emit on every write the repository
///   performs. The repository is the single offline-first writer path (all mutations funnel through
///   it), so a repo-write-driven re-emit faithfully reproduces Room's hot `Flow` re-emission without
///   a separate SwiftData change observer (CONVENTIONS §11).
/// - The fire-and-forget cloud mirror (`mirrorScope` in Kotlin) becomes a tracked tree of detached
///   `Task`s, cancelled in `close()` / `deinit`. A timed-out / failed mirror must never mask a real
///   X error (X-authoritative precedence).
///
/// Fidelity invariants preserved (CONVENTIONS §7, §10, Repository cross-cutting):
/// - merge-bias asymmetry (cloud pull = "fresh" wins for content fields but keeps local
///   curation/embedding; X fetch = local wins for AI-enriched fields);
/// - X-authoritative sync precedence (a Firebase-only "success" never masks an X failure);
/// - single-use rotated refresh token (serialize + re-read stored token + persist rotated);
/// - 429 epoch-seconds math in two places (`Int64`, `> 1_000_000` ⇒ absolute else relative,
///   fallback `900`);
/// - per-page durability + cursor resume;
/// - notes / embeddings / incrementReferenceCount / rule application are NOT mirrored to cloud;
/// - rethrow `CancellationError` everywhere a Kotlin `if (e is CancellationException) throw e` sat.
actor BookmarkRepositoryImpl: BookmarkRepository {

    // MARK: - Dependencies

    private let api: XBookmarksApi
    private let store: BookmarkStore
    private let spaceStore: SpaceStore
    private let tokenStore: TokenStore
    private let firebaseSyncManager: FirebaseSyncManager
    private let authApi: XAuthApi

    private static let logger = Logger(subsystem: "com.curio.app", category: "BookmarkRepo")

    // MARK: - Actor-isolated state (replaces Kotlin ConcurrentHashMap / Mutex)

    /// Per-user pagination cursor saved when a sync stops at the page cap so a follow-up "load more"
    /// can resume. Actor isolation replaces the Kotlin `ConcurrentHashMap<String, String>`.
    private var cursors: [String: String] = [:]

    /// Lock guarding the two subject caches. The flow getters are `nonisolated` (a
    /// `CurrentValueSubject`/`AnyPublisher` is not `Sendable` and so cannot cross the actor boundary,
    /// which a non-`nonisolated` requirement would force), so the caches live outside actor isolation
    /// and every access — from `nonisolated` getters and actor-isolated writers alike — goes through
    /// this lock.
    private nonisolated let subjectLock = NSLock()

    /// Reactive bookmark subjects, one per observed `userId`. Re-emit on every repository write.
    private nonisolated(unsafe) var bookmarkSubjects: [String: CurrentValueSubject<[Bookmark], Never>] = [:]

    /// Reactive Space subjects, one per observed `userId`. Re-emit on every repository write.
    private nonisolated(unsafe) var spaceSubjects: [String: CurrentValueSubject<[Space], Never>] = [:]

    /// Tracked detached mirror / delete tasks, cancelled in `close()` / `deinit` (replaces the Kotlin
    /// `mirrorScope` supervisor scope). Keyed by a per-spawn id so each task can remove ITSELF on
    /// completion — `Task` exposes no `isFinished`, so a "filter out finished" sweep can't work and
    /// the map would otherwise grow unbounded (Kotlin's completed `launch` jobs are released by the
    /// runtime).
    private var backgroundTasks: [UUID: Task<Void, Never>] = [:]

    /// `true` once `close()` has run — new mirror tasks are no longer spawned (the Kotlin
    /// `mirrorScope.cancel()` makes subsequent `launch`es no-ops).
    private var isClosed = false

    // MARK: - Constants (companion object)

    private enum Const {
        /// X API allows up to 100 bookmarks per page (default of 10 was the "only 10 fetched" bug).
        static let xPageSize = 100
        /// Safety cap so a single sync can't loop forever or blow the X rate-limit window.
        static let maxPagesPerSync = 10
        /// 429 backoff retry ceiling.
        static let maxRateLimitRetries = 3
        static let rateLimitBackoffBaseMs: Int64 = 1_000
        static let rateLimitMaxWaitMs: Int64 = 30_000
        /// Firebase (mock backend in this build) call bound — never blocks the X sync.
        static let firebaseTimeoutMs: Int64 = 15_000
        /// Prefix for IDs of manually-added bookmarks (not from the X API).
        static let manualBookmarkPrefix = "manual_"
        /// Prefix for IDs of user-created Spaces.
        static let spaceIdPrefix = "space_"
        /// CSV delimiter for the tag column.
        static let tagDelimiter = ","
        /// Maximum characters in the extracted title snippet.
        static let titleSnippetLimit = 50
    }

    // MARK: - Init / teardown

    init(
        api: XBookmarksApi,
        store: BookmarkStore,
        spaceStore: SpaceStore,
        tokenStore: TokenStore,
        firebaseSyncManager: FirebaseSyncManager,
        authApi: XAuthApi
    ) {
        self.api = api
        self.store = store
        self.spaceStore = spaceStore
        self.tokenStore = tokenStore
        self.firebaseSyncManager = firebaseSyncManager
        self.authApi = authApi
    }

    deinit {
        for task in backgroundTasks.values { task.cancel() }
    }

    /// Cancels the background mirror tasks. Must be called when the repository is no longer needed
    /// (e.g. from `AppEnvironment.close()`) to avoid leaking detached work. Port of Kotlin `close()`
    /// (`mirrorScope.cancel()`).
    func close() {
        isClosed = true
        for task in backgroundTasks.values { task.cancel() }
        backgroundTasks.removeAll()
    }

    // MARK: - Reads / streams

    nonisolated func getBookmarksFlow(userId: String) -> AnyPublisher<[Bookmark], Never> {
        bookmarkSubject(for: userId).eraseToAnyPublisher()
    }

    func getBookmarkById(id: String) async -> Bookmark? {
        await store.getBookmarkById(id: id)
    }

    /// Searches across text/title/summary/OCR for `userId`. Blank query ⇒ all bookmarks newest-first
    /// (the store treats blank as "all", matching the Kotlin `if (query.isBlank()) getBookmarks else
    /// search`). Plain `suspend` (no `Result`) ⇒ `async` (no throws).
    func searchBookmarks(userId: String, query: String) async -> [Bookmark] {
        // The Kotlin impl branched on `query.isBlank()`; `BookmarkStore.search` already returns all
        // rows for a blank query, but we keep the explicit branch for byte-identical behavior on a
        // whitespace-only query (which `isEmpty` would NOT treat as blank).
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return await store.getBookmarks(userId: userId)
        }
        return await store.search(userId: userId, query: query)
    }

    // MARK: - Sync / clear

    /// 3-phase X sync. Throws `RateLimitError` on 429 (the only typed failure surfaced here). The
    /// Kotlin `Result<Unit>` collapses to `async throws` (no return) per CONVENTIONS §3.
    func syncBookmarks(userId: String, fetchNextPage: Bool) async throws {
        var firebaseSyncSuccess = false
        var xSyncSuccess = false
        var lastError: Error?
        // X is the source of truth; Firebase is a best-effort mirror. Track the X failure separately
        // so a Firebase pull that merely timed out can't mask a real X sync error and report a false
        // "success" to the user.
        var xSyncError: Error?

        // 1. Firebase pull (bounded — a hung Firestore call must not block the X sync).
        //    `pullBookmarks` and the store ops are resilient/non-throwing, so the Kotlin try/catch
        //    (which set `lastError` on a pull failure) collapses to a plain sequence: with these
        //    clients the catch could only fire on cancellation, which surfaces through the `await`s.
        //    The wrapper's `nil` distinctly signals *timeout* (mirrors `cloudBookmarks == null`); a
        //    successful-but-empty pull is `[]`.
        let cloudBookmarks: [Bookmark]? = try await withTimeout(Const.firebaseTimeoutMs) {
            await self.firebaseSyncManager.pullBookmarks(userId: userId)
        }
        if cloudBookmarks == nil {
            Self.logger.warning("Firebase pull timed out after \(Const.firebaseTimeoutMs)ms; continuing with X sync")
        } else if let cloud = cloudBookmarks, !cloud.isEmpty {
            let freshIds = cloud.map { $0.id }
            let existing = await store.getBookmarksByIds(ids: freshIds)
            let existingMap = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            // Merge unconditionally, preferring non-null *cloud (fresh)* fields but keeping local
            // curation / embedding / Space / notes (TODO last-writer-wins is not yet possible —
            // no `updatedAt` column). This is the cloud-pull half of the merge-bias asymmetry.
            let merged = cloud.map { fresh -> Bookmark in
                guard let existing = existingMap[fresh.id] else { return fresh }
                return mergeCloudPull(fresh: fresh, existing: existing, userId: userId)
            }
            await store.insertBookmarks(merged)
        }
        firebaseSyncSuccess = true

        // 2. X Bookmarks API — paginate through ALL pages (follow meta.next_token until exhausted or
        //    the per-sync page cap), pulling up to X_PAGE_SIZE per request.
        do {
            let initialToken = await tokenStore.getAccessToken()
            if let initialToken {
                // A full sync starts from the beginning; "load more" resumes from the saved cursor.
                var paginationToken: String? = fetchNextPage ? cursors[userId] : nil
                if fetchNextPage && paginationToken == nil {
                    // Nothing left to page through.
                    xSyncSuccess = true
                } else {
                    var currentToken = initialToken
                    var pagesFetched = 0
                    var totalFetched = 0
                    repeat {
                        // Fetch a page, transparently refreshing an expired access token on 401. The
                        // refreshed token carries to later pages.
                        let page = try await getBookmarksWithAuthRetry(
                            accessToken: currentToken,
                            userId: userId,
                            paginationToken: paginationToken
                        )
                        currentToken = page.accessToken
                        let response = page.response

                        // includes-join lookups: media_key -> media, author_id -> user.
                        let mediaByKey = Dictionary(
                            (response.includes?.media ?? []).map { ($0.mediaKey, $0) },
                            uniquingKeysWith: { a, _ in a }
                        )
                        let usersById = Dictionary(
                            (response.includes?.users ?? []).map { ($0.id, $0) },
                            uniquingKeysWith: { a, _ in a }
                        )

                        let entities: [Bookmark] = (response.data ?? []).map { dto in
                            let epochMs = dto.createdAt.map { parseRfc3339ToEpoch($0) }
                                ?? Self.nowMillis()
                            // Prefer the long-form note_tweet body over the truncated `text`.
                            let bodyText: String = {
                                if let nt = dto.noteTweet?.text, !nt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    return nt
                                }
                                return dto.text
                            }()
                            // Prefer the API's expanded (de-t.co'd) URL; fall back to a regex scan.
                            let expandedUrl = dto.entities?.urls?
                                .lazy
                                .compactMap { u -> String? in
                                    guard let e = u.expandedUrl,
                                          !e.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                                    return e
                                }
                                .first
                            let urlAndTitle = extractUrlAndTitle(bodyText)
                            let imageUrl: String? = dto.attachments?.mediaKeys?
                                .lazy
                                .compactMap { key -> String? in
                                    guard let media = mediaByKey[key] else { return nil }
                                    return media.url ?? media.previewImageUrl
                                }
                                .first
                            let altText: String? = dto.attachments?.mediaKeys?
                                .lazy
                                .compactMap { key -> String? in
                                    guard let a = mediaByKey[key]?.altText,
                                          !a.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                                    return a
                                }
                                .first
                            let author = dto.authorId.flatMap { usersById[$0] }
                            return Bookmark(
                                id: dto.id,
                                text: bodyText,
                                createdAt: epochMs,
                                userId: userId,
                                title: urlAndTitle.title,
                                url: expandedUrl ?? urlAndTitle.url,
                                imageUrl: imageUrl,
                                authorName: author?.name,
                                authorUsername: author?.username,
                                imageAltText: altText
                            )
                        }

                        let freshIds = entities.map { $0.id }
                        let existing = await store.getBookmarksByIds(ids: freshIds)
                        let existingMap = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                        // X fetch half of the merge-bias asymmetry: fresh wins for media/author, but
                        // ALL AI-enriched + curation + Space + notes fields keep the LOCAL value.
                        let merged = entities.map { fresh -> Bookmark in
                            guard let existing = existingMap[fresh.id] else { return fresh }
                            return mergeXFetch(fresh: fresh, existing: existing)
                        }
                        // Persist each page as it arrives so partial progress survives a later
                        // rate-limit or network error mid-pagination.
                        if !merged.isEmpty { await store.insertBookmarks(merged) }
                        totalFetched += merged.count
                        pagesFetched += 1

                        paginationToken = response.meta?.nextToken
                    } while paginationToken != nil && pagesFetched < Const.maxPagesPerSync

                    // Save the cursor if we stopped at the page cap so a follow-up sync can resume;
                    // clear it once we've reached the end.
                    if let token = paginationToken {
                        cursors[userId] = token
                    } else {
                        cursors.removeValue(forKey: userId)
                    }

                    Self.logger.debug("X sync fetched \(totalFetched) bookmarks across \(pagesFetched) page(s)")
                    xSyncSuccess = true
                }
            } else {
                xSyncSuccess = true
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as APIError {
            if let status = error.statusCode {
                Self.logger.error("HTTP \(status) on X API")
                if status == 429 {
                    let secondsLeft = Self.rateLimitSecondsFromHeader(error.headers["x-rate-limit-reset"])
                    // The 429 path notifies subscribers of any per-page durability writes already
                    // made before throwing the typed rate-limit signal.
                    notifyChange(userId: userId)
                    throw RateLimitError(resetTimeSeconds: secondsLeft)
                }
            }
            lastError = error
            xSyncError = error
        } catch {
            Self.logger.error("X API sync error: \(error.localizedDescription)")
            lastError = error
            xSyncError = error
        }

        // 3. Firebase push (bounded for the same reason as the pull). The store read and the resilient
        //    (non-throwing) `pushBookmarks` cannot throw, so the Kotlin try/catch collapses to a plain
        //    sequence here — a cooperative cancellation surfaces through the `await`s. The `withTimeout`
        //    bound returns `nil` on timeout (swallowed, matching `withTimeoutOrNull`).
        let local = await store.getBookmarksByUserDirect(userId: userId)
        if !local.isEmpty {
            _ = try await withTimeout(Const.firebaseTimeoutMs) {
                await self.firebaseSyncManager.pushBookmarks(userId: userId, bookmarks: local)
                return ()
            }
        }

        // Re-emit the merged library after a sync so subscribers refresh.
        notifyChange(userId: userId)

        // Result resolution (X-authoritative precedence).
        if xSyncSuccess {
            return
        } else if let xSyncError {
            // X is authoritative: if it failed, surface that even if the cloud mirror "succeeded".
            throw xSyncError
        } else if firebaseSyncSuccess {
            return
        } else {
            throw lastError ?? SyncError.failed
        }
    }

    func clearAll(userId: String) async {
        await store.clearBookmarks(userId: userId)
        cursors.removeValue(forKey: userId)
        notifyChange(userId: userId)
    }

    // MARK: - Analysis / OCR

    func updateAnalysisAndTags(
        id: String,
        summary: String?,
        category: String?,
        tags: [String],
        entities: String?
    ) async {
        let csv = tags.isEmpty ? nil : tags.joined(separator: Const.tagDelimiter)
        await store.updateAnalysis(
            id: id, summary: summary, tags: csv, category: category,
            isAnalyzed: true, entities: entities
        )
        mirrorToCloud(id)
        notifyChange(forBookmarkId: id)
    }

    func updateOcrContent(id: String, ocrText: String?, isOcrScheduled: Bool) async {
        await store.updateOcr(id: id, ocrText: ocrText, isOcrScheduled: isOcrScheduled)
        mirrorToCloud(id)
        notifyChange(forBookmarkId: id)
    }

    // MARK: - CRUD

    /// Manually adds a bookmark (assigns a `manual_<uuid>` id). Throws on failure (collapses Kotlin
    /// `Result<Bookmark>`).
    func addBookmark(userId: String, text: String) async throws -> Bookmark {
        do {
            let urlAndTitle = extractUrlAndTitle(text)
            let bookmark = Bookmark(
                id: "\(Const.manualBookmarkPrefix)\(UUID().uuidString)",
                text: text,
                createdAt: Self.nowMillis(),
                userId: userId,
                title: urlAndTitle.title,
                url: urlAndTitle.url
            )
            await store.insertBookmarks([bookmark])
            // Mirror fire-and-forget: the local insert already succeeded; a blocking inline push
            // would hang the add whenever Firestore is slow/unreachable (offline).
            mirrorToCloud(bookmark.id)
            notifyChange(userId: userId)
            return bookmark
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.error("Failed to add bookmark: \(error.localizedDescription)")
            throw error
        }
    }

    func deleteBookmarks(ids: [String]) async {
        // Capture the (userId, id) pairs BEFORE the local delete so the fire-and-forget cloud delete
        // can target the right per-user paths (mirrors the Kotlin pre-fetch of entities).
        var toDelete: [(userId: String, id: String)] = []
        var affectedUsers: Set<String> = []
        for id in ids {
            if let b = await store.getBookmarkById(id: id) {
                toDelete.append((b.userId, b.id))
                affectedUsers.insert(b.userId)
            }
        }
        await store.deleteBookmarks(ids: ids)
        // Snapshot into immutable locals so the `@Sendable` background closure captures values, not
        // the mutable `var`s (Swift 6 strict concurrency).
        let deletions = toDelete
        // Fire-and-forget cloud delete — never block the local delete on a slow/unreachable Firestore.
        spawnBackground { [firebaseSyncManager] in
            for entry in deletions {
                await firebaseSyncManager.deleteBookmarks(ids: [entry.id])
            }
        }
        for user in affectedUsers { notifyChange(userId: user) }
    }

    func updateCategoryForIds(ids: [String], category: String) async {
        await store.updateCategoryForIds(ids: ids, category: category)
        for id in ids { mirrorToCloud(id) }
        notifyChange(forBookmarkIds: ids)
    }

    func updateCreatedAt(id: String, createdAt: Int64) async {
        await store.updateCreatedAt(id: id, createdAt: createdAt)
        mirrorToCloud(id)
        notifyChange(forBookmarkId: id)
    }

    /// Atomically swaps two bookmarks' ordering timestamps inside a single DB transaction (the store
    /// performs both mutations then exactly one `save()` — TOCTOU guarantee preserved).
    func swapCreatedAt(id1: String, ts1: Int64, id2: String, ts2: Int64) async {
        await store.swapCreatedAt(id1: id1, ts1: ts1, id2: id2, ts2: ts2)
        mirrorToCloud(id1)
        mirrorToCloud(id2)
        notifyChange(forBookmarkIds: [id1, id2])
    }

    // MARK: - Phase 8 — source resolution

    func updateSourceInfo(
        id: String,
        sourceType: SourceType?,
        sourceId: String?,
        sourceTitle: String?,
        sourceAuthors: String?,
        sourceAbstract: String?,
        sourceExtra: String?,
        referenceCount: Int
    ) async {
        await store.updateSourceInfo(
            id: id,
            sourceType: sourceType?.rawValue,
            sourceId: sourceId,
            sourceTitle: sourceTitle,
            sourceAuthors: sourceAuthors,
            sourceAbstract: sourceAbstract,
            sourceExtra: sourceExtra,
            referenceCount: referenceCount
        )
        mirrorToCloud(id)
        notifyChange(forBookmarkId: id)
    }

    /// Increments the reference count for every row sharing `sourceId` for `userId`. NOT mirrored to
    /// cloud (matches Kotlin — no `mirrorToCloud` call).
    func incrementReferenceCount(sourceId: String, userId: String) async {
        await store.incrementReferenceCount(sourceId: sourceId, userId: userId)
        notifyChange(userId: userId)
    }

    /// Collapses duplicate bookmarks that resolved to the same primary source: keeps the oldest
    /// (`min createdAt`) as canonical with `referenceCount = group.size`, bulk-deletes the rest.
    func deduplicateBySource(userId: String) async {
        let withSource = await store.getBookmarksWithSourceId(userId: userId)
        // Group by sourceId (nil keys are possible if the store returns rows with sourceId == nil —
        // but the store already filters `sourceId != nil`; we still mirror the Kotlin nil-guard).
        var grouped: [String?: [Bookmark]] = [:]
        for b in withSource { grouped[b.sourceId, default: []].append(b) }

        var allDuplicateIds: [String] = []
        for (sourceId, group) in grouped {
            guard let sourceId, group.count > 1 else { continue }
            guard let canonical = group.min(by: { $0.createdAt < $1.createdAt }) else { continue }
            let duplicateIds = group.filter { $0.id != canonical.id }.map { $0.id }
            await store.updateSourceInfo(
                id: canonical.id,
                sourceType: canonical.sourceType?.rawValue,
                sourceId: canonical.sourceId,
                sourceTitle: canonical.sourceTitle,
                sourceAuthors: canonical.sourceAuthors,
                sourceAbstract: canonical.sourceAbstract,
                sourceExtra: canonical.sourceExtra,
                referenceCount: group.count
            )
            allDuplicateIds.append(contentsOf: duplicateIds)
            Self.logger.debug("Deduped \(sourceId): kept \(canonical.id), removing \(duplicateIds.count) duplicate(s)")
        }
        // Single bulk delete — one DB op instead of N separate deletes in the loop.
        if !allDuplicateIds.isEmpty { await store.deleteBookmarks(ids: allDuplicateIds) }
        notifyChange(userId: userId)
    }

    // MARK: - Phase 10 — embeddings

    /// NOT mirrored to cloud (matches Kotlin — embeddings stay on-device).
    func updateEmbedding(id: String, embedding: Data) async {
        await store.updateEmbedding(id: id, embedding: embedding)
    }

    /// Bulk-write embeddings in a single store transaction (exactly one `save()`). NOT mirrored.
    func updateEmbeddings(updates: [(String, Data)]) async {
        await store.updateEmbeddings(updates: updates)
    }

    func getBookmarksWithEmbeddings(userId: String) async -> [(String, Data)] {
        let rows = await store.getIdsAndEmbeddings(userId: userId)
        return rows.compactMap { row in
            guard let bytes = row.embedding else { return nil }
            return (row.id, bytes)
        }
    }

    func getUnembeddedAnalyzed(userId: String) async -> [Bookmark] {
        await store.getUnembedded(userId: userId)
    }

    func getAllUnembedded(userId: String) async -> [Bookmark] {
        await store.getAllUnembedded(userId: userId)
    }

    func clearAllEmbeddings() async {
        await store.clearAllEmbeddings()
    }

    // MARK: - Phase 9 — deep analysis

    func updateDeepSummary(id: String, deepSummary: String) async {
        await store.updateDeepSummary(id: id, deepSummary: deepSummary, isDeepAnalyzed: true)
        mirrorToCloud(id)
        notifyChange(forBookmarkId: id)
    }

    // MARK: - Phase 12 — personal curation

    func setFavorite(id: String, isFavorite: Bool) async {
        await store.updateFavorite(id: id, isFavorite: isFavorite)
        mirrorToCloud(id)
        notifyChange(forBookmarkId: id)
    }

    func setSavedForLater(id: String, isSavedForLater: Bool) async {
        await store.updateSavedForLater(id: id, isSavedForLater: isSavedForLater)
        mirrorToCloud(id)
        notifyChange(forBookmarkId: id)
    }

    /// Sets (or clears, when nil/blank) the user's personal note. Local-only — intentionally NOT
    /// mirrored to cloud.
    func updateNotes(id: String, notes: String?) async {
        // Blank in → cleared (nil) so an empty editor removes the note rather than storing "".
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (trimmed?.isEmpty == false) ? trimmed : nil
        await store.updateNotes(id: id, notes: normalized)
        notifyChange(forBookmarkId: id)
    }

    // MARK: - Spaces

    nonisolated func getSpacesFlow(userId: String) -> AnyPublisher<[Space], Never> {
        spaceSubject(for: userId).eraseToAnyPublisher()
    }

    func createSpace(
        userId: String,
        name: String,
        color: Int64,
        icon: String,
        description: String,
        rules: SpaceRules,
        isPinned: Bool
    ) async -> Space {
        let space = Space(
            id: "\(Const.spaceIdPrefix)\(UUID().uuidString)",
            userId: userId,
            name: name,
            color: color,
            icon: icon,
            createdAt: Self.nowMillis(),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            isPinned: isPinned,
            // New Spaces sort newest-first by default (sortIndex 0); pinning/manual order layer on top.
            sortIndex: 0,
            rules: rules
        )
        await spaceStore.upsertSpace(space)
        notifySpaceChange(userId: userId)
        return space
    }

    func updateSpace(
        id: String,
        name: String,
        color: Int64,
        icon: String,
        description: String,
        rules: SpaceRules,
        isPinned: Bool
    ) async {
        guard let existing = await spaceStore.getSpaceById(id: id) else { return }
        let updated = Space(
            id: existing.id,
            userId: existing.userId,
            name: name,
            color: color,
            icon: icon,
            createdAt: existing.createdAt,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            isPinned: isPinned,
            sortIndex: existing.sortIndex,
            rules: rules
        )
        await spaceStore.upsertSpace(updated)
        notifySpaceChange(userId: existing.userId)
    }

    /// Deletes a Space. NO FK cascade — membership is manually nulled first so no bookmark points at
    /// a removed Space (CONVENTIONS §6).
    func deleteSpace(id: String) async {
        // Resolve owner BEFORE deletion so we can re-emit the right user's bookmark + Space streams.
        let owner = await spaceStore.getSpaceById(id: id)?.userId
        // Unfile members first so no bookmark points at a removed Space.
        await store.clearSpace(spaceId: id)
        await spaceStore.deleteSpace(id: id)
        if let owner {
            notifyChange(userId: owner)
            notifySpaceChange(userId: owner)
        }
    }

    func setSpacePinned(id: String, pinned: Bool) async {
        let owner = await spaceStore.getSpaceById(id: id)?.userId
        await spaceStore.setPinned(id: id, pinned: pinned)
        if let owner { notifySpaceChange(userId: owner) }
    }

    func assignToSpace(ids: [String], spaceId: String?) async {
        await store.updateSpaceForIds(ids: ids, spaceId: spaceId)
        notifyChange(forBookmarkIds: ids)
    }

    // MARK: - Smart Spaces — rule-driven auto-filing

    /// Files `bookmark` into the FIRST auto-file Smart Space whose rules match it, returning that
    /// Space's id (or nil). Only considers currently-unfiled bookmarks — a manual filing is never
    /// overridden.
    func fileByRules(bookmark: Bookmark) async -> String? {
        // Never override a manual filing; AI category Spaces are fair game for Smart-Space rules.
        if !CategorySpaces.bookmarkEligibleForRuleFiling(bookmark.spaceId) { return nil }
        let spaces = await spaceStore.getSpacesDirect(userId: bookmark.userId)
        guard let match = spaces
            .filter({ $0.rules.autoFile && $0.rules.matches(bookmark) })
            .max(by: { $0.rules.matchScore(bookmark) < $1.rules.matchScore(bookmark) })
        else {
            return nil
        }
        await store.updateSpaceForIds(ids: [bookmark.id], spaceId: match.id)
        notifyChange(userId: bookmark.userId)
        return match.id
    }

    /// Files every unfiled bookmark matching `spaceId`'s rules into it, REGARDLESS of the Space's
    /// auto-file toggle (the explicit "Apply rules now" action). Returns the number filed.
    func applySpaceRules(spaceId: String) async -> Int {
        guard let space = await spaceStore.getSpaceById(id: spaceId) else { return 0 }
        let rules = space.rules
        if !rules.isActive { return 0 }
        // Explicit action: file eligible bookmarks this Space's rules match, ignoring autoFile.
        // Eligible = unfiled or in an AI category Space — not bookmarks the user filed manually.
        let candidates = await store.getRuleFilingCandidates(userId: space.userId)
        let matches = candidates.filter { rules.matches($0) }.map { $0.id }
        if !matches.isEmpty {
            await store.updateSpaceForIds(ids: matches, spaceId: spaceId)
            notifyChange(userId: space.userId)
        }
        return matches.count
    }

    /// Backfill across all of `userId`'s auto-file Smart Spaces: every eligible bookmark is filed into
    /// the FIRST Space whose rules match. Idempotent; safe on every login. Returns the number filed.
    func applyRulesToLibrary(userId: String) async -> Int {
        let smartSpaces = await spaceStore.getSpacesDirect(userId: userId)
            .filter { $0.rules.autoFile && $0.rules.isActive }
        if smartSpaces.isEmpty { return 0 }
        var filed = 0
        let candidates = await store.getRuleFilingCandidates(userId: userId)
        for bookmark in candidates {
            guard let target = smartSpaces
                .filter({ $0.rules.matches(bookmark) })
                .max(by: { $0.rules.matchScore(bookmark) < $1.rules.matchScore(bookmark) })
            else { continue }
            await store.updateSpaceForIds(ids: [bookmark.id], spaceId: target.id)
            filed += 1
        }
        if filed > 0 { notifyChange(userId: userId) }
        return filed
    }

    /// Ensures the canonical default Space for an AI `category` exists for `userId` (creating it from
    /// `CategorySpaces` the first time) and returns its id (deterministic so re-analysis is
    /// idempotent). Returns nil when `category` is blank. An existing Space (incl. a renamed one) is
    /// left untouched.
    func ensureCategorySpace(userId: String, category: String) async -> String? {
        let key = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key.isEmpty { return nil }
        // Deterministic id so re-analysis is idempotent and never spawns duplicates.
        let id = "\(CategorySpaces.spaceIdPrefix)\(userId)_\(key)"
        if await spaceStore.getSpaceById(id: id) == nil {
            let meta = CategorySpaces.forCategory(key)
            let space = Space(
                id: id,
                userId: userId,
                name: meta.name,
                color: meta.color,
                icon: meta.icon,
                createdAt: Self.nowMillis()
            )
            await spaceStore.upsertSpace(space)
            notifySpaceChange(userId: userId)
        }
        return id
    }

    /// Backfills Space membership for already-analysed bookmarks: any item with an AI category but no
    /// Space yet is filed into its category's default Space (created on demand). Idempotent.
    func backfillCategorySpaces(userId: String) async {
        let all = await store.getBookmarksByUserDirect(userId: userId)
        // Unfiled (spaceId nil/blank) AND has a non-blank category, grouped by trimmed-lowercased key.
        var unfiledByCategory: [String: [Bookmark]] = [:]
        for b in all {
            let isUnfiled = (b.spaceId == nil || b.spaceId == "")
            guard isUnfiled else { continue }
            guard let category = b.category,
                  !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let key = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            unfiledByCategory[key, default: []].append(b)
        }
        var touched = false
        for (category, items) in unfiledByCategory {
            guard let spaceId = await ensureCategorySpace(userId: userId, category: category) else { continue }
            await store.updateSpaceForIds(ids: items.map { $0.id }, spaceId: spaceId)
            touched = true
        }
        if touched {
            notifyChange(userId: userId)
            notifySpaceChange(userId: userId)
        }
    }

    // MARK: - Semantic auto-organisation (embedding-driven)

    func organizeByEmbedding(userId: String) async -> OrganizeResult {
        let rows = await store.getSpaceEmbeddings(userId: userId).compactMap { row -> (String, String?, [Float])? in
            guard let emb = Self.toOrganizerEmbedding(row.embedding) else { return nil }
            return (row.id, row.spaceId, emb)
        }
        let unfiled = rows.filter { $0.1 == nil }.map { ($0.0, $0.2) }
        if unfiled.isEmpty { return .empty }

        let filedBySpace = Dictionary(grouping: rows.filter { $0.1 != nil }, by: { $0.1! })
        var centroids: [String: [Float]] = [:]
        var memberCounts: [String: Int] = [:]
        for (spaceId, members) in filedBySpace {
            if let centroid = SemanticOrganizer.meanVector(members.map { $0.2 }) {
                centroids[spaceId] = centroid
                memberCounts[spaceId] = members.count
            }
        }

        let plan = SemanticOrganizer.buildPlan(
            unfiled: unfiled,
            spaceCentroids: centroids,
            spaceMemberCounts: memberCounts
        )

        var autoFiled = 0
        let autoBySpace = Dictionary(grouping: plan.autoFile, by: { $0.spaceId })
        for (spaceId, items) in autoBySpace {
            await store.updateSpaceForIds(ids: items.map { $0.bookmarkId }, spaceId: spaceId)
            autoFiled += items.count
        }

        var newSpaces = 0
        var takenNames = Set(
            (await spaceStore.getSpacesDirect(userId: userId)).map { $0.name.lowercased() }
        )
        for (index, cluster) in plan.clusters.enumerated() {
            let members = await store.getBookmarksByIds(ids: cluster.bookmarkIds)
            let name = Self.deriveClusterName(members: members, taken: takenNames, index: index)
            takenNames.insert(name.lowercased())
            let palette = Self.clusterPalette[index % Self.clusterPalette.count]
            let space = await createSpace(
                userId: userId,
                name: name,
                color: palette.color,
                icon: palette.icon,
                description: "Auto-created from similar bookmarks",
                rules: .empty,
                isPinned: false
            )
            await store.updateSpaceForIds(ids: cluster.bookmarkIds, spaceId: space.id)
            newSpaces += 1
        }

        if autoFiled > 0 || newSpaces > 0 {
            notifyChange(userId: userId)
            notifySpaceChange(userId: userId)
        }

        let nameById = Dictionary(
            uniqueKeysWithValues: (await spaceStore.getSpacesDirect(userId: userId)).map { ($0.id, $0.name) }
        )
        let suggestions = plan.suggestions.compactMap { a -> SpaceSuggestion? in
            guard let nm = nameById[a.spaceId] else { return nil }
            return SpaceSuggestion(bookmarkId: a.bookmarkId, spaceId: a.spaceId, spaceName: nm, score: a.score)
        }
        return OrganizeResult(autoFiled: autoFiled, newSpaces: newSpaces, suggestions: suggestions)
    }

    // MARK: - Private — cloud mirror

    /// Fire-and-forget cloud mirror for a single bookmark id. Port of Kotlin `mirrorToCloud`. Spawns
    /// a detached, tracked task (no-op after `close()`).
    private func mirrorToCloud(_ id: String) {
        spawnBackground { [store, firebaseSyncManager] in
            if let b = await store.getBookmarkById(id: id) {
                await firebaseSyncManager.pushBookmark(userId: b.userId, bookmark: b)
            }
        }
    }

    /// Spawns a tracked detached task; logs+swallows (resilient), rethrow-aware of cancellation. The
    /// task removes itself from `backgroundTasks` on completion. No-op once `isClosed`.
    private func spawnBackground(_ body: @escaping @Sendable () async -> Void) {
        guard !isClosed else { return }
        let id = UUID()
        let task = Task.detached { [weak self] in
            await body()
            await self?.removeBackgroundTask(id)
        }
        // No suspension between the spawn above and this insert (actor-isolated sync code), so the
        // task's self-removal — which must hop back onto this actor — can never precede the insert.
        backgroundTasks[id] = task
    }

    /// Removes a completed mirror task so the tracking map doesn't grow unbounded.
    private func removeBackgroundTask(_ id: UUID) {
        backgroundTasks[id] = nil
    }

    // MARK: - Private — auth retry / refresh (single-use rotated token; actor-serialized)

    /// One fetched page + the (possibly refreshed) access token to reuse for later pages. Port of the
    /// Kotlin private `data class BookmarksPage`.
    private struct BookmarksPage {
        let response: BookmarksResponse
        let accessToken: String
    }

    /// Fetches one page. On 401 refreshes the access token ONCE then retries. On 429 retries with
    /// exponential backoff honoring `x-rate-limit-reset` when sooner than the ceiling, else rethrows
    /// so the caller can surface a `RateLimitError`. Returns the (possibly refreshed) token.
    private func getBookmarksWithAuthRetry(
        accessToken: String,
        userId: String,
        paginationToken: String?
    ) async throws -> BookmarksPage {
        var token = accessToken
        var attempt = 0
        var alreadyRefreshed = false
        while true {
            try Task.checkCancellation()
            do {
                let response = try await api.getBookmarks(
                    authHeader: "Bearer \(token)",
                    userId: userId,
                    maxResults: Const.xPageSize,
                    paginationToken: paginationToken
                )
                return BookmarksPage(response: response, accessToken: token)
            } catch let error as APIError {
                guard let status = error.statusCode else { throw error }
                if status == 401 {
                    if alreadyRefreshed { throw error } // give up on second 401
                    alreadyRefreshed = true
                    // Refresh the access token once, then retry on the new token. A refresh that
                    // "failed" because THIS task was cancelled must surface as cancellation (the
                    // Kotlin path rethrows CancellationException), not as the original 401.
                    guard let refreshed = await refreshAccessTokenSafely(staleToken: token) else {
                        try Task.checkCancellation()
                        throw error
                    }
                    token = refreshed
                } else if status == 429 && attempt < Const.maxRateLimitRetries {
                    let resetWaitMs = Self.rateLimitWaitMs(error.headers["x-rate-limit-reset"])
                    // Exponential backoff, but never wait less than the server's reset window.
                    let backoffMs = max(Const.rateLimitBackoffBaseMs << attempt, resetWaitMs)
                    if backoffMs > Const.rateLimitMaxWaitMs { throw error } // too long to block — surface it
                    Self.logger.warning("429 rate-limited; backoff \(backoffMs)ms (attempt \(attempt + 1))")
                    try await Task.sleep(nanoseconds: UInt64(max(0, backoffMs)) * 1_000_000)
                    attempt += 1
                } else {
                    throw error
                }
            }
        }
    }

    /// Milliseconds to wait for a 429, derived from the `x-rate-limit-reset` header (bug-24: parse as
    /// `Int64`; absolute epoch when `> 1_000_000`, else relative seconds).
    private static func rateLimitWaitMs(_ header: String?) -> Int64 {
        guard let header, let resetEpochSeconds = Int64(header) else { return 0 }
        if resetEpochSeconds > 1_000_000 {
            let resetMs = resetEpochSeconds * 1000
            return max(0, resetMs - nowMillis())
        } else {
            return resetEpochSeconds * 1000
        }
    }

    /// Seconds-left value surfaced in `RateLimitError` from the 429 reset header. Mirrors the Kotlin
    /// inline math in `syncBookmarks`: absolute epoch (`> 1_000_000`) ⇒ remaining seconds (fallback
    /// 900 if absent/past); relative positive ⇒ as-is; else fallback 900.
    private static func rateLimitSecondsFromHeader(_ header: String?) -> Int64 {
        let resetEpochSeconds = header.flatMap { Int64($0) } ?? 0
        if resetEpochSeconds > 1_000_000 {
            let resetMs = resetEpochSeconds * 1000
            let delayMs = max(0, resetMs - nowMillis())
            // Convert back to seconds for the caller; fall back to 900s if absent/in the past.
            return delayMs > 0 ? delayMs / 1000 : 900
        } else if resetEpochSeconds > 0 {
            return resetEpochSeconds
        } else {
            return 900
        }
    }

    /// The in-flight refresh, if any. Concurrent 401 handlers await this single task instead of
    /// each running their own refresh — the iOS analogue of the Kotlin `refreshMutex` critical
    /// section. Actor isolation alone is NOT enough: it is released at every `await`, so without
    /// this slot two concurrent 401s could both pass the stale-token check and both consume the
    /// single-use rotated refresh token (the second consumption kills the session).
    private var inFlightRefresh: Task<String?, Never>?

    /// Refreshes the token exactly once per herd and collapses a thundering herd: if the stored
    /// token was already rotated while we were busy, return that freshly-stored token instead of
    /// consuming the (now-invalid) refresh token a second time. Late arrivals join the in-flight
    /// refresh and share its result, exactly like Kotlin's `refreshMutex.withLock` losers.
    private func refreshAccessTokenSafely(staleToken: String) async -> String? {
        if let existing = inFlightRefresh {
            return await existing.value
        }
        // Unstructured on purpose: a cancelled caller must not cancel the refresh other callers
        // are awaiting (the caller re-checks its own cancellation after joining).
        let task = Task<String?, Never> {
            let current = await tokenStore.getAccessToken()
            if let current, !current.isEmpty, current != staleToken {
                return current
            }
            return await refreshAccessToken()
        }
        inFlightRefresh = task
        let result = await task.value
        inFlightRefresh = nil
        return result
    }

    /// Exchanges the stored refresh token for a fresh access token and persists the rotated
    /// credentials. Returns the new access token, or nil if no refresh token is available or the
    /// refresh fails (the user must re-login).
    private func refreshAccessToken() async -> String? {
        guard let refresh = await tokenStore.getRefreshToken(),
              !refresh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        // X_CLIENT_ID with CLIENT_ID fallback is resolved inside CurioConfig.clientID (DESIGN Auth /
        // Platform). A blank id means OAuth is not configured.
        let clientId = CurioConfig.clientID
        if clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Self.logger.error("No OAuth client ID configured; cannot refresh token")
            return nil
        }
        do {
            let resp = try await authApi.refreshToken(
                grantType: "refresh_token",
                clientId: clientId,
                refreshToken: refresh
            )
            let userId = await tokenStore.getUserId() ?? ""
            // X rotates refresh tokens; persist the new one (fall back to the old if absent).
            await tokenStore.saveTokens(
                accessToken: resp.accessToken,
                refreshToken: resp.refreshToken ?? refresh,
                userId: userId
            )
            Self.logger.debug("X access token refreshed")
            return resp.accessToken
        } catch is CancellationError {
            // The Kotlin code rethrows CancellationException; here `refreshAccessToken` is non-throwing
            // (called from a non-throwing context), so a cancellation is observed as the task being
            // cancelled — return nil and let the surrounding cancellation check surface it.
            return nil
        } catch {
            Self.logger.error("Token refresh failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private — parsing helpers

    /// Shared ISO-8601 / RFC-3339 parser with fractional seconds. Created once (actor-isolated, so no
    /// data race on the non-`Sendable` formatter).
    private let rfc3339Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Fallback ISO-8601 parser WITHOUT fractional seconds (X `created_at` is e.g.
    /// `2021-01-06T18:40:40.000Z` — has fractions — but a no-fraction value must still parse, matching
    /// `java.time.Instant.parse` which accepts both).
    private let rfc3339FormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parses an RFC-3339 timestamp to epoch milliseconds; returns 0 on failure (matches the Kotlin
    /// `Instant.parse(...).toEpochMilli()` / `catch → 0L`).
    private func parseRfc3339ToEpoch(_ iso: String) -> Int64 {
        if let date = rfc3339Formatter.date(from: iso) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        if let date = rfc3339FormatterNoFraction.date(from: iso) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        return 0
    }

    /// Extracts the first URL and a title snippet from free text. Byte-faithful port of the Kotlin
    /// `extractUrlAndTitle` — the SAME regex `https?://[a-zA-Z0-9.-]+(?:/[^\s]*)?`, the SAME
    /// `substringBefore`/`take(50)`/`"..."` ellipsis, and the SAME `"Curio Saved Link"` fallback.
    private func extractUrlAndTitle(_ text: String) -> (title: String?, url: String?) {
        let url = Self.firstUrl(in: text)
        let title: String?
        if let url {
            let before = String(text[..<(text.range(of: url)?.lowerBound ?? text.startIndex)])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !before.isEmpty {
                let snippet = String(before.prefix(Const.titleSnippetLimit))
                title = before.count > Const.titleSnippetLimit ? "\(snippet)..." : snippet
            } else {
                title = "Curio Saved Link"
            }
        } else {
            let snippet = String(text.prefix(Const.titleSnippetLimit))
            title = text.count > Const.titleSnippetLimit ? "\(snippet)..." : snippet
        }
        return (title, url)
    }

    /// First HTTP(S) URL in `text` using the exact Kotlin pattern. `NSRegularExpression` with the
    /// identical pattern keeps the match byte-stable.
    private static func firstUrl(in text: String) -> String? {
        // Pattern identical to Kotlin: "https?://[a-zA-Z0-9.-]+(?:/[^\\s]*)?"
        guard let regex = urlRegex else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let swiftRange = Range(match.range, in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }

    private static let urlRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: "https?://[a-zA-Z0-9.-]+(?:/[^\\s]*)?", options: [])

    /// Current Unix epoch milliseconds (`System.currentTimeMillis()` analogue).
    private static func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    // MARK: - Private — merge bias (asymmetric)

    /// Cloud-pull merge: cloud (fresh) wins for content/AI fields where non-nil, OR-accumulate flags,
    /// but local curation/embedding/Space/notes are kept. Mirrors the Kotlin `fresh.copy(...)` in the
    /// Firebase-pull branch.
    private func mergeCloudPull(fresh: Bookmark, existing: Bookmark, userId: String) -> Bookmark {
        Bookmark(
            id: fresh.id,
            text: fresh.text,
            createdAt: fresh.createdAt,
            userId: userId,
            title: fresh.title,
            url: fresh.url,
            summary: fresh.summary ?? existing.summary,
            tags: fresh.tags.isEmpty ? existing.tags : fresh.tags,
            category: fresh.category ?? existing.category,
            imageUrl: fresh.imageUrl ?? existing.imageUrl,
            ocrText: fresh.ocrText ?? existing.ocrText,
            isOcrScheduled: fresh.isOcrScheduled || existing.isOcrScheduled,
            isAnalyzed: fresh.isAnalyzed || existing.isAnalyzed,
            sourceType: fresh.sourceType ?? existing.sourceType,
            sourceId: fresh.sourceId ?? existing.sourceId,
            sourceTitle: fresh.sourceTitle ?? existing.sourceTitle,
            sourceAuthors: fresh.sourceAuthors ?? existing.sourceAuthors,
            sourceAbstract: fresh.sourceAbstract ?? existing.sourceAbstract,
            sourceExtra: fresh.sourceExtra,
            referenceCount: fresh.referenceCount,
            entities: fresh.entities ?? existing.entities,
            isDeepAnalyzed: fresh.isDeepAnalyzed,
            deepSummary: fresh.deepSummary,
            isFavorite: existing.isFavorite || fresh.isFavorite,
            isSavedForLater: existing.isSavedForLater || fresh.isSavedForLater,
            authorName: fresh.authorName,
            authorUsername: fresh.authorUsername,
            imageAltText: fresh.imageAltText,
            spaceId: existing.spaceId,
            notes: existing.notes
        )
    }

    /// X-fetch merge: fresh wins for media/author, but title/url keep the LOCAL value where present,
    /// and ALL AI-enriched + curation + Space + notes fields keep the LOCAL value (incl. embedding).
    /// Mirrors the Kotlin `fresh.copy(...)` in the X-pagination branch.
    private func mergeXFetch(fresh: Bookmark, existing: Bookmark) -> Bookmark {
        Bookmark(
            id: fresh.id,
            text: fresh.text,
            createdAt: fresh.createdAt,
            userId: fresh.userId,
            title: existing.title ?? fresh.title,
            url: existing.url ?? fresh.url,
            summary: existing.summary,
            tags: existing.tags,
            category: existing.category,
            imageUrl: fresh.imageUrl ?? existing.imageUrl,
            ocrText: existing.ocrText,
            isOcrScheduled: existing.isOcrScheduled,
            isAnalyzed: existing.isAnalyzed,
            sourceType: existing.sourceType,
            sourceId: existing.sourceId,
            sourceTitle: existing.sourceTitle,
            sourceAuthors: existing.sourceAuthors,
            sourceAbstract: existing.sourceAbstract,
            sourceExtra: existing.sourceExtra,
            referenceCount: existing.referenceCount,
            entities: existing.entities,
            isDeepAnalyzed: existing.isDeepAnalyzed,
            deepSummary: existing.deepSummary,
            isFavorite: existing.isFavorite,
            isSavedForLater: existing.isSavedForLater,
            authorName: fresh.authorName ?? existing.authorName,
            authorUsername: fresh.authorUsername ?? existing.authorUsername,
            imageAltText: fresh.imageAltText ?? existing.imageAltText,
            spaceId: existing.spaceId,
            notes: existing.notes
        )
    }

    // MARK: - Private — reactive subjects

    /// Returns (creating + seeding once) the bookmark subject for `userId`. The seed is an
    /// asynchronous store read; the subject starts empty and is populated immediately after creation.
    private nonisolated func bookmarkSubject(for userId: String) -> CurrentValueSubject<[Bookmark], Never> {
        subjectLock.lock()
        if let subject = bookmarkSubjects[userId] {
            subjectLock.unlock()
            return subject
        }
        let subject = CurrentValueSubject<[Bookmark], Never>([])
        bookmarkSubjects[userId] = subject
        subjectLock.unlock()
        // Seed asynchronously (the store actor read can't be awaited synchronously here).
        Task { await self.reloadBookmarks(userId: userId) }
        return subject
    }

    /// Returns (creating + seeding once) the Space subject for `userId`.
    private nonisolated func spaceSubject(for userId: String) -> CurrentValueSubject<[Space], Never> {
        subjectLock.lock()
        if let subject = spaceSubjects[userId] {
            subjectLock.unlock()
            return subject
        }
        let subject = CurrentValueSubject<[Space], Never>([])
        spaceSubjects[userId] = subject
        subjectLock.unlock()
        Task { await self.reloadSpaces(userId: userId) }
        return subject
    }

    /// Re-queries the store and re-emits the user's bookmark list (the hot-flow re-emission). Called
    /// after every repository write touching `userId`'s bookmarks.
    private func notifyChange(userId: String) {
        guard subjectLock.withLock({ bookmarkSubjects[userId] != nil }) else { return }
        Task { await self.reloadBookmarks(userId: userId) }
    }

    /// Re-emits the streams affected by a single bookmark id (resolves its userId then re-queries).
    private func notifyChange(forBookmarkId id: String) {
        Task {
            if let b = await self.store.getBookmarkById(id: id) {
                self.notifyChange(userId: b.userId)
            }
        }
    }

    /// Re-emits the streams affected by a set of bookmark ids (resolves their distinct userIds).
    private func notifyChange(forBookmarkIds ids: [String]) {
        guard !ids.isEmpty else { return }
        Task {
            var users: Set<String> = []
            for id in ids {
                if let b = await self.store.getBookmarkById(id: id) { users.insert(b.userId) }
            }
            for user in users { self.notifyChange(userId: user) }
        }
    }

    /// Re-queries and re-emits the user's Space list.
    private func notifySpaceChange(userId: String) {
        guard subjectLock.withLock({ spaceSubjects[userId] != nil }) else { return }
        Task { await self.reloadSpaces(userId: userId) }
    }

    /// Fetches the user's bookmarks (newest-first) and pushes them onto the subject.
    private func reloadBookmarks(userId: String) async {
        guard let subject = subjectLock.withLock({ bookmarkSubjects[userId] }) else { return }
        let rows = await store.getBookmarks(userId: userId)
        subject.send(rows)
    }

    /// Fetches the user's Spaces (with derived membership counts injected) and pushes them onto the
    /// subject. The `SpaceStore` returns `count = 0` (a transient field); the repository fills the
    /// count via a per-Space bookmark query, matching the Android split where the DAO returns plain
    /// entities and the repository derives counts.
    private func reloadSpaces(userId: String) async {
        guard let subject = subjectLock.withLock({ spaceSubjects[userId] }) else { return }
        let spaces = await spaceStore.getSpacesDirect(userId: userId)
        // Derive membership counts from the user's full bookmark set (one fetch, in-memory tally) so
        // we issue a single store read rather than N.
        let all = await store.getBookmarksByUserDirect(userId: userId)
        var countBySpace: [String: Int] = [:]
        for b in all {
            guard let sid = b.spaceId, !sid.isEmpty else { continue }
            countBySpace[sid, default: 0] += 1
        }
        let withCounts = spaces.map { space -> Space in
            Space(
                id: space.id,
                userId: space.userId,
                name: space.name,
                color: space.color,
                icon: space.icon,
                createdAt: space.createdAt,
                count: countBySpace[space.id] ?? 0,
                description: space.description,
                isPinned: space.isPinned,
                sortIndex: space.sortIndex,
                rules: space.rules
            )
        }
        subject.send(withCounts)
    }
}

// MARK: - Cluster Space naming (ports BookmarkRepositoryImpl.kt helpers)

private extension BookmarkRepositoryImpl {
    struct ClusterPaletteEntry {
        let color: Int64
        let icon: String
    }

    static func toOrganizerEmbedding(_ data: Data) -> [Float]? {
        guard data.count >= 4 else { return nil }
        let emb = VectorSearch.dataToFloatArray(data)
        guard !emb.isEmpty, VectorSearch.normalizeL2(emb) != nil else { return nil }
        return emb
    }

    static let clusterPalette: [ClusterPaletteEntry] = [
        ClusterPaletteEntry(color: 0xFF1E88E5, icon: "hub"),
        ClusterPaletteEntry(color: 0xFF8E24AA, icon: "workspaces"),
        ClusterPaletteEntry(color: 0xFF43A047, icon: "folder"),
        ClusterPaletteEntry(color: 0xFFFF9800, icon: "bolt"),
        ClusterPaletteEntry(color: 0xFF00BCD4, icon: "star"),
        ClusterPaletteEntry(color: 0xFF673AB7, icon: "science"),
        ClusterPaletteEntry(color: 0xFFFF5722, icon: "rocket"),
        ClusterPaletteEntry(color: 0xFF3F51B5, icon: "label"),
    ]

    static let nameStopwords: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "are", "was", "how", "why",
        "new", "using", "use", "via", "into", "your", "our", "you", "https", "http",
        "com", "www", "about", "what", "when", "will", "can", "has", "have"
    ]

    static func deriveClusterName(members: [Bookmark], taken: Set<String>, index: Int) -> String {
        let topTag = members.flatMap { $0.tags }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 2 }
            .map { $0.lowercased() }
            .reduce(into: [String: Int]()) { counts, tag in counts[tag, default: 0] += 1 }
            .max(by: { $0.value < $1.value })?.key

        let base: String
        if let topTag {
            base = topTag.prefix(1).uppercased() + topTag.dropFirst()
        } else if let keyword = topKeyword(members: members) {
            base = keyword
        } else {
            base = "Group \(index + 1)"
        }

        var name = base
        var n = 2
        while taken.contains(name.lowercased()) {
            name = "\(base) \(n)"
            n += 1
        }
        return name
    }

    static func topKeyword(members: [Bookmark]) -> String? {
        let words = members.flatMap { b -> [String] in
            [b.title, b.sourceTitle, b.summary, b.text]
                .compactMap { $0 }
                .joined(separator: " ")
                .components(separatedBy: CharacterSet.letters.inverted)
        }
        .map { $0.lowercased() }
        .filter { $0.count > 3 && !nameStopwords.contains($0) }

        // A trailing closure directly in a `guard let … = reduce(into:) { … }` condition is a parse
        // ambiguity, so bind the frequency map first, then pick the mode.
        let counts = words.reduce(into: [String: Int]()) { counts, w in counts[w, default: 0] += 1 }
        guard let best = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return best.prefix(1).uppercased() + best.dropFirst()
    }
}
