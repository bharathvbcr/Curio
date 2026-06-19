package com.example.data.repo

import android.util.Log
import com.example.data.embedding.VectorSearch.toByteArray
import com.example.data.embedding.VectorSearch.toFloatArray
import com.example.BuildConfig
import com.example.data.local.BookmarkDao
import com.example.data.local.BookmarkEntity
import com.example.data.local.SpaceDao
import com.example.data.local.SpaceEntity
import com.example.domain.model.Space
import com.example.domain.model.SpaceRules
import com.example.data.remote.BookmarksResponse
import com.example.data.remote.TokenStore
import com.example.data.remote.XAuthApi
import com.example.data.remote.XBookmarksApi
import com.example.domain.model.Bookmark
import com.example.domain.model.SourceType
import com.example.domain.repo.BookmarkRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import retrofit2.HttpException
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

class RateLimitException(val resetTimeSeconds: Int) : Exception("X API Rate limit exceeded.")

class BookmarkRepositoryImpl(
    private val api: XBookmarksApi,
    private val dao: BookmarkDao,
    private val spaceDao: SpaceDao,
    private val tokenStore: TokenStore,
    private val firebaseSyncManager: com.example.data.remote.FirebaseSyncManager,
    private val authApi: XAuthApi
) : BookmarkRepository {

    private val cursors = ConcurrentHashMap<String, String>()

    // Cloud mirroring is best-effort and must never block a local write. The mock
    // Firestore backend in this build can hang indefinitely on .set(), which would
    // otherwise leave UI "processing" spinners stuck after the local DB write already
    // completed. We fire pushes on a detached supervisor scope so writes return at
    // local-DB speed and the cloud mirror catches up (or fails) in the background.
    private val mirrorScope = kotlinx.coroutines.CoroutineScope(Dispatchers.IO + kotlinx.coroutines.SupervisorJob())

    /** Fire-and-forget cloud mirror for a single bookmark id. */
    private fun mirrorToCloud(id: String) {
        mirrorScope.launch {
            try {
                dao.getBookmarkById(id)?.let { firebaseSyncManager.pushBookmark(it.userId, it.toDomain()) }
            } catch (e: Exception) { Log.e("BookmarkRepo", "Cloud mirror failed for $id: ${e.message}") }
        }
    }

    companion object {
        // X API allows up to 100 bookmarks per page; default of 10 was the cause of
        // "only 10 bookmarks fetched".
        private const val X_PAGE_SIZE = 100
        // Safety cap so a single sync can't loop forever or blow the X rate-limit window.
        private const val MAX_PAGES_PER_SYNC = 10
        // 429 backoff: retry a rate-limited page a few times with exponential backoff. If the
        // server's x-rate-limit-reset is further out than this ceiling we stop retrying and
        // surface a RateLimitException so the UI can show a countdown instead of blocking.
        private const val MAX_RATE_LIMIT_RETRIES = 3
        private const val RATE_LIMIT_BACKOFF_BASE_MS = 1_000L
        private const val RATE_LIMIT_MAX_WAIT_MS = 30_000L
        // Firebase uses mock credentials in this build; a Firestore call against a
        // non-existent backend can hang indefinitely. Bound it so it can never block
        // the X sync (the cause of "synchronizing loads continuously").
        private const val FIREBASE_TIMEOUT_MS = 15_000L
    }

    override fun getBookmarksFlow(userId: String): Flow<List<Bookmark>> =
        dao.getBookmarks(userId).map { entities -> entities.map { it.toDomain() } }

    override suspend fun getBookmarkById(id: String): Bookmark? = withContext(Dispatchers.IO) {
        dao.getBookmarkById(id)?.toDomain()
    }

    override suspend fun syncBookmarks(userId: String, fetchNextPage: Boolean): Result<Unit> =
        withContext(Dispatchers.IO) {
            var firebaseSyncSuccess = false
            var xSyncSuccess = false
            var lastError: Exception? = null

            // 1. Firebase pull (bounded — a hung Firestore call must not block the X sync)
            try {
                val cloudBookmarks = withTimeoutOrNull(FIREBASE_TIMEOUT_MS) {
                    firebaseSyncManager.pullBookmarks(userId)
                }
                if (cloudBookmarks == null) {
                    Log.w("BookmarkRepo", "Firebase pull timed out after ${FIREBASE_TIMEOUT_MS}ms; continuing with X sync")
                } else if (cloudBookmarks.isNotEmpty()) {
                    val merged = cloudBookmarks.map { cb ->
                        val fresh = BookmarkEntity(
                            id = cb.id, text = cb.text, createdAt = cb.createdAt, userId = userId,
                            title = cb.title, url = cb.url, summary = cb.summary,
                            tags = if (cb.tags.isEmpty()) null else cb.tags.joinToString(","),
                            category = cb.category, imageUrl = cb.imageUrl, ocrText = cb.ocrText,
                            isOcrScheduled = cb.isOcrScheduled, isAnalyzed = cb.isAnalyzed,
                            sourceType = cb.sourceType?.name, sourceId = cb.sourceId,
                            sourceTitle = cb.sourceTitle, sourceAuthors = cb.sourceAuthors,
                            sourceAbstract = cb.sourceAbstract, sourceExtra = cb.sourceExtra,
                            referenceCount = cb.referenceCount, entities = cb.entities,
                            isDeepAnalyzed = cb.isDeepAnalyzed, deepSummary = cb.deepSummary
                        )
                        val existing = dao.getBookmarkById(fresh.id)
                        if (existing != null) {
                            fresh.copy(
                                summary = fresh.summary ?: existing.summary,
                                tags = fresh.tags ?: existing.tags,
                                category = fresh.category ?: existing.category,
                                imageUrl = fresh.imageUrl ?: existing.imageUrl,
                                ocrText = fresh.ocrText ?: existing.ocrText,
                                isOcrScheduled = fresh.isOcrScheduled || existing.isOcrScheduled,
                                isAnalyzed = fresh.isAnalyzed || existing.isAnalyzed,
                                sourceType = fresh.sourceType ?: existing.sourceType,
                                sourceId = fresh.sourceId ?: existing.sourceId,
                                sourceTitle = fresh.sourceTitle ?: existing.sourceTitle,
                                sourceAuthors = fresh.sourceAuthors ?: existing.sourceAuthors,
                                sourceAbstract = fresh.sourceAbstract ?: existing.sourceAbstract,
                                entities = fresh.entities ?: existing.entities,
                                embedding = existing.embedding,
                                isFavorite = existing.isFavorite || fresh.isFavorite,
                                isSavedForLater = existing.isSavedForLater || fresh.isSavedForLater,
                                spaceId = existing.spaceId, notes = existing.notes
                            )
                        } else fresh
                    }
                    dao.insertBookmarks(merged)
                }
                firebaseSyncSuccess = true
            } catch (e: Exception) {
                Log.e("BookmarkRepo", "Firebase pull error: ${e.message}")
                lastError = e
            }

            // 2. X Bookmarks API — paginate through ALL pages.
            // Previously a single request with max_results=10 was issued, which is why only
            // 10 bookmarks were ever fetched. We now follow meta.next_token until exhausted
            // (or the per-sync page cap), pulling up to X_PAGE_SIZE per request.
            try {
                val initialToken = tokenStore.getAccessToken()
                if (initialToken != null) {
                    // A full sync starts from the beginning; "load more" resumes from the
                    // cursor saved when a previous sync stopped at the page cap.
                    var paginationToken: String? = if (fetchNextPage) cursors[userId] else null
                    if (fetchNextPage && paginationToken == null) {
                        // Nothing left to page through.
                        xSyncSuccess = true
                    } else {
                        var currentToken: String = initialToken
                        var pagesFetched = 0
                        var totalFetched = 0
                        do {
                            // Fetch a page, transparently refreshing an expired access token
                            // on 401 (X access tokens expire ~2h; previously this silently
                            // returned nothing). The refreshed token carries to later pages.
                            val page = getBookmarksWithAuthRetry(currentToken, userId, paginationToken)
                            currentToken = page.accessToken
                            val response = page.response

                            // includes-join lookups: media_key -> media, author_id -> user.
                            val mediaByKey = (response.includes?.media ?: emptyList())
                                .associateBy { it.mediaKey }
                            val usersById = (response.includes?.users ?: emptyList())
                                .associateBy { it.id }

                            val entities = (response.data ?: emptyList()).map { dto ->
                                val epochMs = dto.createdAt?.let { parseRfc3339ToEpoch(it) }
                                    ?: System.currentTimeMillis()
                                // Prefer the long-form note_tweet body over the truncated `text`.
                                val bodyText = dto.noteTweet?.text?.takeIf { it.isNotBlank() } ?: dto.text
                                // Prefer the API's expanded (de-t.co'd) URL; fall back to a regex scan.
                                val expandedUrl = dto.entities?.urls
                                    ?.firstNotNullOfOrNull { it.expandedUrl?.takeIf { u -> u.isNotBlank() } }
                                val urlAndTitle = extractUrlAndTitle(bodyText)
                                val imageUrl = dto.attachments?.mediaKeys
                                    ?.firstNotNullOfOrNull { key ->
                                        mediaByKey[key]?.let { it.url ?: it.previewImageUrl }
                                    }
                                val altText = dto.attachments?.mediaKeys
                                    ?.firstNotNullOfOrNull { key ->
                                        mediaByKey[key]?.altText?.takeIf { a -> a.isNotBlank() }
                                    }
                                val author = dto.authorId?.let { usersById[it] }
                                BookmarkEntity(
                                    id = dto.id, text = bodyText, createdAt = epochMs, userId = userId,
                                    title = urlAndTitle.first, url = expandedUrl ?: urlAndTitle.second,
                                    imageUrl = imageUrl,
                                    authorName = author?.name,
                                    authorUsername = author?.username,
                                    imageAltText = altText
                                )
                            }

                            val merged = entities.map { fresh ->
                                val existing = dao.getBookmarkById(fresh.id)
                                if (existing != null) {
                                    fresh.copy(
                                        title = existing.title ?: fresh.title,
                                        url = existing.url ?: fresh.url,
                                        imageUrl = fresh.imageUrl ?: existing.imageUrl,
                                        authorName = fresh.authorName ?: existing.authorName,
                                        authorUsername = fresh.authorUsername ?: existing.authorUsername,
                                        imageAltText = fresh.imageAltText ?: existing.imageAltText,
                                        summary = existing.summary, tags = existing.tags,
                                        category = existing.category, ocrText = existing.ocrText,
                                        isOcrScheduled = existing.isOcrScheduled,
                                        isAnalyzed = existing.isAnalyzed,
                                        sourceType = existing.sourceType, sourceId = existing.sourceId,
                                        sourceTitle = existing.sourceTitle, sourceAuthors = existing.sourceAuthors,
                                        sourceAbstract = existing.sourceAbstract, sourceExtra = existing.sourceExtra,
                                        referenceCount = existing.referenceCount, entities = existing.entities,
                                        isDeepAnalyzed = existing.isDeepAnalyzed, deepSummary = existing.deepSummary,
                                        embedding = existing.embedding,
                                        isFavorite = existing.isFavorite, isSavedForLater = existing.isSavedForLater,
                                        spaceId = existing.spaceId, notes = existing.notes
                                    )
                                } else fresh
                            }
                            // Persist each page as it arrives so partial progress survives a
                            // later rate-limit or network error mid-pagination.
                            if (merged.isNotEmpty()) dao.insertBookmarks(merged)
                            totalFetched += merged.size
                            pagesFetched++

                            paginationToken = response.meta?.nextToken
                        } while (paginationToken != null && pagesFetched < MAX_PAGES_PER_SYNC)

                        // Save the cursor if we stopped at the page cap so a follow-up
                        // sync can resume; clear it once we've reached the end.
                        if (paginationToken != null) cursors[userId] = paginationToken
                        else cursors.remove(userId)

                        Log.d("BookmarkRepo", "X sync fetched $totalFetched bookmarks across $pagesFetched page(s)")
                        xSyncSuccess = true
                    }
                } else {
                    xSyncSuccess = true
                }
            } catch (e: HttpException) {
                Log.e("BookmarkRepo", "HTTP ${e.code()} on X API")
                if (e.code() == 429) {
                    val resetHeader = e.response()?.headers()?.get("x-rate-limit-reset")
                    val resetSecondsVal = resetHeader?.toIntOrNull() ?: 900
                    val secondsLeft = if (resetSecondsVal > 1_000_000) {
                        val diff = resetSecondsVal - (System.currentTimeMillis() / 1000).toInt()
                        if (diff > 0) diff else 900
                    } else resetSecondsVal
                    return@withContext Result.failure(RateLimitException(secondsLeft))
                } else {
                    lastError = e
                }
            } catch (e: Exception) {
                Log.e("BookmarkRepo", "X API sync error: ${e.message}")
                lastError = e
            }

            // 3. Firebase push (bounded for the same reason as the pull)
            try {
                val local = dao.getAllBookmarksDirect().filter { it.userId == userId }
                if (local.isNotEmpty()) withTimeoutOrNull(FIREBASE_TIMEOUT_MS) {
                    firebaseSyncManager.pushBookmarks(userId, local.map { it.toDomain() })
                }
            } catch (e: Exception) {
                Log.e("BookmarkRepo", "Firebase push error: ${e.message}")
            }

            if (firebaseSyncSuccess || xSyncSuccess) Result.success(Unit)
            else Result.failure(lastError ?: Exception("Sync failed"))
        }

    override suspend fun clearAll(userId: String) = withContext(Dispatchers.IO) {
        dao.clearBookmarks(userId)
        cursors.remove(userId)
        Unit
    }

    override suspend fun updateAnalysisAndTags(
        id: String, summary: String?, category: String?, tags: List<String>, entities: String?
    ) = withContext(Dispatchers.IO) {
        val csv = if (tags.isEmpty()) null else tags.joinToString(",")
        dao.updateAnalysis(id, summary, csv, category, isAnalyzed = true, entities = entities)
        mirrorToCloud(id)
        Unit
    }

    override suspend fun updateOcrContent(id: String, ocrText: String?, isOcrScheduled: Boolean) =
        withContext(Dispatchers.IO) {
            dao.updateOcr(id, ocrText, isOcrScheduled)
            mirrorToCloud(id)
            Unit
        }

    override suspend fun addBookmark(userId: String, text: String): Result<Bookmark> =
        withContext(Dispatchers.IO) {
            try {
                val urlAndTitle = extractUrlAndTitle(text)
                val entity = BookmarkEntity(
                    id = "manual_${java.util.UUID.randomUUID()}",
                    text = text, createdAt = System.currentTimeMillis(), userId = userId,
                    title = urlAndTitle.first, url = urlAndTitle.second
                )
                dao.insertBookmarks(listOf(entity))
                val domain = entity.toDomain()
                try { firebaseSyncManager.pushBookmark(userId, domain) } catch (e: Exception) { /* no-op */ }
                Result.success(domain)
            } catch (e: Exception) {
                Log.e("BookmarkRepo", "Failed to add bookmark", e)
                Result.failure(e)
            }
        }

    override suspend fun deleteBookmarks(ids: List<String>) = withContext(Dispatchers.IO) {
        val entities = ids.mapNotNull { dao.getBookmarkById(it) }
        dao.deleteBookmarks(ids)
        try {
            entities.forEach { firebaseSyncManager.deleteBookmarks(it.userId, listOf(it.id)) }
        } catch (e: Exception) { Log.e("BookmarkRepo", "Firebase delete error: ${e.message}") }
        Unit
    }

    override suspend fun updateCategoryForIds(ids: List<String>, category: String) =
        withContext(Dispatchers.IO) {
            dao.updateCategoryForIds(ids, category)
            ids.forEach { mirrorToCloud(it) }
            Unit
        }

    override suspend fun updateCreatedAt(id: String, createdAt: Long) = withContext(Dispatchers.IO) {
        dao.updateCreatedAt(id, createdAt)
        mirrorToCloud(id)
        Unit
    }

    // ── Phase 8: Source resolution ─────────────────────────────────────────

    override suspend fun updateSourceInfo(
        id: String, sourceType: SourceType?, sourceId: String?, sourceTitle: String?,
        sourceAuthors: String?, sourceAbstract: String?, sourceExtra: String?, referenceCount: Int
    ) = withContext(Dispatchers.IO) {
        dao.updateSourceInfo(id, sourceType?.name, sourceId, sourceTitle, sourceAuthors, sourceAbstract, sourceExtra, referenceCount)
        mirrorToCloud(id)
        Unit
    }

    override suspend fun incrementReferenceCount(sourceId: String, userId: String) =
        withContext(Dispatchers.IO) { dao.incrementReferenceCount(sourceId, userId) }

    override suspend fun deduplicateBySource(userId: String) = withContext(Dispatchers.IO) {
        val withSource = dao.getBookmarksWithSourceId(userId)
        val grouped = withSource.groupBy { it.sourceId }
        grouped.forEach { (sourceId, group) ->
            if (sourceId != null && group.size > 1) {
                val canonical = group.minByOrNull { it.createdAt } ?: return@forEach
                val duplicateIds = group.filter { it.id != canonical.id }.map { it.id }
                dao.updateSourceInfo(
                    id = canonical.id,
                    sourceType = canonical.sourceType,
                    sourceId = canonical.sourceId,
                    sourceTitle = canonical.sourceTitle,
                    sourceAuthors = canonical.sourceAuthors,
                    sourceAbstract = canonical.sourceAbstract,
                    sourceExtra = canonical.sourceExtra,
                    referenceCount = group.size
                )
                dao.deleteBookmarks(duplicateIds)
                Log.d("BookmarkRepo", "Deduped $sourceId: kept ${canonical.id}, removed $duplicateIds")
            }
        }
    }

    // ── Phase 10: Embeddings ────────────────────────────────────────────────

    override suspend fun updateEmbedding(id: String, embedding: ByteArray) =
        withContext(Dispatchers.IO) { dao.updateEmbedding(id, embedding) }

    override suspend fun getBookmarksWithEmbeddings(userId: String): List<Pair<String, ByteArray>> =
        withContext(Dispatchers.IO) {
            dao.getIdsAndEmbeddings(userId).mapNotNull { row ->
                val bytes = row.embedding ?: return@mapNotNull null
                row.id to bytes
            }
        }

    override suspend fun getUnembeddedAnalyzed(): List<Bookmark> =
        withContext(Dispatchers.IO) { dao.getUnembedded().map { it.toDomain() } }

    override suspend fun clearAllEmbeddings() =
        withContext(Dispatchers.IO) { dao.clearAllEmbeddings() }

    // ── Phase 9: Deep analysis ──────────────────────────────────────────────

    override suspend fun updateDeepSummary(id: String, deepSummary: String) =
        withContext(Dispatchers.IO) {
            dao.updateDeepSummary(id, deepSummary, isDeepAnalyzed = true)
            mirrorToCloud(id)
            Unit
        }

    // ── Phase 12: Personal curation ─────────────────────────────────────────

    override suspend fun setFavorite(id: String, isFavorite: Boolean) = withContext(Dispatchers.IO) {
        dao.updateFavorite(id, isFavorite)
        mirrorToCloud(id)
        Unit
    }

    override suspend fun setSavedForLater(id: String, isSavedForLater: Boolean) = withContext(Dispatchers.IO) {
        dao.updateSavedForLater(id, isSavedForLater)
        mirrorToCloud(id)
        Unit
    }

    override suspend fun updateNotes(id: String, notes: String?) = withContext(Dispatchers.IO) {
        // Blank in → cleared (null) so an empty editor removes the note rather than storing "".
        dao.updateNotes(id, notes?.trim()?.takeIf { it.isNotEmpty() })
        // Local-only annotation — intentionally not mirrored to the cloud.
        Unit
    }

    // ── Spaces ──────────────────────────────────────────────────────────────

    override fun getSpacesFlow(userId: String): Flow<List<Space>> =
        spaceDao.getSpaces(userId).map { entities -> entities.map { it.toDomain() } }

    override suspend fun createSpace(
        userId: String, name: String, color: Long, icon: String,
        description: String, rules: SpaceRules, isPinned: Boolean
    ): Space = withContext(Dispatchers.IO) {
        val entity = SpaceEntity(
            id = "space_${java.util.UUID.randomUUID()}",
            userId = userId,
            name = name,
            colorValue = color,
            iconKey = icon,
            createdAt = System.currentTimeMillis(),
            description = description.trim(),
            isPinned = isPinned,
            // New Spaces sort newest-first by default (sortIndex 0); pinning/manual order layer on top.
            sortIndex = 0,
            rulesJson = rules.toJson()
        )
        spaceDao.upsertSpace(entity)
        entity.toDomain()
    }

    override suspend fun updateSpace(
        id: String, name: String, color: Long, icon: String,
        description: String, rules: SpaceRules, isPinned: Boolean
    ) = withContext(Dispatchers.IO) {
        val existing = spaceDao.getSpaceById(id) ?: return@withContext
        spaceDao.upsertSpace(
            existing.copy(
                name = name, colorValue = color, iconKey = icon,
                description = description.trim(), rulesJson = rules.toJson(), isPinned = isPinned
            )
        )
        Unit
    }

    override suspend fun deleteSpace(id: String) = withContext(Dispatchers.IO) {
        // Unfile members first so no bookmark points at a removed Space.
        dao.clearSpace(id)
        spaceDao.deleteSpace(id)
        Unit
    }

    override suspend fun setSpacePinned(id: String, pinned: Boolean) = withContext(Dispatchers.IO) {
        spaceDao.setPinned(id, pinned)
        Unit
    }

    override suspend fun assignToSpace(ids: List<String>, spaceId: String?) = withContext(Dispatchers.IO) {
        dao.updateSpaceForIds(ids, spaceId)
        Unit
    }

    // ── Smart Spaces: rule-driven auto-filing ────────────────────────────────

    override suspend fun fileByRules(bookmark: Bookmark): String? = withContext(Dispatchers.IO) {
        // Never override an existing (manual or prior) filing.
        if (bookmark.spaceId != null) return@withContext null
        val match = spaceDao.getSpacesDirect(bookmark.userId)
            .firstOrNull { it.rules().autoFile && it.rules().matches(bookmark) }
            ?: return@withContext null
        dao.updateSpaceForIds(listOf(bookmark.id), match.id)
        match.id
    }

    override suspend fun applySpaceRules(spaceId: String): Int = withContext(Dispatchers.IO) {
        val space = spaceDao.getSpaceById(spaceId) ?: return@withContext 0
        val rules = space.rules()
        if (!rules.isActive) return@withContext 0
        // Explicit action: file any unfiled bookmark this Space's rules match, ignoring autoFile.
        val matches = dao.getAllBookmarksDirect()
            .filter { it.userId == space.userId && it.spaceId == null && rules.matches(it.toDomain()) }
            .map { it.id }
        if (matches.isNotEmpty()) dao.updateSpaceForIds(matches, spaceId)
        matches.size
    }

    override suspend fun applyRulesToLibrary(userId: String): Int = withContext(Dispatchers.IO) {
        val smartSpaces = spaceDao.getSpacesDirect(userId).filter { it.rules().autoFile && it.rules().isActive }
        if (smartSpaces.isEmpty()) return@withContext 0
        var filed = 0
        dao.getAllBookmarksDirect()
            .filter { it.userId == userId && it.spaceId == null }
            .forEach { entity ->
                val domain = entity.toDomain()
                // First matching Space wins, matching the single-bookmark fileByRules() ordering.
                val target = smartSpaces.firstOrNull { it.rules().matches(domain) } ?: return@forEach
                dao.updateSpaceForIds(listOf(entity.id), target.id)
                filed++
            }
        filed
    }

    override suspend fun ensureCategorySpace(userId: String, category: String): String? =
        withContext(Dispatchers.IO) {
            val key = category.trim().lowercase()
            if (key.isEmpty()) return@withContext null
            // Deterministic id so re-analysis is idempotent and never spawns duplicates.
            val id = "space_cat_${userId}_$key"
            if (spaceDao.getSpaceById(id) == null) {
                val meta = com.example.domain.model.CategorySpaces.forCategory(key)
                spaceDao.upsertSpace(
                    SpaceEntity(
                        id = id, userId = userId, name = meta.name,
                        colorValue = meta.color, iconKey = meta.icon,
                        createdAt = System.currentTimeMillis()
                    )
                )
            }
            id
        }

    override suspend fun backfillCategorySpaces(userId: String) = withContext(Dispatchers.IO) {
        val unfiledByCategory = dao.getAllBookmarksDirect()
            .filter { it.userId == userId && it.spaceId == null && !it.category.isNullOrBlank() }
            .groupBy { it.category!!.trim().lowercase() }
        unfiledByCategory.forEach { (category, items) ->
            val spaceId = ensureCategorySpace(userId, category) ?: return@forEach
            dao.updateSpaceForIds(items.map { it.id }, spaceId)
        }
        Unit
    }

    // ── Private helpers ─────────────────────────────────────────────────────

    private data class BookmarksPage(val response: BookmarksResponse, val accessToken: String)

    /**
     * Fetches one page of bookmarks. If the access token has expired (HTTP 401), refreshes
     * it once using the stored refresh token and retries. On HTTP 429 (rate limit) it retries
     * with exponential backoff, honouring the `x-rate-limit-reset` header when it is sooner
     * than [RATE_LIMIT_MAX_WAIT_MS]; otherwise it rethrows so the caller can surface a
     * [RateLimitException]. Returns the (possibly refreshed) access token so the caller can
     * reuse it for subsequent pages.
     */
    private suspend fun getBookmarksWithAuthRetry(
        accessToken: String, userId: String, paginationToken: String?
    ): BookmarksPage {
        var token = accessToken
        var attempt = 0
        while (true) {
            try {
                return BookmarksPage(
                    api.getBookmarks("Bearer $token", userId, X_PAGE_SIZE, paginationToken),
                    token
                )
            } catch (e: HttpException) {
                when {
                    e.code() == 401 -> {
                        // Refresh the access token once, then retry on the new token.
                        token = refreshAccessToken() ?: throw e
                    }
                    e.code() == 429 && attempt < MAX_RATE_LIMIT_RETRIES -> {
                        val resetWaitMs = rateLimitWaitMs(e)
                        // Exponential backoff, but never wait less than the server's reset window.
                        val backoffMs = (RATE_LIMIT_BACKOFF_BASE_MS shl attempt)
                            .coerceAtLeast(resetWaitMs)
                        if (backoffMs > RATE_LIMIT_MAX_WAIT_MS) throw e // too long to block — surface it
                        Log.w("BookmarkRepo", "429 rate-limited; backoff ${backoffMs}ms (attempt ${attempt + 1})")
                        kotlinx.coroutines.delay(backoffMs)
                        attempt++
                    }
                    else -> throw e
                }
            }
        }
    }

    /** Milliseconds to wait for a 429, derived from the `x-rate-limit-reset` header. */
    private fun rateLimitWaitMs(e: HttpException): Long {
        val resetHeader = e.response()?.headers()?.get("x-rate-limit-reset")?.toIntOrNull() ?: return 0L
        val seconds = if (resetHeader > 1_000_000) {
            (resetHeader - (System.currentTimeMillis() / 1000).toInt()).coerceAtLeast(0)
        } else resetHeader
        return seconds * 1000L
    }

    /**
     * Exchanges the stored refresh token for a fresh access token and persists the rotated
     * credentials. Returns the new access token, or null if no refresh token is available
     * or the refresh fails (e.g. the refresh token itself expired — user must re-login).
     */
    private suspend fun refreshAccessToken(): String? {
        val refresh = tokenStore.getRefreshToken()?.takeIf { it.isNotBlank() } ?: return null
        return try {
            val clientId = BuildConfig.CLIENT_ID.takeIf { it.isNotEmpty() } ?: BuildConfig.X_CLIENT_ID
            val resp = authApi.refreshToken(
                grantType = "refresh_token",
                clientId = clientId,
                refreshToken = refresh
            )
            val userId = tokenStore.userIdFlow.first() ?: ""
            // X rotates refresh tokens; persist the new one (fall back to the old if absent).
            tokenStore.saveTokens(resp.accessToken, resp.refreshToken ?: refresh, userId)
            Log.d("BookmarkRepo", "X access token refreshed")
            resp.accessToken
        } catch (e: Exception) {
            Log.e("BookmarkRepo", "Token refresh failed: ${e.message}")
            null
        }
    }

    private fun parseRfc3339ToEpoch(iso: String): Long {
        return try {
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).parse(iso)?.time
                ?: System.currentTimeMillis()
        } catch (e: Exception) {
            try {
                SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).parse(iso)?.time
                    ?: System.currentTimeMillis()
            } catch (ex: Exception) {
                System.currentTimeMillis()
            }
        }
    }

    private fun extractUrlAndTitle(text: String): Pair<String?, String?> {
        val match = "https?://[a-zA-Z0-9.-]+(?:/[^\\s]*)?".toRegex().find(text)
        val url = match?.value
        val title = if (url != null) {
            val before = text.substringBefore(url).trim()
            if (before.isNotEmpty()) before.take(50).let { if (before.length > 50) "$it..." else it }
            else "Curio Saved Link"
        } else {
            text.take(50).let { if (text.length > 50) "$it..." else it }
        }
        return title to url
    }

    private fun BookmarkEntity.toDomain(): Bookmark {
        val tagList = tags?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() } ?: emptyList()
        val srcType = sourceType?.let { runCatching { SourceType.valueOf(it) }.getOrNull() }
        return Bookmark(
            id = id, text = text, createdAt = createdAt, userId = userId,
            title = title, url = url, summary = summary, tags = tagList,
            category = category, imageUrl = imageUrl, ocrText = ocrText,
            isOcrScheduled = isOcrScheduled, isAnalyzed = isAnalyzed,
            sourceType = srcType, sourceId = sourceId,
            sourceTitle = sourceTitle, sourceAuthors = sourceAuthors,
            sourceAbstract = sourceAbstract, sourceExtra = sourceExtra,
            referenceCount = referenceCount, entities = entities,
            isDeepAnalyzed = isDeepAnalyzed, deepSummary = deepSummary,
            isFavorite = isFavorite, isSavedForLater = isSavedForLater,
            authorName = authorName, authorUsername = authorUsername,
            imageAltText = imageAltText, spaceId = spaceId, notes = notes
        )
    }

    /** Parsed rule set for this Space row (cheap; tolerant of legacy/blank `rulesJson`). */
    private fun SpaceEntity.rules(): SpaceRules = SpaceRules.fromJson(rulesJson)

    private fun SpaceEntity.toDomain(): Space =
        Space(
            id = id, userId = userId, name = name, color = colorValue, icon = iconKey,
            createdAt = createdAt, description = description, isPinned = isPinned,
            sortIndex = sortIndex, rules = rules()
        )
}
