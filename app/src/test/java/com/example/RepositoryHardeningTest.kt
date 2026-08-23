package com.example

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.example.data.local.AppDatabase
import com.example.data.local.BookmarkEntity
import com.example.data.remote.FirebaseSyncManager
import com.example.data.remote.TokenStore
import com.example.data.remote.XAuthApi
import com.example.data.remote.XBookmarksApi
import com.example.data.repo.BookmarkRepositoryImpl
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory

/**
 * Robustness tests for the repository layer: LIKE-metacharacter search, bulk IN-query chunking,
 * and the malformed-timestamp sentinel (a bad created_at used to store epoch 0 → "1970").
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class RepositoryHardeningTest {

    private lateinit var server: MockWebServer
    private lateinit var db: AppDatabase
    private lateinit var repo: BookmarkRepositoryImpl

    private val uid = "u1"

    @Before
    fun setup() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        server = MockWebServer().also { it.start() }

        val moshi = Moshi.Builder().addLast(KotlinJsonAdapterFactory()).build()
        val retrofit = Retrofit.Builder()
            .baseUrl(server.url("/"))
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()

        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries().build()

        val tokenStore = TokenStore(context)
        runBlocking { tokenStore.saveTokens(accessToken = "acc", refreshToken = "ref", userId = uid) }

        repo = BookmarkRepositoryImpl(
            retrofit.create(XBookmarksApi::class.java),
            db.bookmarkDao(), db.spaceDao(), tokenStore,
            FirebaseSyncManager(context), retrofit.create(XAuthApi::class.java)
        )
    }

    @After
    fun teardown() {
        server.shutdown()
        db.close()
    }

    private suspend fun insert(id: String, text: String, createdAt: Long = 1_700_000_000_000L) {
        db.bookmarkDao().insertBookmarks(listOf(BookmarkEntity(id = id, text = text, createdAt = createdAt, userId = uid)))
    }

    // ── LIKE wildcard injection ──────────────────────────────────────────────

    @Test
    fun `percent in query is literal not wildcard`() = runBlocking {
        insert("b1", "100% done")
        insert("b2", "100x done")
        val hits = repo.searchBookmarks(uid, "100%").map { it.id }
        assertEquals(listOf("b1"), hits)
    }

    @Test
    fun `underscore in query is literal not wildcard`() = runBlocking {
        insert("b1", "snake_case_name")
        insert("b1x", "snakeXcaseXname")
        val hits = repo.searchBookmarks(uid, "_case_").map { it.id }
        assertEquals(listOf("b1"), hits)
    }

    @Test
    fun `backslash in query does not crash`() = runBlocking {
        insert("b1", "path C:\\Users\\test")
        val hits = repo.searchBookmarks(uid, "\\Users").map { it.id }
        assertEquals(listOf("b1"), hits)
    }

    // ── Bulk IN-query chunking (stress: 1500 ids > legacy 999 SQLite variable cap) ──

    @Test
    fun `bulk delete of 1500 ids removes all rows`() = runBlocking {
        val entities = (0 until 1500).map {
            BookmarkEntity(id = "bulk$it", text = "t$it", createdAt = 1_700_000_000_000L, userId = uid)
        }
        db.bookmarkDao().insertBookmarks(entities)

        repo.deleteBookmarks(entities.map { it.id })

        assertEquals(0, db.bookmarkDao().getBookmarksByUserDirect(uid).size)
    }

    @Test
    fun `bulk space assignment of 1500 ids files every row`() = runBlocking {
        val entities = (0 until 1500).map {
            BookmarkEntity(id = "sp$it", text = "t$it", createdAt = 1_700_000_000_000L, userId = uid)
        }
        db.bookmarkDao().insertBookmarks(entities)

        repo.assignToSpace(entities.map { it.id }, "space_x")

        val unfiled = entities.count { db.bookmarkDao().getBookmarkById(it.id)?.spaceId != "space_x" }
        assertEquals(0, unfiled)
    }

    // ── Malformed created_at must not become 1970 ────────────────────────────

    @Test
    fun `malformed created_at falls back to now not epoch zero`() = runBlocking {
        server.enqueue(
            MockResponse().setBody(
                """{"data":[{"id":"badts","text":"hello","created_at":"not-a-real-date"}],"meta":{}}"""
            )
        )
        val before = System.currentTimeMillis() - 60_000L
        assertTrue(repo.syncBookmarks(uid, fetchNextPage = false).isSuccess)
        val stored = db.bookmarkDao().getBookmarkById("badts")!!
        assertTrue("expected ~now, got ${stored.createdAt}", stored.createdAt >= before)
    }
}
