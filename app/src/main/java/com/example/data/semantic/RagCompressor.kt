package com.example.data.semantic

import com.example.data.embedding.VectorSearch
import com.example.domain.model.Bookmark

/**
 * Maximal-Marginal-Relevance compressor for retrieved RAG context. Given the top-K bookmarks
 * (already fetched with their EmbeddingGemma vectors), it drops near-duplicate / low-relevance
 * items and greedily selects a set that stays under a token budget — trading a little recall for
 * a tighter, less repetitive prompt. Ported from the Python `semantic_compressor`.
 *
 * Bookmarks whose embedding is unavailable (empty vector) are kept as-is at the end: we can't
 * score them, and dropping context silently would be worse than a slightly larger prompt.
 */
class RagCompressor(
    private val lambda: Float = 0.7f,          // relevance vs. diversity (MMR)
    private val relevanceThreshold: Float = 0.25f,
    private val maxTokens: Int = 2048,
    private val charsPerToken: Int = 4
) {
    /** Returns the compressed, reordered subset of [scored] (input is `bookmark → query-space vector`). */
    fun compress(queryEmbedding: FloatArray, scored: List<Pair<Bookmark, FloatArray>>): List<Bookmark> {
        if (scored.isEmpty()) return emptyList()

        val scorable = scored.filter { it.second.isNotEmpty() }
        val unscorable = scored.filter { it.second.isEmpty() }.map { it.first }
        if (scorable.isEmpty()) return scored.map { it.first }

        val relevance = scorable.map { VectorSearch.cosineSimilarity(queryEmbedding, it.second) }
        val eligible = scorable.indices.filter { relevance[it] >= relevanceThreshold }.toMutableSet()
        // If the floor drops everything, fall back to pure MMR over all scorable items.
        if (eligible.isEmpty()) eligible.addAll(scorable.indices)

        val selected = mutableListOf<Int>()
        var usedTokens = 0
        while (eligible.isNotEmpty()) {
            var bestIdx = -1
            var bestScore = Float.NEGATIVE_INFINITY
            for (idx in eligible) {
                val maxRedundancy = selected.maxOfOrNull { s ->
                    VectorSearch.cosineSimilarity(scorable[idx].second, scorable[s].second)
                } ?: 0f
                val mmr = lambda * relevance[idx] - (1 - lambda) * maxRedundancy
                if (mmr > bestScore) {
                    bestScore = mmr
                    bestIdx = idx
                }
            }
            if (bestIdx < 0) break

            val tokens = estimateTokens(scorable[bestIdx].first)
            eligible.remove(bestIdx)
            // Always admit the first pick even if it alone exceeds the budget, so we never
            // return an empty context; afterwards, respect the budget.
            if (selected.isNotEmpty() && usedTokens + tokens > maxTokens) continue
            selected.add(bestIdx)
            usedTokens += tokens
            if (usedTokens >= maxTokens) break
        }

        return selected.map { scorable[it].first } + unscorable
    }

    private fun estimateTokens(b: Bookmark): Int {
        val chars = (b.title?.length ?: 0) +
            (b.summary?.length ?: 0) +
            (b.deepSummary?.length ?: 0) +
            b.text.length
        return (chars / charsPerToken).coerceAtLeast(1)
    }
}
