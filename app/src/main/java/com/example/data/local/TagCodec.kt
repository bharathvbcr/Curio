package com.example.data.local

import org.json.JSONArray

/**
 * Canonical owner of the bookmark `tags` column encoding.
 *
 * Tags were historically stored as comma-separated CSV, which silently corrupts any tag that
 * itself contains a comma (LLM analyzers emit such tags regularly): "ml, transformers" stored
 * next to "ai" round-trips as three tags. New writes are JSON arrays; the decoder still reads
 * legacy CSV rows so no migration or data rewrite is needed.
 */
object TagCodec {

    /** Encodes tags as a JSON array; null for an effectively-empty list (column stays unset). */
    fun encode(tags: List<String>): String? {
        val cleaned = tags.map { it.trim() }.filter { it.isNotEmpty() }
        if (cleaned.isEmpty()) return null
        return JSONArray(cleaned).toString()
    }

    /**
     * Decodes a stored value: JSON array first (current format), legacy CSV fallback for rows
     * written before the format switch. Corrupt JSON degrades to an empty list rather than throwing.
     */
    fun decode(raw: String?): List<String> {
        if (raw.isNullOrBlank()) return emptyList()
        val trimmed = raw.trim()
        if (trimmed.startsWith("[")) {
            return runCatching {
                val arr = JSONArray(trimmed)
                (0 until arr.length()).map { arr.optString(it).trim() }.filter { it.isNotEmpty() }
            }.getOrDefault(emptyList())
        }
        return trimmed.split(",").map { it.trim() }.filter { it.isNotEmpty() }
    }
}
