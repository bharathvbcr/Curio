package com.example

import com.example.data.remote.ArxivClient
import com.example.data.remote.CrossrefClient
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Exercises the primary-source HTTP clients against a MockWebServer (base URLs are injectable), so
 * the arXiv Atom parser and Crossref JSON parser are tested end-to-end without hitting the network.
 * Robolectric supplies android.util.Xml (arXiv) and android.util.Log.
 */
@RunWith(RobolectricTestRunner)
@Config(manifest = Config.NONE)
class SourceClientTest {

    @Test
    fun `arxiv atom is parsed into ArxivMeta`() {
        val atom = """
            <?xml version="1.0" encoding="UTF-8"?>
            <feed xmlns="http://www.w3.org/2005/Atom">
              <entry>
                <id>http://arxiv.org/abs/2312.00752v1</id>
                <title>Mamba: Linear-Time Sequence Modeling</title>
                <summary>We introduce a selective state space model.</summary>
                <published>2023-12-01T00:00:00Z</published>
                <author><name>Albert Gu</name></author>
                <author><name>Tri Dao</name></author>
                <category term="cs.LG"/>
              </entry>
            </feed>
        """.trimIndent()
        val server = MockWebServer()
        server.enqueue(MockResponse().setResponseCode(200).setBody(atom))
        server.start()
        try {
            val client = ArxivClient(OkHttpClient(), server.url("/").toString())
            val meta = runBlocking { client.fetchPaper("2312.00752") }!!
            assertEquals("2312.00752", meta.id)                       // version suffix stripped
            assertTrue(meta.title.contains("Mamba"))
            assertEquals(listOf("Albert Gu", "Tri Dao"), meta.authors)
            assertEquals("2023-12-01", meta.published)
            assertEquals(listOf("cs.LG"), meta.categories)
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun `arxiv non-2xx yields null`() {
        val server = MockWebServer()
        server.enqueue(MockResponse().setResponseCode(503))
        server.start()
        try {
            val client = ArxivClient(OkHttpClient(), server.url("/").toString())
            assertEquals(null, runBlocking { client.fetchPaper("2312.00752") })
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun `crossref json is parsed and JATS abstract is stripped`() {
        val json = """
            {"message":{
              "DOI":"10.1038/s41586-021-03819-2",
              "title":["Highly accurate protein structure prediction with AlphaFold"],
              "author":[{"given":"John","family":"Jumper"},{"given":"Demis","family":"Hassabis"}],
              "abstract":"<jats:p>AlphaFold predicts structures.</jats:p>",
              "container-title":["Nature"],
              "type":"journal-article",
              "issued":{"date-parts":[[2021,7,15]]}
            }}
        """.trimIndent()
        val server = MockWebServer()
        server.enqueue(MockResponse().setResponseCode(200).setBody(json))
        server.start()
        try {
            val client = CrossrefClient(OkHttpClient(), server.url("/").toString())
            val meta = runBlocking { client.fetchWork("10.1038/s41586-021-03819-2") }!!
            assertEquals("10.1038/s41586-021-03819-2", meta.doi)
            assertTrue(meta.title.contains("AlphaFold"))
            assertEquals(listOf("John Jumper", "Demis Hassabis"), meta.authors)
            assertEquals("Nature", meta.containerTitle)
            assertEquals("2021-07-15", meta.published)
            assertEquals("AlphaFold predicts structures.", meta.abstract)
        } finally {
            server.shutdown()
        }
    }
}
