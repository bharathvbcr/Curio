package com.example

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.example.data.local.AppDatabase
import com.example.data.remote.FirebaseSyncManager
import com.example.data.remote.TokenStore
import com.example.data.remote.XAuthApi
import com.example.data.remote.XBookmarksApi
import com.example.data.repo.BookmarkRepositoryImpl
import com.example.data.repo.RateLimitException
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory

/**
 * Repository-level tests with MockWebServer covering pagination through `meta.next_token`
 * and 429 rate-limit handling (returns [RateLimitException]).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class RepositoryPagingTest {

    private lateinit var server: MockWebServer
    private lateinit var db: AppDatabase
    private lateinit var repo: BookmarkRepositoryImpl
    private lateinit var tokenStore: TokenStore

    private val uid = "u1"

    @Before
    fun setup() = runTest {
        val context = ApplicationProvider.getApplicationContext<Context>()
        server = MockWebServer().also { it.start() }

        val moshi = Moshi.Builder().addLast(KotlinJsonAdapterFactory()).build()
        val retrofit = Retrofit.Builder()
            .baseUrl(server.url("/"))
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()
        val api = retrofit.create(XBookmarksApi::class.java)
        val authApi = retrofit.create(XAuthApi::class.java)

        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries().build()
        tokenStore = TokenStore(context)
        tokenStore.saveTokens(accessToken = "acc", refreshToken = "ref", userId = uid)

        repo = BookmarkRepositoryImpl(
            api, db.bookmarkDao(), db.spaceDao(), tokenStore, FirebaseSyncManager(context), authApi
        )
    }

    @After
    fun teardown() {
        server.shutdown()
        db.close()
    }

    @Test
    fun `paginates through next_token`() = runTest {
        server.enqueue(
            MockResponse().setBody(
                """{"data":[{"id":"a","text":"first","created_at":"2024-01-01T00:00:00.000Z"}],"meta":{"next_token":"TOK2"}}"""
            )
        )
        server.enqueue(
            MockResponse().setBody("""{"data":[{"id":"b","text":"second"}],"meta":{}}""")
        )

        val result = repo.syncBookmarks(uid, fetchNextPage = false)
        assertTrue(result.isSuccess)

        val stored = db.bookmarkDao().getBookmarks(uid).first().map { it.id }.toSet()
        assertEquals(setOf("a", "b"), stored)
        // Two pages requested: page 1 + the next_token follow-up.
        assertEquals(2, server.requestCount)
    }

    @Test
    fun `rate limit 429 surfaces RateLimitException`() = runTest {
        server.enqueue(
            MockResponse()
                .setResponseCode(429)
                .setHeader("x-rate-limit-reset", "60") // 60s reset > 30s cap → surfaced immediately, no blocking retry
                .setBody("""{"title":"Too Many Requests"}""")
        )

        val result = repo.syncBookmarks(uid, fetchNextPage = false)
        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull() is RateLimitException)
    }
}
