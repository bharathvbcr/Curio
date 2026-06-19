package com.example.data.local

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.example.BuildConfig

@Database(entities = [BookmarkEntity::class, SpaceEntity::class], version = 9, exportSchema = false)
abstract class AppDatabase : RoomDatabase() {
    abstract fun bookmarkDao(): BookmarkDao
    abstract fun spaceDao(): SpaceDao

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

        fun getDatabase(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "curio_database"
                )
                    .addMigrations(MIGRATION_6_7, MIGRATION_7_8, MIGRATION_8_9)
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
