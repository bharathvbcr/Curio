package com.example.data.semantic

import com.example.data.remote.GrokReasoning

/**
 * Query-complexity router. The app generates via a single xAI flagship model rather than a
 * pool of local models, so complexity is mapped to xAI's `reasoning_effort` (thinking-token
 * budget) instead of a model tier: simple asks answer fast and cheap, complex asks get deeper
 * reasoning. Ported from the Python `semantic_router` (length + syntax + lexical richness; the
 * embedding "domain" signal is dropped since there's no complex-example centroid on-device).
 */
data class RouteDecision(
    val tier: String,            // "fast" | "deep" — surfaced in the chat UI
    val reasoningEffort: String, // GrokReasoning.* — fed to xAI
    val complexityScore: Float
)

class ComplexityRouter(
    private val complexityThreshold: Float = 0.45f,
    private val lengthSaturationTokens: Int = 100,
    private val richnessSaturationTokens: Int = 60
) {
    fun route(query: String): RouteDecision {
        val tokens = query.split(WHITESPACE).filter { it.isNotEmpty() }
        val nTokens = tokens.size

        val length = (nTokens.toFloat() / lengthSaturationTokens).coerceAtMost(1f)

        var syntax = 0f
        if (CODE_PATTERN.containsMatchIn(query)) syntax += 0.6f
        if (MULTI_STEP_PATTERN.containsMatchIn(query)) syntax += 0.4f
        syntax = syntax.coerceAtMost(1f)

        val distinct = tokens.map { it.lowercase() }.toSet().size
        val richness = (distinct.toFloat() / richnessSaturationTokens).coerceAtMost(1f)

        // Weights (0.30/0.40/0.30) redistribute the Python model's domain weight across the
        // three signals that survive on-device; they sum to 1 so the threshold stays comparable.
        val score = 0.30f * length + 0.40f * syntax + 0.30f * richness

        return if (score >= complexityThreshold) {
            RouteDecision("deep", GrokReasoning.HIGH, score)
        } else {
            RouteDecision("fast", GrokReasoning.LOW, score)
        }
    }

    private companion object {
        val WHITESPACE = Regex("\\s+")
        val CODE_PATTERN = Regex(
            "```|def |class |function |import |SELECT |for \\(|while \\(",
            RegexOption.IGNORE_CASE
        )
        val MULTI_STEP_PATTERN = Regex(
            "\\b(step \\d|first,|second,|then |finally |compare |analyze |explain why|prove )\\b",
            RegexOption.IGNORE_CASE
        )
    }
}
