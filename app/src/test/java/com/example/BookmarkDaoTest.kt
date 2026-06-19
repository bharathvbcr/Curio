package com.example

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.example.data.local.AppDatabase
import com.example.data.local.BookmarkDao
import com.example.data.local.BookmarkEntity
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * In-memory Room DAO test covering the query surface added for the checklist
 * (search / byCategory / categories / unenriched / observeAll) plus upsert + round-trip.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class BookmarkDaoTest {

    private lateinit var db: AppDatabase
    private lateinit var dao: BookmarkDao

    private val uid = "u1"

    @Before
    fun setup() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        dao = db.bookmarkDao()
    }

    @After
    fun teardown() = db.close()

    private fun entity(
        id: String,
        text: String = "text $id",
        category: String? = null,
        summary: String? = null,
        ocrText: String? = null,
        isAnalyzed: Boolean = false,
        createdAt: Long = id.hashCode().toLong()
    ) = BookmarkEntity(
        id = id, text = text, createdAt = createdAt, userId = uid,
        category = category, summary = summary, ocrText = ocrText, isAnalyzed = isAnalyzed
    )

    @Test
    fun `upsert and observe round-trip`() = runTest {
        dao.insertBookmarks(listOf(entity("1"), entity("2")))
        // Upsert (REPLACE) updates the existing row rather than duplicating.
        dao.insertBookmarks(listOf(entity("1", text = "updated")))
        val all = dao.getBookmarks(uid).first()
        assertEquals(2, all.size)
        assertEquals("updated", all.first { it.id == "1" }.text)
    }

    @Test
    fun `search matches text, ocr and summary`() = runTest {
        dao.insertBookmarks(
            listOf(
                entity("1", text = "Mamba selective state spaces"),
                entity("2", text = "unrelated", ocrText = "FlashAttention kernel"),
                entity("3", text = "unrelated", summary = "About PagedAttention serving")
            )
        )
        assertEquals(listOf("1"), dao.search(uid, "Mamba").first().map { it.id })
        assertEquals(listOf("2"), dao.search(uid, "FlashAttention").first().map { it.id })
        assertEquals(listOf("3"), dao.search(uid, "PagedAttention").first().map { it.id })
    }

    @Test
    fun `byCategory and categories`() = runTest {
        dao.insertBookmarks(
            listOf(
                entity("1", category = "training"),
                entity("2", category = "training"),
                entity("3", category = "inference-opt"),
                entity("4", category = null)
            )
        )
        assertEquals(2, dao.byCategory(uid, "training").first().size)
        assertEquals(listOf("inference-opt", "training"), dao.categories(uid).first())
    }

    @Test
    fun `unenriched returns only un-analyzed or un-summarized`() = runTest {
        dao.insertBookmarks(
            listOf(
                entity("1", isAnalyzed = true, summary = "done"),
                entity("2", isAnalyzed = false),
                entity("3", isAnalyzed = true, summary = null)
            )
        )
        val ids = dao.unenriched(uid).map { it.id }.toSet()
        assertEquals(setOf("2", "3"), ids)
        assertTrue("1" !in ids)
    }
}
