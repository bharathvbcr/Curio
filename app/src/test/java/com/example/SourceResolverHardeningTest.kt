package com.example

import com.example.data.remote.ArxivClient
import com.example.data.remote.GithubApi
import com.example.data.remote.HuggingFaceApi
import com.example.data.remote.CrossrefClient
import com.example.data.source.SourceResolver
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory

/**
 * Hardening for primary-source resolution: the arXiv ID regex must not swallow trailing dots
 * from /pdf/<id>.pdf links, and a hostile server-supplied `Retry-After` must be capped — the
 * resolver used to sleep for exactly the header value (up to hours) on 429/503.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class SourceResolverHardeningTest {

    // ── arXiv ID extraction ──────────────────────────────────────────────────

    @Test
    fun `abs url id extracted cleanly`() {
        assertEquals(
            "2401.00001",
            ArxivClient.ARXIV_ID_REGEX.find("https://arxiv.org/abs/2401.00001")!!.groupValues[1]
        )
    }

    @Test
    fun `pdf url with extension has no trailing dot`() {
        val m = ArxivClient.ARXIV_ID_REGEX.find("https://arxiv.org/pdf/2401.00001.pdf")!!
        val id = m.groupValues[1]
        assertEquals("2401.00001", id)
    }

    @Test
    fun `versioned pdf url keeps version drops extension`() {
        val id = ArxivClient.ARXIV_ID_REGEX.find("https://arxiv.org/pdf/2401.00001v2.pdf")!!.groupValues[1]
        assertEquals("2401.00001v2", id)
    }

    @Test
    fun `trailing sentence punctuation does not corrupt id`() {
        val id = ArxivClient.ARXIV_ID_REGEX.find("see https://arxiv.org/pdf/2312.00752.")!!.groupValues[1]
        assertTrue(id.endsWith(".00752") && !id.endsWith("."))
    }

    // ── Retry-After cap (hostile header: 99999s ≈ 27h; old code slept it verbatim) ──

    private fun resolver(server: MockWebServer, ceilingMs: Long): SourceResolver {
        val moshi = Moshi.Builder().addLast(KotlinJsonAdapterFactory()).build()
        val retrofit = Retrofit.Builder()
            .baseUrl(server.url("/"))
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()
        return SourceResolver(
            arxivClient = ArxivClient(OkHttpClient(), server.url("/").toString()),
            githubApi = retrofit.create(GithubApi::class.java),
            huggingFaceApi = retrofit.create(HuggingFaceApi::class.java),
            crossrefClient = CrossrefClient(OkHttpClient(), server.url("/").toString()),
            retryAfterCeilingMs = ceilingMs
        )
    }

    @Test(timeout = 20_000L)
    fun `hostile retry-after is capped and resolve completes quickly`() {
        val server = MockWebServer()
        repeat(12) {
            server.enqueue(
                MockResponse().setResponseCode(429).setHeader("Retry-After", "99999").setBody("{}")
            )
        }
        server.start()
        try {
            val started = System.currentTimeMillis()
            val info = runBlocking {
                withTimeoutOrNull(15_000L) {
                    // GitHub URLs route through the Retrofit-based GithubApi, whose suspend
                    // calls surface HTTP failures as HttpException — the path guarded by
                    // withRetry's Retry-After handling.
                    resolver(server, ceilingMs = 10L)
                        .resolve(text = "check https://github.com/foo/bar", url = null)
                }
            }
            val elapsed = System.currentTimeMillis() - started
            assertNull("all attempts 429 → no result", info)
            assertTrue("resolve took ${elapsed}ms — Retry-After not capped", elapsed < 10_000L)
        } finally {
            server.shutdown()
        }
    }
}
