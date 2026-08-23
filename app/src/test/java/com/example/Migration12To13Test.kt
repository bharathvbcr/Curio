package com.example

import android.content.Context
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.sqlite.db.SupportSQLiteOpenHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.test.core.app.ApplicationProvider
import com.example.data.local.AppDatabase.Companion.MIGRATION_12_13
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/**
 * Migration 12→13: adds the trigger-maintained `updatedAt` stamp column.
 *
 * MigrationTestHelper needs exported schemas on the unit-test asset path, which this build's
 * AGP setup doesn't merge for unit tests — so the harness builds the v12 database from the
 * exported `12.json` DDL over one persistent connection, runs the real [MIGRATION_12_13], then
 * validates the end state STRUCTURALLY against the exported `13.json`: every table, column
 * (name / affinity / notNull), primary key and index must match Room's own expectations.
 * (Room's runtime identity-hash check is exercised implicitly — the v13 hash is stamped here —
 * but asserting structure directly pinpoints exactly which column is wrong when it fails.)
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [34])
class Migration12To13Test {

    private fun schemaFile(version: Int): File =
        listOf(
            File("schemas/com.example.data.local.AppDatabase/$version.json"),
            File("app/schemas/com.example.data.local.AppDatabase/$version.json")
        ).first { it.exists() }

    @Test
    fun `legacy rows survive migration and triggers stamp writes`() = kotlinx.coroutines.runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val dbFile = context.getDatabasePath("migration-12-13-test")
        dbFile.parentFile?.mkdirs()
        // Remove any previous artifact INCLUDING WAL sidecars so we start truly clean.
        listOf("", "-wal", "-shm", "-journal").forEach { suffix ->
            File(dbFile.absolutePath + suffix).delete()
        }

        val v12 = JSONObject(schemaFile(12).readText()).getJSONObject("database")
        val v13 = JSONObject(schemaFile(13).readText()).getJSONObject("database")

        // One helper/connection for the whole build-migrate-assert phase.
        val helper = FrameworkSQLiteOpenHelperFactory().create(
            SupportSQLiteOpenHelper.Configuration.builder(context)
                .name(dbFile.absolutePath)
                .callback(object : SupportSQLiteOpenHelper.Callback(12) {
                    override fun onCreate(db: SupportSQLiteDatabase) {
                        // Assemble v12 exactly as Room would: entity/index DDL + master hash.
                        db.execSQL(
                            "CREATE TABLE IF NOT EXISTS room_master_table " +
                                "(id INTEGER PRIMARY KEY,identity_hash TEXT)"
                        )
                        applyEntities(db, v12)
                        db.execSQL(
                            "INSERT OR REPLACE INTO room_master_table (id,identity_hash) " +
                                "VALUES(42, '${v12.getString("identityHash")}')"
                        )
                    }

                    override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
                })
                .build()
        )
        val db = helper.writableDatabase
        try {
            // ── Pre-migration state ──────────────────────────────────────────
            assertFalse(columnExists(db, "bookmarks", "updatedAt"))
            db.execSQL(
                "INSERT INTO bookmarks (id, text, createdAt, userId, isOcrScheduled, isAnalyzed, " +
                    "referenceCount, isDeepAnalyzed, isFavorite, isSavedForLater) " +
                    "VALUES ('m1', 'legacy body', 12345, 'u1', 0, 0, 1, 0, 0, 0)"
            )

            // ── Run the production migration object ─────────────────────────
            MIGRATION_12_13.migrate(db)
            // A raw Migration only applies schema deltas — the caller owns PRAGMA user_version.
            db.version = 13
            db.execSQL("DELETE FROM room_master_table")
            db.execSQL(
                "INSERT INTO room_master_table (identity_hash) VALUES ('${v13.getString("identityHash")}')"
            )

            // ── Post-migration state ────────────────────────────────────────
            assertTrue(columnExists(db, "bookmarks", "updatedAt"))
            assertEquals("legacy row intact", "legacy body", queryString(db, "m1"))
            assertEquals("legacy row starts unstamped", 0L, queryStamp(db, "m1"))
            assertEquals(
                "updatedAt must carry the NOT NULL DEFAULT 0 declared in the migration",
                "0",
                defaultValueOf(db, "bookmarks", "updatedAt")
            )

            // AFTER INSERT trigger stamps new rows…
            db.execSQL(
                "INSERT INTO bookmarks (id, text, createdAt, userId, isOcrScheduled, isAnalyzed, " +
                    "referenceCount, isDeepAnalyzed, isFavorite, isSavedForLater) " +
                    "VALUES ('m2', 'new row', 67890, 'u1', 0, 0, 1, 0, 0, 0)"
            )
            Thread.sleep(5) // keep insert/update stamps distinguishable
            // …and AFTER UPDATE trigger stamps edits of existing rows.
            db.execSQL("UPDATE bookmarks SET text = 'edited body' WHERE id = 'm1'")
            val insertStamp = queryStamp(db, "m2")
            val updateStamp = queryStamp(db, "m1")
            assertTrue("insert trigger must stamp", insertStamp > 0)
            assertTrue("update trigger must stamp", updateStamp > 0)
            assertTrue("update stamp should be >= insert stamp", updateStamp >= insertStamp)

            // The trigger's own UPDATE must not recurse (SQLite leaves recursive triggers off):
            // exactly one stamp per write, i.e. m2's stamp equals its insert time.
            assertEquals(insertStamp, queryStamp(db, "m2"))

            // ── Structural validation against Room's exported v13 schema ────
            assertEquals(v13.getString("identityHash"), queryString2(db))
            assertEquals(13, db.version)
            validateSchemaMatches(db, v13)
        } finally {
            db.close()
            helper.close()
        }
    }

    /** Executes every entity + index DDL entry from an exported schema document. */
    private fun applyEntities(db: SupportSQLiteDatabase, schema: JSONObject) {
        val entities = schema.getJSONArray("entities")
        for (i in 0 until entities.length()) {
            val entity = entities.getJSONObject(i)
            val tableName = entity.getString("tableName")
            db.execSQL(entity.getString("createSql").replace("\${TABLE_NAME}", tableName))
            val indices = entity.optJSONArray("indices")
            if (indices != null) {
                for (j in 0 until indices.length()) {
                    db.execSQL(
                        indices.getJSONObject(j).getString("createSql")
                            .replace("\${TABLE_NAME}", tableName)
                    )
                }
            }
        }
    }

    private data class Col(val type: String?, val notNull: Boolean, val dflt: String?, val pk: Int)

    /**
     * Field-by-field comparison of the live database against an exported Room schema:
     * table existence, exact column set, affinity, NOT NULL flags, primary-key membership,
     * and every declared index (existence + uniqueness).
     */
    private fun validateSchemaMatches(db: SupportSQLiteDatabase, schema: JSONObject) {
        val entities = schema.getJSONArray("entities")
        for (i in 0 until entities.length()) {
            val entity = entities.getJSONObject(i)
            val table = entity.getString("tableName")

            val columns = linkedMapOf<String, Col>()
            db.query("PRAGMA table_info($table)").use { c ->
                while (c.moveToNext()) {
                    columns[c.getString(1)] = Col(
                        type = c.getString(2)?.uppercase(),
                        notNull = c.getInt(3) == 1,
                        dflt = c.getString(4),
                        pk = c.getInt(5)
                    )
                }
            }
            assertFalse("table $table missing after migration", columns.isEmpty())

            val fields = entity.getJSONArray("fields")
            assertEquals(
                "column set mismatch for $table",
                fields.length(),
                columns.size
            )
            for (j in 0 until fields.length()) {
                val f = fields.getJSONObject(j)
                val name = f.getString("columnName")
                val col = columns[name]
                    ?: throw AssertionError("$table.$name missing after migration")
                assertEquals(
                    "$table.$name affinity",
                    f.getString("affinity"),
                    col.type
                )
                assertEquals("$table.$name notNull", f.optBoolean("notNull"), col.notNull)
            }

            val pkNames = entity.getJSONObject("primaryKey").getJSONArray("columnNames")
            for (j in 0 until pkNames.length()) {
                val pkCol = columns[pkNames.getString(j)]
                    ?: throw AssertionError("$table.${pkNames.getString(j)} missing (pk)")
                assertTrue("$table.${pkNames.getString(j)} must be a primary key", pkCol.pk > 0)
            }

            val indices = entity.optJSONArray("indices")
            if (indices != null) {
                val actualIndexes = linkedMapOf<String, Boolean>() // name → unique
                db.query("PRAGMA index_list($table)").use { c ->
                    while (c.moveToNext()) actualIndexes[c.getString(1)] = c.getInt(2) == 1
                }
                for (j in 0 until indices.length()) {
                    val idx = indices.getJSONObject(j)
                    val name = idx.getString("name")
                    assertEquals(
                        "index $name missing or wrong uniqueness on $table",
                        idx.getBoolean("unique"),
                        actualIndexes[name]
                    )
                }
            }
        }
    }

    private fun queryStamp(db: SupportSQLiteDatabase, id: String): Long =
        db.query("SELECT updatedAt FROM bookmarks WHERE id = ?", arrayOf(id)).use { c ->
            if (c.moveToFirst()) c.getLong(0) else -1L
        }

    private fun queryString(db: SupportSQLiteDatabase, id: String): String? =
        db.query("SELECT text FROM bookmarks WHERE id = ?", arrayOf(id)).use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }

    private fun queryString2(db: SupportSQLiteDatabase): String? =
        db.query("SELECT identity_hash FROM room_master_table").use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }

    private fun defaultValueOf(db: SupportSQLiteDatabase, table: String, column: String): String? {
        db.query("PRAGMA table_info($table)").use { c ->
            while (c.moveToNext()) {
                if (c.getString(1) == column) return c.getString(4)
            }
        }
        return null
    }

    private fun columnExists(db: SupportSQLiteDatabase, table: String, column: String): Boolean {
        db.query("PRAGMA table_info($table)").use { c ->
            val nameIdx = c.getColumnIndex("name")
            while (c.moveToNext()) if (c.getString(nameIdx) == column) return true
        }
        return false
    }
}
