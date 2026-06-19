package com.example.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface SpaceDao {
    // Pinned Spaces float to the top; within each group manual sortIndex wins, newest as tiebreak.
    @Query("SELECT * FROM spaces WHERE userId = :userId ORDER BY isPinned DESC, sortIndex ASC, createdAt DESC")
    fun getSpaces(userId: String): Flow<List<SpaceEntity>>

    @Query("SELECT * FROM spaces WHERE userId = :userId ORDER BY isPinned DESC, sortIndex ASC, createdAt DESC")
    suspend fun getSpacesDirect(userId: String): List<SpaceEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertSpace(space: SpaceEntity)

    @Query("DELETE FROM spaces WHERE id = :id")
    suspend fun deleteSpace(id: String)

    @Query("SELECT * FROM spaces WHERE id = :id")
    suspend fun getSpaceById(id: String): SpaceEntity?

    @Query("UPDATE spaces SET isPinned = :pinned WHERE id = :id")
    suspend fun setPinned(id: String, pinned: Boolean)

    @Query("UPDATE spaces SET sortIndex = :sortIndex WHERE id = :id")
    suspend fun setSortIndex(id: String, sortIndex: Int)
}
