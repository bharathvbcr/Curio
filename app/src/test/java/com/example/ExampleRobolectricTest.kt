package com.example

import android.content.Context
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.example.data.XAiAnalyzer
import com.example.data.embedding.EmbeddingService
import com.example.data.ocr.OcrAnalyzer
import com.example.data.remote.ArxivClient
import com.example.data.remote.GithubApi
import com.example.data.remote.GithubRepoResponse
import com.example.data.remote.GithubOwner
import com.example.data.remote.HuggingFaceApi
import com.example.data.remote.HfModelResponse
import com.example.data.remote.HfDatasetResponse
import com.example.data.remote.XAiApi
import com.example.data.remote.XAiEmbeddingRequest
import com.example.data.remote.XAiEmbeddingResponse
import com.example.data.remote.XAiRequest
import com.example.data.remote.XAiResponse
import com.example.data.source.SourceResolver
import com.example.domain.model.Bookmark
import com.example.domain.model.SourceType
import com.example.domain.repo.BookmarkRepository
import com.example.ui.BookmarkViewModel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

class FakeBookmarkRepository : BookmarkRepository {
    val bookmarksFlow = MutableStateFlow<List<Bookmark>>(emptyList())

    override fun getBookmarksFlow(userId: String): Flow<List<Bookmark>> = bookmarksFlow

    override suspend fun getBookmarkById(id: String): Bookmark? =
        bookmarksFlow.value.find { it.id == id }

    override suspend fun searchBookmarks(userId: String, query: String): List<Bookmark> {
        val all = bookmarksFlow.value.sortedByDescending { it.createdAt }
        if (query.isBlank()) return all
        return all.filter {
            it.text.contains(query, ignoreCase = true) ||
                (it.title?.contains(query, ignoreCase = true) == true) ||
                (it.summary?.contains(query, ignoreCase = true) == true) ||
                (it.ocrText?.contains(query, ignoreCase = true) == true)
        }
    }

    override suspend fun syncBookmarks(userId: String, fetchNextPage: Boolean): Result<Unit> =
        Result.success(Unit)

    override suspend fun swapCreatedAt(id1: String, ts1: Long, id2: String, ts2: Long) {
        bookmarksFlow.value = bookmarksFlow.value.map {
            when (it.id) {
                id1 -> it.copy(createdAt = ts2)
                id2 -> it.copy(createdAt = ts1)
                else -> it
            }
        }
    }

    override suspend fun clearAll(userId: String) {
        bookmarksFlow.value = emptyList()
    }

    override suspend fun updateAnalysisAndTags(
        id: String,
        summary: String?,
        category: String?,
        tags: List<String>,
        entities: String?
    ) {
        bookmarksFlow.value = bookmarksFlow.value.map {
            if (it.id == id) it.copy(summary = summary, category = category, tags = tags, isAnalyzed = true)
            else it
        }
    }

    override suspend fun updateOcrContent(id: String, ocrText: String?, isOcrScheduled: Boolean) {
        bookmarksFlow.value = bookmarksFlow.value.map {
            if (it.id == id) it.copy(ocrText = ocrText, isOcrScheduled = isOcrScheduled) else it
        }
    }

    override suspend fun addBookmark(userId: String, text: String): Result<Bookmark> {
        val newBookmark = Bookmark(
            id = "manual_${java.util.UUID.randomUUID()}",
            text = text,
            createdAt = System.currentTimeMillis(),
            userId = userId,
            title = if (text.startsWith("http")) "Mock Manual Link" else "Mock Manual Text",
            url = if (text.startsWith("http")) text else null,
            summary = null,
            tags = emptyList(),
            category = null,
            ocrText = null,
            isOcrScheduled = false,
            isAnalyzed = false
        )
        bookmarksFlow.value = bookmarksFlow.value + newBookmark
        return Result.success(newBookmark)
    }

    override suspend fun deleteBookmarks(ids: List<String>) {
        bookmarksFlow.value = bookmarksFlow.value.filter { it.id !in ids }
    }

    override suspend fun restoreBookmarks(bookmarks: List<Bookmark>) {
        val existing = bookmarksFlow.value.associateBy { it.id }.toMutableMap()
        bookmarks.forEach { existing[it.id] = it }
        bookmarksFlow.value = existing.values.sortedByDescending { it.createdAt }
    }

    override suspend fun updateCategoryForIds(ids: List<String>, category: String) {
        bookmarksFlow.value = bookmarksFlow.value.map {
            if (it.id in ids) it.copy(category = category) else it
        }
    }

    override suspend fun updateCreatedAt(id: String, createdAt: Long) {}

    override suspend fun updateSourceInfo(
        id: String,
        sourceType: SourceType?,
        sourceId: String?,
        sourceTitle: String?,
        sourceAuthors: String?,
        sourceAbstract: String?,
        sourceExtra: String?,
        referenceCount: Int
    ) {}

