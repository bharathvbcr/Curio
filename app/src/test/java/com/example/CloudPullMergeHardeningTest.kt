package com.example

import com.example.data.repo.BookmarkRepositoryImpl
import com.example.data.local.BookmarkEntity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Pure-merge tests for the cloud-pull reconciliation. The push payload intentionally omits
 * body text (PII stays on-device), so a pull can never restore text — rows that exist only in
 * the cloud and carry no displayable content at all must not be materialised as empty cards,
 * and locally-explicit favourite/save state must survive a stale cloud copy.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE)
class CloudPullMergeHardeningTest {

    private fun fresh(
        id: String, text: String = "", title: String? = null, url: String? = null,
        favorite: Boolean = false, saved: Boolean = false
    ) = BookmarkEntity(
        id = id, text = text, createdAt = 1_700_000_000_000L, userId = "u1",
        title = title, url = url, isFavorite = favorite, isSavedForLater = saved
    )

    @Test
    fun `content-less cloud-only row is dropped`() {
        val merged = BookmarkRepositoryImpl.mergeCloudPull(
            existingById = emptyMap(),
            fresh = listOf(fresh("zombie"))
        )
        assertTrue("zombie row must not be materialised", merged.isEmpty())
    }

    @Test
    fun `cloud-only row with title or url survives`() {
        val merged = BookmarkRepositoryImpl.mergeCloudPull(
            existingById = emptyMap(),
            fresh = listOf(fresh("withTitle", title = "A Title"), fresh("withUrl", url = "https://x.ai"))
        )
        assertEquals(2, merged.size)
    }

    @Test
    fun `local explicit unfavorite wins over stale cloud favourite`() {
        val local = fresh("b1", text = "body", favorite = false)
        val cloud = fresh("b1", favorite = true)
        val merged = BookmarkRepositoryImpl.mergeCloudPull(
            existingById = mapOf("b1" to local),
            fresh = listOf(cloud)
        )
        val row = merged.single { it.id == "b1" }
        assertEquals(false, row.isFavorite)
    }

    @Test
    fun `local unsave-for-later wins over stale cloud flag`() {
        val local = fresh("b2", text = "body", saved = false)
        val cloud = fresh("b2", saved = true)
        val merged = BookmarkRepositoryImpl.mergeCloudPull(
            existingById = mapOf("b2" to local),
            fresh = listOf(cloud)
        )
        assertEquals(false, merged.single { it.id == "b2" }.isSavedForLater)
    }

    @Test
    fun `local enrichment is preserved and gaps filled from cloud`() {
        val local = BookmarkEntity(
            id = "b3", text = "real body", createdAt = 1L, userId = "u1",
            summary = "local summary", spaceId = "space_9", notes = "mine"
        )
        val cloud = BookmarkEntity(
            id = "b3", text = "", createdAt = 1L, userId = "u1",
            title = "cloud title", url = "https://example.com"
        )
        val merged = BookmarkRepositoryImpl.mergeCloudPull(
            existingById = mapOf("b3" to local),
            fresh = listOf(cloud)
        ).single { it.id == "b3" }
        assertEquals("local summary", merged.summary)
        assertEquals("cloud title", merged.title)
        assertEquals("space_9", merged.spaceId)
        assertEquals("mine", merged.notes)
    }

    // ── Last-writer-wins (updatedAt stamps) ──────────────────────────────────

    @Test
    fun `provably newer cloud content wins`() {
        val local = BookmarkEntity(
            id = "lww1", text = "old body", createdAt = 1L, userId = "u1",
            updatedAt = 1_000L
        )
        val cloud = BookmarkEntity(
            id = "lww1", text = "new body from X sync mirror", createdAt = 1L, userId = "u1",
            summary = "fresh summary"
        )
        val merged = BookmarkRepositoryImpl.mergeCloudPull(
            existingById = mapOf("lww1" to local),
            fresh = listOf(cloud),
            cloudUpdatedAtById = mapOf("lww1" to 2_000L)
        ).single { it.id == "lww1" }
        assertEquals("new body from X sync mirror", merged.text)
        assertEquals("fresh summary", merged.summary)
        // Merged row carries the newer stamp.
        assertEquals(2_000L, merged.updatedAt)
    }

    @Test
    fun `newer blank cloud payload never erases local body`() {
        // Regression: the push payload omits `text`, and its serverTimestamp lands after every
        // local write's stamp — an unguarded recency copy-in used to blank local bodies.
        val local = BookmarkEntity(
            id = "blank1", text = "precious manual note", createdAt = 1L, userId = "u1",
            updatedAt = 1_000L
        )
        val cloud = BookmarkEntity(id = "blank1", text = "", createdAt = 1L, userId = "u1")
        val merged = BookmarkRepositoryImpl.mergeCloudPull(
            existingById = mapOf("blank1" to local),
            fresh = listOf(cloud),
            // Cloud stamp newer than local — the exact race that caused the wipe.
            cloudUpdatedAtById = mapOf("blank1" to 9_999L)
        ).single { it.id == "blank1" }
        assertEquals("precious manual note", merged.text)
    }

    @Test
    fun `local newer keeps local content over stale cloud`() {
        val local = BookmarkEntity(
            id = "lww2", text = "local edit", createdAt = 1L, userId = "u1",
            summary = "local analysis", updatedAt = 5_000L
        )
        val cloud = BookmarkEntity(
            id = "lww2", text = "stale body", createdAt = 1L, userId = "u1",
            summary = "stale analysis"
        )
        val merged = BookmarkRepositoryImpl.mergeCloudPull(
            existingById = mapOf("lww2" to local),
            fresh = listOf(cloud),
            cloudUpdatedAtById = mapOf("lww2" to 3_000L)
        ).single { it.id == "lww2" }
        assertEquals("local edit", merged.text)
        assertEquals("local analysis", merged.summary)
        assertEquals(5_000L, merged.updatedAt)
    }

    @Test
    fun `favorites stay local even when cloud is newer`() {
        val local = BookmarkEntity(
            id = "fav1", text = "body", createdAt = 1L, userId = "u1",
            isFavorite = false, updatedAt = 1_000L
        )
        val cloud = BookmarkEntity(
            id = "fav1", text = "body", createdAt = 1L, userId = "u1",
            isFavorite = true
        )
        val merged = BookmarkRepositoryImpl.mergeCloudPull(
            existingById = mapOf("fav1" to local),
            fresh = listOf(cloud),
            cloudUpdatedAtById = mapOf("fav1" to 9_000L)
        ).single { it.id == "fav1" }
        assertEquals(false, merged.isFavorite)
    }
}
