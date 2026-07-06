package com.example.data.local

import androidx.room.ColumnInfo
import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query

/**
 * On-device semantic response cache. Stores `(query embedding → past AI answer)` so a
 * semantically-equivalent question can skip the xAI round-trip. Fully local and single-user
 * (rows are scoped by [userId]), so there is no cross-user exposure to worry about — this is
 * the on-device replacement for the old Python sidecar cache.
 *
 * [embedding] is the EmbeddingGemma query vector as a little-endian Float32 blob, encoded with
 * [com.example.data.embedding.VectorSearch.toByteArray] (same format as bookmark embeddings).
 */
@Entity(
    tableName = "semantic_cache",
    indices = [
        Index(value = ["userId", "queryHash"]),
        Index(value = ["userId"]),
        Index(value = ["expiresAt"])
    ]
)
data class SemanticCacheEntity(
    @PrimaryKey val id: String,
    // "" for the anonymous/no-account case, so `= :userId` matches (NULL never does).
    val userId: String,
    val queryText: String,
    val queryHash: String,
    val embedding: ByteArray? = null,
    val response: String,
    val modelTier: String = "",
    val createdAt: Long,
    val lastAccessAt: Long,
    val expiresAt: Long,
    val hitCount: Int = 0
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is SemanticCacheEntity) return false
        return id == other.id
    }

    override fun hashCode(): Int = id.hashCode()
}

/** Lightweight projection for the cosine scan (avoids materializing full rows). */
data class SemanticCacheVector(
    @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "embedding") val embedding: ByteArray?
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is SemanticCacheVector) return false
        return id == other.id
    }

    override fun hashCode(): Int = id.hashCode()
}

@Dao
interface SemanticCacheDao {

    @Query("SELECT * FROM semantic_cache WHERE userId = :userId AND queryHash = :hash LIMIT 1")
    suspend fun findByHash(userId: String, hash: String): SemanticCacheEntity?

    @Query("SELECT * FROM semantic_cache WHERE id = :id LIMIT 1")
    suspend fun getById(id: String): SemanticCacheEntity?

    @Query("SELECT id, embedding FROM semantic_cache WHERE userId = :userId AND expiresAt > :now")
    suspend fun getVectors(userId: String, now: Long): List<SemanticCacheVector>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entry: SemanticCacheEntity)

    @Query("UPDATE semantic_cache SET hitCount = hitCount + 1, lastAccessAt = :now WHERE id = :id")
    suspend fun touch(id: String, now: Long)

    @Query("DELETE FROM semantic_cache WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM semantic_cache WHERE expiresAt <= :now")
    suspend fun deleteExpired(now: Long)

    @Query("SELECT COUNT(*) FROM semantic_cache WHERE userId = :userId")
    suspend fun count(userId: String): Int

    @Query("SELECT id FROM semantic_cache WHERE userId = :userId ORDER BY lastAccessAt ASC LIMIT :limit")
    suspend fun oldestIds(userId: String, limit: Int): List<String>
}
