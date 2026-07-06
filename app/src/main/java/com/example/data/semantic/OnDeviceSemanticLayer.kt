package com.example.data.semantic

import android.content.Context
import com.example.data.embedding.VectorSearch
import com.example.data.embedding.VectorSearch.toByteArray
import com.example.data.embedding.VectorSearch.toFloatArray
import com.example.data.local.SemanticCacheDao
import com.example.data.local.SemanticCacheEntity
import com.example.domain.model.Bookmark
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.security.MessageDigest
import java.util.UUID

/** A cache hit ready to be shown to the user without an xAI call. */
data class CachedAnswer(
    val entryId: String,
    val response: String,
    val similarity: Float,
    val modelTier: String
)

/**
 * On-device semantic layer: response cache + RAG compression + complexity routing. Fully local
 * and single-user, this replaces the old Python HTTP sidecar. The caller embeds the query once
 * (on-device EmbeddingGemma) and threads the vector through lookup / compress / store so nothing
 * is embedded more than necessary.
 *
 * Caching is only appropriate for answers that don't depend on live web/X/news search (those are
 * time-sensitive); the caller gates [lookup]/[store] on that.
 */
class OnDeviceSemanticLayer(
    private val context: Context,
    private val cacheDao: SemanticCacheDao,
    private val router: ComplexityRouter = ComplexityRouter(),
    private val compressor: RagCompressor = RagCompressor(),
    private val ttlMillis: Long = DEFAULT_TTL_MILLIS,
    private val maxEntriesPerUser: Int = DEFAULT_MAX_ENTRIES
) {
    fun isEnabled(): Boolean = SemanticPreference.isEnabled(context)

    fun setEnabled(enabled: Boolean) = SemanticPreference.setEnabled(context, enabled)

    /** Complexity → xAI reasoning effort + display tier. */
    fun route(query: String): RouteDecision = router.route(query)

    /** MMR-compress retrieved RAG context. No-op passthrough when the query wasn't embedded. */
    fun compress(queryEmbedding: FloatArray?, scored: List<Pair<Bookmark, FloatArray>>): List<Bookmark> {
        if (queryEmbedding == null || queryEmbedding.isEmpty()) return scored.map { it.first }
        return compressor.compress(queryEmbedding, scored)
    }

    /** Returns a cached answer for a semantically-equivalent past query, or null. */
    suspend fun lookup(query: String, queryEmbedding: FloatArray?, userId: String?): CachedAnswer? =
        withContext(Dispatchers.IO) {
            val uid = userId.orEmpty()
            val now = System.currentTimeMillis()
            cacheDao.deleteExpired(now)

            // 1. Exact-hash fast path (verbatim repeat of the same query).
            val hash = hashQuery(query, uid)
            cacheDao.findByHash(uid, hash)?.let { entry ->
                if (entry.expiresAt > now) {
                    cacheDao.touch(entry.id, now)
                    return@withContext CachedAnswer(entry.id, entry.response, 1f, entry.modelTier)
                }
            }

            // 2. Semantic match over this user's cached queries.
            if (queryEmbedding == null || queryEmbedding.isEmpty()) return@withContext null
            val candidates = cacheDao.getVectors(uid, now)
                .mapNotNull { v -> v.embedding?.let { v.id to it.toFloatArray() } }
            if (candidates.isEmpty()) return@withContext null

            val best = VectorSearch.topKScored(queryEmbedding, candidates, k = 1, minSimilarity = 0f)
                .firstOrNull() ?: return@withContext null
            val (bestId, sim) = best
            if (sim < SemanticPreference.getCacheThreshold(context)) return@withContext null
            val entry = cacheDao.getById(bestId)?.takeIf { it.expiresAt > now } ?: return@withContext null
            cacheDao.touch(entry.id, now)
            CachedAnswer(entry.id, entry.response, sim, entry.modelTier)
        }

    /** Write-through store after a fresh xAI answer. Upserts by hash to avoid duplicates. */
    suspend fun store(
        query: String,
        queryEmbedding: FloatArray?,
        response: String,
        userId: String?,
        modelTier: String
    ): String? = withContext(Dispatchers.IO) {
        if (response.isBlank()) return@withContext null
        val uid = userId.orEmpty()
        val now = System.currentTimeMillis()
        val hash = hashQuery(query, uid)

        val existing = cacheDao.findByHash(uid, hash)
        val id = existing?.id ?: UUID.randomUUID().toString()
        cacheDao.upsert(
            SemanticCacheEntity(
                id = id,
                userId = uid,
                queryText = query,
                queryHash = hash,
                embedding = queryEmbedding?.takeIf { it.isNotEmpty() }?.toByteArray(),
                response = response,
                modelTier = modelTier,
                createdAt = now,
                lastAccessAt = now,
                expiresAt = now + ttlMillis,
                hitCount = existing?.hitCount ?: 0
            )
        )

        // LRU cap: drop the least-recently-used overflow for this user.
        val overflow = cacheDao.count(uid) - maxEntriesPerUser
        if (overflow > 0) {
            cacheDao.oldestIds(uid, overflow).forEach { cacheDao.deleteById(it) }
        }
        id
    }

    /**
     * Feedback on a served cache hit. Thumbs-down deletes the offending entry (so it is never
     * re-served) and nudges the global hit threshold up toward the rejected similarity — the
     * Python calibrator's intent, minus the global grid search.
     */
    suspend fun feedback(entryId: String, accepted: Boolean, similarity: Float): Unit =
        withContext(Dispatchers.IO) {
            if (accepted) return@withContext
            cacheDao.deleteById(entryId)
            if (similarity > 0f) {
                val current = SemanticPreference.getCacheThreshold(context)
                val target = similarity + 0.02f
                val next = current + THRESHOLD_BETA * (target - current)
                if (next > current) SemanticPreference.setCacheThreshold(context, next)
            }
        }

    private fun hashQuery(query: String, userId: String): String {
        val payload = "${query.trim().lowercase()}|$userId"
        val digest = MessageDigest.getInstance("SHA-256").digest(payload.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }.substring(0, 16)
    }

    private companion object {
        const val THRESHOLD_BETA = 0.30f
        const val DEFAULT_MAX_ENTRIES = 500
        val DEFAULT_TTL_MILLIS = 24L * 60 * 60 * 1000 // 24h
    }
}