    override suspend fun incrementReferenceCount(sourceId: String, userId: String) {}
    override suspend fun deduplicateBySource(userId: String): Int = 0
    override suspend fun updateEmbedding(id: String, embedding: ByteArray) {}
    override suspend fun updateEmbeddings(updates: List<Pair<String, ByteArray>>) {}
    override suspend fun getBookmarksWithEmbeddings(userId: String): List<Pair<String, ByteArray>> = emptyList()
    override suspend fun getUnembeddedAnalyzed(userId: String): List<Bookmark> = emptyList()
    override suspend fun getAllUnembedded(userId: String): List<Bookmark> = emptyList()
    override suspend fun clearAllEmbeddings() {}
    override suspend fun updateDeepSummary(id: String, deepSummary: String) {}

    override suspend fun setFavorite(id: String, isFavorite: Boolean) {
        bookmarksFlow.value = bookmarksFlow.value.map {
            if (it.id == id) it.copy(isFavorite = isFavorite) else it
        }
    }

    override suspend fun setSavedForLater(id: String, isSavedForLater: Boolean) {
        bookmarksFlow.value = bookmarksFlow.value.map {
            if (it.id == id) it.copy(isSavedForLater = isSavedForLater) else it
        }
    }

    override suspend fun updateNotes(id: String, notes: String?) {
        bookmarksFlow.value = bookmarksFlow.value.map {
            if (it.id == id) it.copy(notes = notes?.trim()?.takeIf { n -> n.isNotEmpty() }) else it
        }
    }

    // ── Spaces ───────────────────────────────────────────────────────────────
    val spacesFlow = MutableStateFlow<List<com.example.domain.model.Space>>(emptyList())

    override fun getSpacesFlow(userId: String): Flow<List<com.example.domain.model.Space>> = spacesFlow

    override suspend fun createSpace(
        userId: String, name: String, color: Long, icon: String,
        description: String, rules: com.example.domain.model.SpaceRules, isPinned: Boolean
    ): com.example.domain.model.Space {
        val space = com.example.domain.model.Space(
            "space_${java.util.UUID.randomUUID()}", userId, name, color, icon,
            System.currentTimeMillis(), description = description, isPinned = isPinned, rules = rules
        )
        spacesFlow.value = spacesFlow.value + space
        return space
    }

    override suspend fun updateSpace(
        id: String, name: String, color: Long, icon: String,
        description: String, rules: com.example.domain.model.SpaceRules, isPinned: Boolean
    ) {
        spacesFlow.value = spacesFlow.value.map {
            if (it.id == id) it.copy(name = name, color = color, icon = icon, description = description, rules = rules, isPinned = isPinned) else it
        }
    }

    override suspend fun deleteSpace(id: String) {
        spacesFlow.value = spacesFlow.value.filter { it.id != id }
        bookmarksFlow.value = bookmarksFlow.value.map { if (it.spaceId == id) it.copy(spaceId = null) else it }
    }

    override suspend fun setSpacePinned(id: String, pinned: Boolean) {
        spacesFlow.value = spacesFlow.value.map { if (it.id == id) it.copy(isPinned = pinned) else it }
    }

    override suspend fun assignToSpace(ids: List<String>, spaceId: String?) {
        bookmarksFlow.value = bookmarksFlow.value.map { if (it.id in ids) it.copy(spaceId = spaceId) else it }
    }

    override suspend fun fileByRules(bookmark: com.example.domain.model.Bookmark): String? {
        if (!com.example.domain.model.CategorySpaces.bookmarkEligibleForRuleFiling(bookmark.spaceId)) return null
        val match = spacesFlow.value.firstOrNull { it.rules.autoFile && it.rules.matches(bookmark) } ?: return null
        assignToSpace(listOf(bookmark.id), match.id)
        return match.id
    }

    override suspend fun applySpaceRules(spaceId: String): Int {
        val space = spacesFlow.value.firstOrNull { it.id == spaceId } ?: return 0
        if (!space.rules.isActive) return 0
        val matches = bookmarksFlow.value
            .filter { com.example.domain.model.CategorySpaces.bookmarkEligibleForRuleFiling(it.spaceId) && space.rules.matches(it) }
            .map { it.id }
        if (matches.isNotEmpty()) assignToSpace(matches, spaceId)
        return matches.size
    }

    override suspend fun applyRulesToLibrary(userId: String): Int {
        val smart = spacesFlow.value.filter { it.rules.autoFile && it.rules.isActive }
        if (smart.isEmpty()) return 0
        var filed = 0
        bookmarksFlow.value
            .filter { it.userId == userId && com.example.domain.model.CategorySpaces.bookmarkEligibleForRuleFiling(it.spaceId) }
            .forEach { b ->
            val target = smart.firstOrNull { it.rules.matches(b) } ?: return@forEach
            assignToSpace(listOf(b.id), target.id)
            filed++
        }
        return filed
    }

