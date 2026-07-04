package com.example.data.embedding

/**
 * Embedding-driven auto-organisation engine (pure, no Android/DB dependencies so it is unit-testable).
 *
 * Given the embeddings of *unfiled* bookmarks and the per-Space "signature" (the mean vector of a
 * Space's already-filed members — its semantic centroid), it produces a [Plan] with three tiers:
 *
 *  1. [Plan.autoFile]    — high-confidence matches to an existing Space (cosine ≥ [AUTO_FILE_THRESHOLD]).
 *                          Filed automatically.
 *  2. [Plan.suggestions] — medium-confidence matches (≥ [SUGGEST_THRESHOLD]) surfaced as a per-card
 *                          suggestion the user can tap to confirm.
 *  3. [Plan.clusters]    — the leftovers (matched no existing Space) grouped by mutual similarity into
 *                          cohesive clusters that become brand-new Spaces.
 *
 * The centroid comparison *is* the "semantic Smart-Space rule": a Space is defined by what it already
 * contains, so future cards that look like its members flow into it — no keyword rule required.
 *
 * All comparisons use [VectorSearch.cosineSimilarity], which returns 0 for mismatched dimensions, so
 * mixing on-device and cloud embeddings of different sizes can never produce a spurious match.
 */
object SemanticOrganizer {

    /** Cosine at/above which an unfiled card is filed into the nearest Space automatically. */
    const val AUTO_FILE_THRESHOLD = 0.68f

    /** Cosine at/above which (but below [AUTO_FILE_THRESHOLD]) we only *suggest* the Space. */
    const val SUGGEST_THRESHOLD = 0.50f

    /** Minimum mutual cosine for two leftover cards to share a new cluster. */
    const val CLUSTER_THRESHOLD = 0.62f

    /** A cluster smaller than this isn't worth its own Space (avoids one-off "Spaces"). */
    const val MIN_CLUSTER_SIZE = 2

    /**
     * Skip connected-components clustering above this bucket size — pairwise similarity is O(n²) and
     * large leftover sets are rare; auto-file/suggest tiers still run.
     */
    const val MAX_CLUSTER_BUCKET_SIZE = 200

    /** id → Space the card should be filed into, with the cosine that earned it. */
    data class Assignment(val bookmarkId: String, val spaceId: String, val score: Float)

    /** A discovered group of mutually-similar leftovers that warrants a new Space. */
    data class Cluster(val bookmarkIds: List<String>, val centroid: FloatArray, val cohesion: Float)

    data class Plan(
        val autoFile: List<Assignment>,
        val suggestions: List<Assignment>,
        val clusters: List<Cluster>
    )

    /**
     * @param unfiled            (id, embedding) for every bookmark with no Space.
     * @param spaceCentroids     spaceId → mean vector of that Space's filed members.
     * @param spaceMemberCounts  optional filed-member counts — used to break ties when two Spaces
     *                           score equally (prefer the larger, more established Space).
     */
    fun buildPlan(
        unfiled: List<Pair<String, FloatArray>>,
        spaceCentroids: Map<String, FloatArray>,
        spaceMemberCounts: Map<String, Int> = emptyMap()
    ): Plan {
        val autoFile = mutableListOf<Assignment>()
        val suggestions = mutableListOf<Assignment>()
        val leftovers = mutableListOf<Pair<String, FloatArray>>()

        for ((id, emb) in unfiled) {
            // Empty or zero-norm vectors can't match centroids or form clusters — skip them.
            if (emb.isEmpty() || VectorSearch.normalizeL2(emb) == null) continue
            val best = spaceCentroids.entries
                .asSequence()
                .filter { (_, centroid) -> centroid.size == emb.size }
                .map { (spaceId, centroid) ->
                    Triple(
                        spaceId,
                        VectorSearch.cosineSimilarity(emb, centroid),
                        spaceMemberCounts[spaceId] ?: 0
                    )
                }
                .maxWithOrNull(
                    compareBy<Triple<String, Float, Int>> { it.second }
                        .thenBy { it.third }
                        .thenBy { it.first }
                )
            when {
                best == null || best.second < SUGGEST_THRESHOLD -> leftovers += id to emb
                best.second >= AUTO_FILE_THRESHOLD -> autoFile += Assignment(id, best.first, best.second)
                else -> suggestions += Assignment(id, best.first, best.second)
            }
        }

        return Plan(autoFile, suggestions, clusterLeftovers(leftovers))
    }

    /**
     * Connected-components clustering on the pairwise similarity graph: two leftovers share a cluster
     * when their cosine ≥ [CLUSTER_THRESHOLD], including transitive chains (A~B, B~C ⇒ one group).
     * Deterministic — clusters are sorted by their smallest bookmark id.
     */
    private fun clusterLeftovers(leftovers: List<Pair<String, FloatArray>>): List<Cluster> {
        if (leftovers.size < MIN_CLUSTER_SIZE) return emptyList()
        // Never compare across embedding dimensions (mixed on-device/cloud vectors score 0 anyway).
        return leftovers.groupBy { it.second.size }
            .flatMap { clusterLeftoversSameDim(it.value) }
            .sortedBy { it.bookmarkIds.minOrNull() }
    }

    /**
     * Connected-components on one dimension bucket. Pre-normalises vectors so pairwise checks are
     * dot products (cheaper than full cosine) without changing thresholds.
     */
    private fun clusterLeftoversSameDim(leftovers: List<Pair<String, FloatArray>>): List<Cluster> {
        val n = leftovers.size
        if (n < MIN_CLUSTER_SIZE || n > MAX_CLUSTER_BUCKET_SIZE) return emptyList()

        val normalized = leftovers.map { (_, emb) -> VectorSearch.normalizeL2(emb) }
        val parent = IntArray(n) { it }
        fun find(x: Int): Int {
            var r = x
            while (parent[r] != r) {
                parent[r] = parent[parent[r]]
                r = parent[r]
            }
            return r
        }
        fun union(a: Int, b: Int) {
            val ra = find(a)
            val rb = find(b)
            if (ra != rb) parent[rb] = ra
        }

        for (i in 0 until n) {
            val ni = normalized[i] ?: continue
            for (j in i + 1 until n) {
                val nj = normalized[j] ?: continue
                if (VectorSearch.dotProduct(ni, nj) >= CLUSTER_THRESHOLD) union(i, j)
            }
        }

        val groups = mutableMapOf<Int, MutableList<Int>>()
        for (i in 0 until n) {
            groups.getOrPut(find(i)) { mutableListOf() }.add(i)
        }

        return groups.values
            .filter { it.size >= MIN_CLUSTER_SIZE }
            .mapNotNull { indices ->
                val members = indices.map { leftovers[it] }
                val centroid = meanVector(members.map { it.second }) ?: return@mapNotNull null
                val cohesion = members
                    .map { VectorSearch.cosineSimilarity(centroid, it.second) }
                    .average().toFloat()
                Cluster(members.map { it.first }, centroid, cohesion)
            }
    }

    /** Element-wise mean; null if empty or dimensions disagree. */
    fun meanVector(vectors: List<FloatArray>): FloatArray? {
        if (vectors.isEmpty()) return null
        val dim = vectors.first().size
        if (dim == 0 || vectors.any { it.size != dim }) return null
        val acc = FloatArray(dim)
        for (v in vectors) for (j in 0 until dim) acc[j] += v[j]
        for (j in 0 until dim) acc[j] /= vectors.size
        return acc
    }
}
