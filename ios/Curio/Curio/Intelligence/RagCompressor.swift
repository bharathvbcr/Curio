import Foundation

/// Maximal-Marginal-Relevance compressor for retrieved RAG context. Given the top-K bookmarks
/// (already fetched with their EmbeddingGemma vectors), it drops near-duplicate / low-relevance
/// items and greedily selects a set under a token budget. Port of the Kotlin `RagCompressor`.
///
/// Bookmarks whose embedding is unavailable (empty vector) are appended as-is: we can't score them,
/// and dropping context silently would be worse than a slightly larger prompt.
struct RagCompressor: Sendable {
    var lambda: Float = 0.7               // relevance vs. diversity (MMR)
    var relevanceThreshold: Float = 0.25
    var maxTokens: Int = 2048
    var charsPerToken: Int = 4

    /// Returns the compressed, reordered subset of `scored` (`(bookmark, query-space vector)`).
    func compress(queryEmbedding: [Float], scored: [(bookmark: Bookmark, embedding: [Float])]) -> [Bookmark] {
        if scored.isEmpty { return [] }

        let scorable = scored.filter { !$0.embedding.isEmpty }
        let unscorable = scored.filter { $0.embedding.isEmpty }.map { $0.bookmark }
        if scorable.isEmpty { return scored.map { $0.bookmark } }

        let relevance = scorable.map { VectorSearch.cosineSimilarity(queryEmbedding, $0.embedding) }
        var eligible = Set(scorable.indices.filter { relevance[$0] >= relevanceThreshold })
        if eligible.isEmpty { eligible = Set(scorable.indices) }

        var selected: [Int] = []
        var usedTokens = 0
        while !eligible.isEmpty {
            var bestIdx = -1
            var bestScore = -Float.greatestFiniteMagnitude
            for idx in eligible {
                let maxRedundancy = selected
                    .map { VectorSearch.cosineSimilarity(scorable[idx].embedding, scorable[$0].embedding) }
                    .max() ?? 0
                let mmr = lambda * relevance[idx] - (1 - lambda) * maxRedundancy
                if mmr > bestScore {
                    bestScore = mmr
                    bestIdx = idx
                }
            }
            if bestIdx < 0 { break }

            let tokens = estimateTokens(scorable[bestIdx].bookmark)
            eligible.remove(bestIdx)
            // Always admit the first pick even if it alone exceeds the budget, so we never return an
            // empty context; afterwards, respect the budget.
            if !selected.isEmpty && usedTokens + tokens > maxTokens { continue }
            selected.append(bestIdx)
            usedTokens += tokens
            if usedTokens >= maxTokens { break }
        }

        return selected.map { scorable[$0].bookmark } + unscorable
    }

    private func estimateTokens(_ b: Bookmark) -> Int {
        let chars = (b.title?.count ?? 0) + (b.summary?.count ?? 0) + (b.deepSummary?.count ?? 0) + b.text.count
        return max(chars / charsPerToken, 1)
    }
}