    override suspend fun ensureCategorySpace(userId: String, category: String): String? {
        val key = category.trim().lowercase()
        if (key.isEmpty()) return null
        val id = "${com.example.domain.model.CategorySpaces.SPACE_ID_PREFIX}${userId}_$key"
        if (spacesFlow.value.none { it.id == id }) {
            val meta = com.example.domain.model.CategorySpaces.forCategory(key)
            spacesFlow.value = spacesFlow.value + com.example.domain.model.Space(id, userId, meta.name, meta.color, meta.icon, System.currentTimeMillis())
        }
        return id
    }

    override suspend fun backfillCategorySpaces(userId: String) {
        bookmarksFlow.value
            .filter { it.userId == userId && it.spaceId.isNullOrBlank() && !it.category.isNullOrBlank() }
            .groupBy { it.category!!.trim().lowercase() }
            .forEach { (category, items) ->
                val spaceId = ensureCategorySpace(userId, category) ?: return@forEach
                assignToSpace(items.map { it.id }, spaceId)
            }
    }

    override suspend fun organizeByEmbedding(userId: String): com.example.domain.model.OrganizeResult =
        com.example.domain.model.OrganizeResult.EMPTY
}

class FakeXAiApi : XAiApi {
    override suspend fun chatCompletions(authorization: String, request: XAiRequest): XAiResponse =
        XAiResponse(choices = emptyList())

    override suspend fun visionCompletions(
        authorization: String,
        request: com.example.data.remote.XAiVisionRequest
    ): XAiResponse = XAiResponse(choices = emptyList())

    override suspend fun createEmbeddings(
        authorization: String,
        request: XAiEmbeddingRequest
    ): XAiEmbeddingResponse = XAiEmbeddingResponse(data = emptyList())

    override suspend fun listEmbeddingModels(
        authorization: String
    ): com.example.data.remote.XAiEmbeddingModelsResponse =
        com.example.data.remote.XAiEmbeddingModelsResponse()

    override suspend fun generateImages(
        authorization: String,
        request: com.example.data.remote.XAiImageRequest
    ): com.example.data.remote.XAiImageResponse = com.example.data.remote.XAiImageResponse(data = emptyList())

    override suspend fun getApiKeyInfo(
        authorization: String
    ): com.example.data.remote.XAiApiKeyInfo = com.example.data.remote.XAiApiKeyInfo()
}

class FakeGithubApi : GithubApi {
    override suspend fun getRepo(owner: String, repo: String): GithubRepoResponse =
        throw UnsupportedOperationException("not used in tests")
}

class FakeHuggingFaceApi : HuggingFaceApi {
    override suspend fun getModel(id: String): HfModelResponse =
        throw UnsupportedOperationException("not used in tests")

    override suspend fun getDataset(id: String): HfDatasetResponse =
        throw UnsupportedOperationException("not used in tests")
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ExampleRobolectricTest {

    @Test
    fun `read string from context`() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val appName = context.getString(R.string.app_name)
        assertEquals("Curio", appName)
    }

