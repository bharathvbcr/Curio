package com.example.domain.model

import org.json.JSONArray
import org.json.JSONObject

/**
 * Which field of a [Bookmark] a [SpaceRule] inspects. [label] is the user-facing name shown in the
 * rule builder. The ordinal/name is what gets persisted, so order may grow but existing values must
 * keep their [name].
 */
enum class RuleField(val label: String) {
    KEYWORD("Text"),      // raw text, title, summary, OCR, source title/abstract
    TAG("Tag"),
    CATEGORY("Category"), // AI-assigned category
    SOURCE("Source"),     // resolved primary source type (ARXIV, GITHUB, …)
    AUTHOR("Author"),     // tweet author or resolved paper authors
    URL("Link");
}

/** How a [SpaceRule] compares its [SpaceRule.value] against the chosen [RuleField]. */
enum class RuleOp(val label: String) {
    CONTAINS("contains"),
    EQUALS("is"),
    STARTS_WITH("starts with");
}

/** Whether a Space's rule set fires when ANY rule matches or only when ALL of them do. */
enum class RuleMatch { ANY, ALL }

/**
 * A single auto-filing condition: "[field] [op] [value]", e.g. KEYWORD CONTAINS "diffusion".
 * Matching is always case-insensitive; a blank [value] never matches (and is treated as a draft).
 */
data class SpaceRule(
    val field: RuleField,
    val op: RuleOp,
    val value: String
) {
    fun matches(b: Bookmark): Boolean {
        val needle = value.trim()
        if (needle.isEmpty()) return false
        return when (field) {
            RuleField.KEYWORD -> listOfNotNull(
                b.text, b.title, b.summary, b.ocrText, b.sourceTitle, b.sourceAbstract
            ).any { test(it, needle) }
            RuleField.TAG -> b.tags.any { test(it, needle) }
            RuleField.CATEGORY -> b.category?.let { test(it, needle) } ?: false
            RuleField.SOURCE -> b.sourceType?.name?.let { test(it, needle) } ?: false
            RuleField.AUTHOR -> listOfNotNull(b.authorName, b.authorUsername, b.sourceAuthors)
                .any { test(it, needle) }
            RuleField.URL -> b.url?.let { test(it, needle) } ?: false
        }
    }

    private fun test(haystack: String, needle: String): Boolean = when (op) {
        RuleOp.CONTAINS -> haystack.contains(needle, ignoreCase = true)
        RuleOp.EQUALS -> haystack.equals(needle, ignoreCase = true)
        RuleOp.STARTS_WITH -> haystack.startsWith(needle, ignoreCase = true)
    }
}

/**
 * The full rule configuration attached to a Space ("Smart Space"). [autoFile] gates whether
 * matching bookmarks are filed automatically (on analysis / sync / login backfill); when off the
 * rules are inert until the user taps "Apply rules". Persisted as a compact JSON blob on the entity
 * via [toJson] / [fromJson] so no extra table or per-rule migration is needed.
 */
data class SpaceRules(
    val match: RuleMatch = RuleMatch.ANY,
    val autoFile: Boolean = true,
    val rules: List<SpaceRule> = emptyList()
) {
    /** Rules that actually carry a value — drafts with an empty value are ignored when matching. */
    private val effective: List<SpaceRule> get() = rules.filter { it.value.isNotBlank() }

    /** True when this Space has at least one usable rule (i.e. it's a "smart" Space). */
    val isActive: Boolean get() = effective.isNotEmpty()

    /** Whether [b] should be filed here. Always false for an empty/inactive rule set. */
    fun matches(b: Bookmark): Boolean = matchScore(b) > 0

    /**
     * How many rules matched [b]; 0 when the set doesn't match. Used to pick the best Smart Space
     * when several qualify (more matching rules = more specific intent).
     */
    fun matchScore(b: Bookmark): Int {
        val active = effective
        if (active.isEmpty()) return 0
        val hits = active.count { it.matches(b) }
        return when (match) {
            RuleMatch.ANY -> if (hits > 0) hits else 0
            RuleMatch.ALL -> if (hits == active.size) active.size else 0
        }
    }

    fun toJson(): String {
        if (rules.isEmpty()) return ""
        val arr = JSONArray()
        rules.forEach { r ->
            arr.put(
                JSONObject()
                    .put("f", r.field.name)
                    .put("o", r.op.name)
                    .put("v", r.value)
            )
        }
        return JSONObject()
            .put("m", match.name)
            .put("a", autoFile)
            .put("r", arr)
            .toString()
    }

    companion object {
        val EMPTY = SpaceRules()

        /** Tolerant parser — any malformed/blank input yields [EMPTY] rather than throwing. */
        fun fromJson(raw: String?): SpaceRules {
            if (raw.isNullOrBlank()) return EMPTY
            return try {
                val obj = JSONObject(raw)
                val match = runCatching { RuleMatch.valueOf(obj.optString("m", "ANY")) }
                    .getOrDefault(RuleMatch.ANY)
                val autoFile = obj.optBoolean("a", true)
                val arr = obj.optJSONArray("r") ?: JSONArray()
                val rules = (0 until arr.length()).mapNotNull { i ->
                    val o = arr.optJSONObject(i) ?: return@mapNotNull null
                    val field = runCatching { RuleField.valueOf(o.optString("f")) }.getOrNull()
                        ?: return@mapNotNull null
                    val op = runCatching { RuleOp.valueOf(o.optString("o")) }.getOrNull()
                        ?: return@mapNotNull null
                    SpaceRule(field, op, o.optString("v"))
                }
                SpaceRules(match, autoFile, rules)
            } catch (e: Exception) {
                EMPTY
            }
        }
    }
}
