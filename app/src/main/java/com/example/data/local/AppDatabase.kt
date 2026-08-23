package com.example.data.local

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.example.BuildConfig

@Database(
    entities = [BookmarkEntity::class, SpaceEntity::class, SemanticCacheEntity::class],
    version = 13,
    exportSchema = true
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun bookmarkDao(): BookmarkDao
    abstract fun spaceDao(): SpaceDao
    abstract fun semanticCacheDao(): SemanticCacheDao

    companion object {
        @Volatile
        private var INSTANCE: AppDatabase? = null

        /**
         * v6 → v7: introduces Spaces. Adds the `spaceId` column to `bookmarks` and creates the
         * `spaces` table, preserving existing bookmarks rather than dropping the database.
         */
        private val MIGRATION_6_7 = object : Migration(6, 7) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE bookmarks ADD COLUMN spaceId TEXT")
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS spaces (
                        id TEXT NOT NULL PRIMARY KEY,
                        userId TEXT NOT NULL,
                        name TEXT NOT NULL,
                        colorValue INTEGER NOT NULL,
                        iconKey TEXT NOT NULL,
                        createdAt INTEGER NOT NULL
                    )
                    """.trimIndent()
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS index_spaces_userId ON spaces (userId)")
            }
        }

        /** v7 → v8: adds the per-bookmark personal `notes` annotation column. */
        private val MIGRATION_7_8 = object : Migration(7, 8) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE bookmarks ADD COLUMN notes TEXT")
            }
        }

        /**
         * v8 → v9: Smart Spaces + customization. Adds `description`, `isPinned`, `sortIndex` and
         * `rulesJson` to `spaces`. All carry safe defaults so existing Spaces become plain,
         * unpinned, rule-less collections without any data loss.
         */
        private val MIGRATION_8_9 = object : Migration(8, 9) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE spaces ADD COLUMN description TEXT NOT NULL DEFAULT ''")
                db.execSQL("ALTER TABLE spaces ADD COLUMN isPinned INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE spaces ADD COLUMN sortIndex INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE spaces ADD COLUMN rulesJson TEXT NOT NULL DEFAULT ''")
            }
        }

        /**
         * v9 → v10: adds indices for Space-membership and category filtering. Index names match
         * Room's generated convention (`index_<table>_<cols>`) so the post-migration schema hash
         * validates. No data change — pure index creation.
         */
        private val MIGRATION_9_10 = object : Migration(9, 10) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("CREATE INDEX IF NOT EXISTS index_bookmarks_spaceId ON bookmarks (spaceId)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_bookmarks_userId_category ON bookmarks (userId, category)")
            }
        }

        /**
         * v10 → v11: adds indices for embedding backfill and enrichment queries. Index names match
         * Room's generated convention (`index_<table>_<cols>`) so the post-migration schema hash
         * validates. No data change — pure index creation.
         */
        private val MIGRATION_10_11 = object : Migration(10, 11) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("CREATE INDEX IF NOT EXISTS index_bookmarks_isAnalyzed ON bookmarks (isAnalyzed)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_bookmarks_userId_isAnalyzed ON bookmarks (userId, isAnalyzed)")
            }
        }

        /**
         * v11 → v12: adds the on-device semantic response cache (`semantic_cache`). Column and
         * index definitions mirror Room's generated schema for [SemanticCacheEntity] exactly so
         * the post-migration schema hash validates. Pure additive change — no existing data touched.
         */
        private val MIGRATION_11_12 = object : Migration(11, 12) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS semantic_cache (
                        id TEXT NOT NULL PRIMARY KEY,
                        userId TEXT NOT NULL,
                        queryText TEXT NOT NULL,
                        queryHash TEXT NOT NULL,
                        embedding BLOB,
                        response TEXT NOT NULL,
                        modelTier TEXT NOT NULL,
                        createdAt INTEGER NOT NULL,
                        lastAccessAt INTEGER NOT NULL,
                        expiresAt INTEGER NOT NULL,
                        hitCount INTEGER NOT NULL
                    )
                    """.trimIndent()
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS index_semantic_cache_userId_queryHash ON semantic_cache (userId, queryHash)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_semantic_cache_userId ON semantic_cache (userId)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_semantic_cache_expiresAt ON semantic_cache (expiresAt)")
            }
        }

        /**
         * v12 → v13: adds the last-local-write stamp `updatedAt` to `bookmarks`, maintained by
         * two table triggers so every write path is stamped without touching any DAO query.
         * SQLite leaves recursive triggers OFF by default, so the trigger's own UPDATE does not
         * re-fire it (and Room ignores triggers during schema validation). INSERT-OR-REPLACE
         * upserts delete+insert, hence the companion AFTER INSERT trigger. Existing rows start
         * at 0 ("never locally written since this migration").
         */
        internal val MIGRATION_12_13 = object : Migration(12, 13) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE bookmarks ADD COLUMN updatedAt INTEGER NOT NULL DEFAULT 0")
                db.execSQL(
                    """
                    CREATE TRIGGER IF NOT EXISTS bookmarks_touch_updated_at_update
                    AFTER UPDATE ON bookmarks
                    BEGIN
                        UPDATE bookmarks SET updatedAt =
                            CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)
                        WHERE id = NEW.id;
                    END
                    """.trimIndent()
                )
                db.execSQL(
                    """
                    CREATE TRIGGER IF NOT EXISTS bookmarks_touch_updated_at_insert
                    AFTER INSERT ON bookmarks
                    BEGIN
                        UPDATE bookmarks SET updatedAt =
                            CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)
                        WHERE id = NEW.id;
                    END
                    """.trimIndent()
                )
            }
        }

        fun getDatabase(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "curio_database"
                )
                    .addMigrations(
                        MIGRATION_6_7, MIGRATION_7_8, MIGRATION_8_9, MIGRATION_9_10,
                        MIGRATION_10_11, MIGRATION_11_12, MIGRATION_12_13
                    )
                    .apply {
                        // Destructive fallback wipes the user's entire library on any schema
                        // mismatch. Keep it for fast iteration in debug builds only; a release
                        // build must crash (and be fixed with a real migration) rather than
                        // silently delete a user's bookmarks.
                        if (BuildConfig.DEBUG) fallbackToDestructiveMigration()
                    }
                    .build()
                INSTANCE = instance
                instance
            }
        }
    }
}