    @Test
    fun `viewmodel filtering and stats test`() = runTest {
        val fakeXAiApi = FakeXAiApi()
        val repository = FakeBookmarkRepository()
        val ocrAnalyzer = OcrAnalyzer()
        val aiAnalyzer = XAiAnalyzer(fakeXAiApi)
        val embeddingService = EmbeddingService(fakeXAiApi)
        val sourceResolver = SourceResolver(
            ArxivClient(OkHttpClient()),
            FakeGithubApi(),
            FakeHuggingFaceApi(),
            com.example.data.remote.CrossrefClient(OkHttpClient())
        )

        val availability = com.example.data.ai.GenAiAvailability(ApplicationProvider.getApplicationContext())
        val localGen = com.example.data.ai.LocalKeywordTextGenerator(aiAnalyzer)
        val textGenerator = com.example.data.ai.TextGeneratorSelector(
            com.example.data.ai.NanoTextGenerator(availability, localGen),
            com.example.data.ai.CloudTextGenerator(aiAnalyzer),
            localGen,
            availability
        )
        val grokImageService = com.example.data.GrokImageService(fakeXAiApi)
        val tokenStore = com.example.data.remote.TokenStore(ApplicationProvider.getApplicationContext())
        val embeddingModelManager = com.example.data.embedding.EmbeddingModelManager(
            ApplicationProvider.getApplicationContext(),
            tokenStore
        )
        val chronosFlowBridge = com.example.interop.ChronosFlowBridge(ApplicationProvider.getApplicationContext())
        val curioActivityController = com.example.notifications.CurioActivityController(
            kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.SupervisorJob()),
            com.example.notifications.CurioNotifier(ApplicationProvider.getApplicationContext())
        )
        val reminderScheduler = com.example.notifications.ReminderScheduler(ApplicationProvider.getApplicationContext())
        val semanticDb = androidx.room.Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            com.example.data.local.AppDatabase::class.java
        ).allowMainThreadQueries().build()
        val semanticLayer = com.example.data.semantic.OnDeviceSemanticLayer(
            ApplicationProvider.getApplicationContext(),
            semanticDb.semanticCacheDao()
        )
        val viewModel = BookmarkViewModel(repository, ocrAnalyzer, aiAnalyzer, embeddingService, sourceResolver, textGenerator, grokImageService, embeddingModelManager, tokenStore, chronosFlowBridge, curioActivityController, reminderScheduler, semanticLayer)

        val mockBookmarks = listOf(
            Bookmark(
                id = "1",
                text = "Building secure Web APIs with Compose",
                createdAt = 1000L,
                userId = "test_user",
                title = "Compose Security Framework",
                url = "https://compose.dev/security",
                category = "Development",
                tags = listOf("Kotlin", "Security"),
                isAnalyzed = true
            ),
            Bookmark(
                id = "2",
                text = "Dynamic Color Palette Generation Guidelines",
                createdAt = 2000L,
                userId = "test_user",
                title = "M3 Generator",
                url = "https://m3.material.io/theme-builder",
                category = "Design",
                tags = listOf("Colors", "UIUX"),
                isAnalyzed = true
            ),
            Bookmark(
                id = "3",
                text = "Growth hacking for indie developers",
                createdAt = 3000L,
                userId = "test_user",
                title = "Indie Growth Hub",
                url = "https://indiehackers.com/growth",
                category = "Marketing",
                tags = listOf("SEO", "Growth"),
                isAnalyzed = false
            )
        )
        repository.bookmarksFlow.value = mockBookmarks

        val testDispatcher = UnconfinedTestDispatcher(testScheduler)
        viewModel.setUserId("test_user")

        backgroundScope.launch(testDispatcher) { viewModel.rawBookmarks.collect {} }
        backgroundScope.launch(testDispatcher) { viewModel.bookmarks.collect {} }
        backgroundScope.launch(testDispatcher) { viewModel.stats.collect {} }

        testScheduler.runCurrent()
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(3, viewModel.rawBookmarks.value.size)
        assertEquals(3, viewModel.bookmarks.value.size)

        viewModel.updateSearchQuery("Compose")
        testScheduler.runCurrent()
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1, viewModel.bookmarks.value.size)
        assertEquals("1", viewModel.bookmarks.value.first().id)

        viewModel.updateSearchQuery("M3 Generator")
        testScheduler.runCurrent()
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1, viewModel.bookmarks.value.size)
        assertEquals("2", viewModel.bookmarks.value.first().id)

        viewModel.updateSearchQuery("indiehackers.com")
        testScheduler.runCurrent()
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1, viewModel.bookmarks.value.size)
        assertEquals("3", viewModel.bookmarks.value.first().id)

        viewModel.updateSearchQuery("")
        testScheduler.runCurrent()
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(3, viewModel.bookmarks.value.size)

        viewModel.selectCategory("Design")
        testScheduler.runCurrent()
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1, viewModel.bookmarks.value.size)
        assertEquals("2", viewModel.bookmarks.value.first().id)

        viewModel.selectCategory(null)
        testScheduler.runCurrent()
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(3, viewModel.bookmarks.value.size)

        viewModel.selectTag("SEO")
        testScheduler.runCurrent()
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1, viewModel.bookmarks.value.size)
        assertEquals("3", viewModel.bookmarks.value.first().id)

        viewModel.selectTag(null)
        testScheduler.runCurrent()
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(3, viewModel.bookmarks.value.size)

        val currentStats = viewModel.stats.value
        assertEquals(3, currentStats.totalCount)
        assertEquals(2, currentStats.curatedCount) // id=1 and id=2 are analyzed
        assertEquals(1, currentStats.categoryCounts["Development"])
        assertEquals(1, currentStats.categoryCounts["Design"])
        assertEquals(1, currentStats.categoryCounts["Marketing"])
    }

    @Test
    fun `test token store encryption and decryption`() = runTest {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val tokenStore = com.example.data.remote.TokenStore(context)

        tokenStore.saveTokens(
            accessToken = "my_access_token_123",
            refreshToken = "my_refresh_token_456",
            userId = "my_user_id_789"
        )

        assertTrue(tokenStore.hasTokens())
        assertEquals("my_access_token_123", tokenStore.getAccessToken())
        assertEquals("my_refresh_token_456", tokenStore.getRefreshToken())
        assertEquals("my_user_id_789", tokenStore.userIdFlow.first())
    }
}
