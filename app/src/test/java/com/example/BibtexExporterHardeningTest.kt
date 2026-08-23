package com.example

import com.example.data.export.BibtexExporter
import com.example.domain.model.Bookmark
import com.example.domain.model.SourceType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.Calendar
import java.util.TimeZone

/**
 * Hardening tests for citation export: LaTeX metacharacter escaping, UTC year derivation with a
 * sane fallback for the legacy epoch-0 sentinel, and BibTeX key uniqueness in list exports.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class BibtexExporterHardeningTest {

    private fun bookmark(
        title: String,
        createdAt: Long,
        authors: String? = "Ada Lovelace",
        extra: String? = null
    ) = Bookmark(
        id = "t1", text = "body", createdAt = createdAt, userId = "u1",
        sourceType = SourceType.ARXIV, sourceId = "2312.00752",
        sourceTitle = title, sourceAuthors = authors,
        sourceExtra = extra ?: """{"published":"2023-12-01","categories":["cs.LG"]}"""
    )

    @Test
    fun `latex special characters are escaped`() {
        val dollar = '$'
        val title = "Scaling Laws \\& Robustness: 100% {curly} #tags _under_ ${dollar}p${dollar}"
        val b = BibtexExporter.toBibtex(bookmark(title, 1_700_000_000_000L))!!
        // A literal backslash must be typeset via \textbackslash{}, not doubled (\\ is a
        // line-break command in LaTeX) — and the & after it still needs its own escape.
        assertTrue(
            "expected \\textbackslash{}\\& in:\n$b",
            b.contains("Scaling Laws \\textbackslash{}\\&")
        )
        assertTrue(b.contains("100\\%"))
        assertFalse(Regex("\\{curly}").containsMatchIn(b)) // raw braces break .bib grouping
        assertTrue(b.contains("\\{curly\\}"))
        assertTrue(b.contains("\\#tags"))
        assertTrue(b.contains("\\_under\\_"))
        // $p$ → \$p\$
        assertTrue(b.contains("\\" + dollar + "p\\" + dollar))
    }

    @Test
    fun `epoch zero sentinel falls back to current year not 1970`() {
        val expectedYear = Calendar.getInstance(TimeZone.getTimeZone("UTC")).get(Calendar.YEAR)
        // extra must not carry a "published" year — that path wins before the timestamp.
        val b = BibtexExporter.toBibtex(bookmark("Some Paper", createdAt = 0L, extra = "{}"))!!
        assertTrue("expected year $expectedYear in:\n$b", b.contains("year          = {$expectedYear}"))
    }

    @Test
    fun `year derives from UTC not device timezone`() {
        // 2023-12-31 23:30 UTC — a UTC+14 device would call this 2024.
        val b = BibtexExporter.toBibtex(bookmark("Year Edge", createdAt = 1_704_065_400_000L))!!
        // sourceExtra "published" wins; strip it to force the timestamp path.
        val noExtra = bookmark("Year Edge", createdAt = 1_704_065_400_000L).copy(sourceExtra = null)
        val b2 = BibtexExporter.toBibtex(noExtra)!!
        assertTrue(b2.contains("year          = {2023}"))
    }

    @Test
    fun `list export uniquifies duplicate citation keys`() {
        val one = bookmark("Attention Is All You Need", 1_700_000_001_000L)
        val two = bookmark("Attention Is All You Need", 1_700_000_002_000L)
        val list = BibtexExporter.toBibtexList(listOf(one, two))
        val keys = Regex("@article\\{([^,]+),").findAll(list).map { it.groupValues[1] }.toList()
        assertEquals(2, keys.size)
        assertEquals("duplicate BibTeX keys: $keys", keys.size, keys.toSet().size)
    }
}
