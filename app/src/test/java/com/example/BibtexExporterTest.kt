package com.example

import com.example.data.export.BibtexExporter
import com.example.domain.model.Bookmark
import com.example.domain.model.SourceType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Citation-export tests. Robolectric supplies a real org.json used by the exporter. */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class BibtexExporterTest {

    private fun arxiv() = Bookmark(
        id = "t1", text = "great paper", createdAt = 1_700_000_000_000L, userId = "u1",
        sourceType = SourceType.ARXIV, sourceId = "2312.00752",
        sourceTitle = "Mamba: Linear-Time Sequence Modeling",
        sourceAuthors = "Albert Gu, Tri Dao",
        sourceAbstract = "We introduce a selective state space model.",
        sourceExtra = """{"published":"2023-12-01","categories":["cs.LG","cs.AI"]}"""
    )

    private fun doi() = Bookmark(
        id = "t2", text = "doi paper", createdAt = 1_700_000_000_000L, userId = "u1",
        sourceType = SourceType.DOI, sourceId = "10.1038/s41586-021-03819-2",
        sourceTitle = "Highly accurate protein structure prediction with AlphaFold",
        sourceAuthors = "John Jumper, Demis Hassabis",
        sourceAbstract = "AlphaFold predicts structures.",
        sourceExtra = """{"doi":"10.1038/s41586-021-03819-2","published":"2021-07-15","container":"Nature"}"""
    )

    @Test
    fun `arxiv bibtex includes enriched fields`() {
        val b = BibtexExporter.toBibtex(arxiv())!!
        assertTrue(b.contains("@article{"))
        assertTrue(b.contains("eprint        = {2312.00752}"))
        assertTrue(b.contains("archivePrefix = {arXiv}"))
        assertTrue(b.contains("primaryClass  = {cs.LG}"))
        assertTrue(b.contains("month         = {dec}"))
        assertTrue(b.contains("author        = {Albert Gu and Tri Dao}"))
        assertTrue(b.contains("abstract      = {"))
        assertTrue(b.contains("year          = {2023}"))
    }

    @Test
    fun `doi bibtex uses journal and doi`() {
        val b = BibtexExporter.toBibtex(doi())!!
        assertTrue(b.contains("journal = {Nature}"))
        assertTrue(b.contains("doi     = {10.1038/s41586-021-03819-2}"))
        assertTrue(b.contains("https://doi.org/10.1038/s41586-021-03819-2"))
        assertTrue(b.contains("year    = {2021}"))
    }

    @Test
    fun `ris export marks papers as journal articles`() {
        val ris = BibtexExporter.toRis(arxiv())!!
        assertTrue(ris.startsWith("TY  - JOUR"))
        assertTrue(ris.contains("AU  - Albert Gu"))
        assertTrue(ris.contains("AU  - Tri Dao"))
        assertTrue(ris.contains("UR  - https://arxiv.org/abs/2312.00752"))
        assertTrue(ris.trimEnd().endsWith("ER  -"))
    }

    @Test
    fun `csl json carries split author names and doi`() {
        // Android's org.json (used at runtime and under Robolectric) escapes '/' as '\/' —
        // valid JSON that Zotero/pandoc accept fine; normalize so assertions read naturally.
        val csl = BibtexExporter.toCslJson(doi())!!.replace("\\/", "/")
        assertTrue(csl.contains("\"family\": \"Jumper\""))
        assertTrue(csl.contains("\"given\": \"John\""))
        assertTrue(csl.contains("\"DOI\": \"10.1038/s41586-021-03819-2\""))
        assertTrue(csl.contains("\"type\": \"article-journal\""))
    }

    @Test
    fun `markdown export is a single linked bullet`() {
        val md = BibtexExporter.toMarkdown(arxiv())!!
        assertTrue(md.startsWith("- "))
        assertTrue(md.contains("(2023)"))
        assertTrue(md.contains("[Mamba: Linear-Time Sequence Modeling](https://arxiv.org/abs/2312.00752)"))
    }

    @Test
    fun `tweets and unresolved bookmarks have no citation`() {
        val tweet = Bookmark(id = "x", text = "just a tweet", createdAt = 1_700_000_000_000L, userId = "u1")
        assertNull(BibtexExporter.toBibtex(tweet))
        assertNull(BibtexExporter.toRis(tweet))
        assertNull(BibtexExporter.toMarkdown(tweet))
    }

    @Test
    fun `list export concatenates and skips non-sources`() {
        val tweet = Bookmark(id = "x", text = "tweet", createdAt = 1_700_000_000_000L, userId = "u1")
        val list = BibtexExporter.toBibtexList(listOf(arxiv(), tweet, doi()))
        assertEquals(2, Regex("@article\\{").findAll(list).count())
    }
}
