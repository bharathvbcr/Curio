package com.example

import com.example.data.remote.ArxivClient
import com.example.data.remote.CrossrefClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Pure-JVM tests for the primary-source URL/ID extraction regexes that drive SourceResolver's
 * priority logic (arXiv ids, bare arXiv ids, DOIs). The audit flagged this extraction as untested.
 */
class SourceExtractionTest {

    private fun arxivId(s: String) = ArxivClient.ARXIV_ID_REGEX.find(s)?.groupValues?.get(1)
    private fun bareArxiv(s: String) = ArxivClient.ARXIV_BARE_REGEX.find(s)?.groupValues?.get(1)
    private fun doi(s: String) = CrossrefClient.DOI_REGEX.find(s)?.groupValues?.get(1)

    @Test
    fun `arxiv id from abs and pdf urls`() {
        assertEquals("2312.00752", arxivId("https://arxiv.org/abs/2312.00752"))
        assertEquals("2301.00001v2", arxivId("https://arxiv.org/pdf/2301.00001v2"))
        assertEquals("2305.12345", arxivId("see ar5iv.org/abs/2305.12345 for the rendered version"))
    }

    @Test
    fun `arxiv id regex ignores non-arxiv urls`() {
        assertNull(arxivId("https://github.com/owner/repo"))
        assertNull(arxivId("https://example.com/abs/123"))
    }

    @Test
    fun `bare arxiv id found in free text but not short decimals`() {
        assertEquals("2312.00752", bareArxiv("the Mamba paper 2312.00752 is great"))
        assertEquals("2301.00001v3", bareArxiv("2301.00001v3"))
        assertNull(bareArxiv("version 12.34 of the spec"))
    }

    @Test
    fun `doi matched in doi-org url and bare, case-insensitive`() {
        assertEquals("10.1038/s41586-021-03819-2", doi("https://doi.org/10.1038/s41586-021-03819-2"))
        assertEquals("10.1145/3292500.3330701", doi("cite 10.1145/3292500.3330701 here"))
        // DOI prefixes are case-insensitive per the regex option.
        assertEquals("10.1000/XYZ123", doi("DOI 10.1000/XYZ123"))
    }

    @Test
    fun `doi regex ignores non-doi text`() {
        assertNull(doi("just some text with 10 and a slash / but no doi"))
        assertNull(doi("https://github.com/owner/repo"))
    }
}
