package com.example

import com.example.data.local.TagCodec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Tag column encoding tests: JSON-array writes must round-trip tags containing commas (LLM
 * analyzers emit them), while legacy CSV rows keep reading exactly as before.
 */
class TagCodecTest {

    @Test
    fun `round-trips tags containing commas`() {
        val tags = listOf("machine learning, transformers", "attention", "  spaced  ")
        val encoded = TagCodec.encode(tags)!!
        assertEquals(listOf("machine learning, transformers", "attention", "spaced"), TagCodec.decode(encoded))
    }

    @Test
    fun `encode trims and drops blank entries`() {
        assertEquals("""["a","b"]""", TagCodec.encode(listOf("", " a ", "  ", "b")))
    }

    @Test
    fun `empty list encodes to null and null decodes to empty`() {
        assertNull(TagCodec.encode(emptyList()))
        assertNull(TagCodec.encode(listOf("   ", "")))
        assertEquals(emptyList<String>(), TagCodec.decode(null))
        assertEquals(emptyList<String>(), TagCodec.decode(""))
        assertEquals(emptyList<String>(), TagCodec.decode("   "))
    }

    @Test
    fun `legacy csv rows still decode`() {
        assertEquals(listOf("ml", "ai"), TagCodec.decode("ml,ai"))
        // A legacy tag that itself contained a comma was already split at write time; the
        // reader preserves that historical behavior rather than inventing new splits.
        assertEquals(listOf("a", "b c", "d"), TagCodec.decode("a,b c,d"))
    }

    @Test
    fun `corrupt json degrades to empty not crash`() {
        assertEquals(emptyList<String>(), TagCodec.decode("[broken"))
    }
}
