import Foundation
import SwiftData

/// SwiftData migration plan mirroring Room's `AppDatabase` migrations v6→v11
/// (`data/local/AppDatabase.kt`, `MIGRATION_6_7` … `MIGRATION_10_11`).
///
/// Android's Room schema evolved through five additive migrations:
/// - **v6→v7** introduces Spaces: adds `bookmarks.spaceId` (nullable TEXT) and creates the `spaces`
///   table (`id/userId/name/colorValue/iconKey/createdAt`) + `index_spaces_userId`.
/// - **v7→v8** adds `bookmarks.notes` (nullable TEXT).
/// - **v8→v9** adds Smart-Space columns to `spaces`: `description` (`NOT NULL DEFAULT ''`),
///   `isPinned` (`DEFAULT 0`), `sortIndex` (`DEFAULT 0`), `rulesJson` (`NOT NULL DEFAULT ''`).
/// - **v9→v10** adds `index_bookmarks_spaceId` and `index_bookmarks_userId_category`.
/// - **v10→v11** adds `index_bookmarks_isAnalyzed` and `index_bookmarks_userId_isAnalyzed`.
///
/// Every Room migration is **additive** (new nullable columns, new columns with literal defaults, or
/// pure index creation) — so each SwiftData stage is `.lightweight`. The columns and indices all
/// already exist on the final `BookmarkModel` / `SpaceModel` definitions; the versioned schemas below
/// describe the historical shapes so SwiftData can derive the additive deltas.
///
/// Indices are declared on the models (`#Index`), not via raw CREATE INDEX — SwiftData recreates them
/// from the model definition (CONVENTIONS §6). The empty-string sentinels and nil defaults are
/// preserved by the model definitions themselves (`description=""`, `isPinned=false`, `sortIndex=0`,
/// `rulesJson=""`, `spaceId=nil`, `notes=nil`).
///
/// Store file `curio_database` lives in Application Support; DEBUG destructive-rebuild / RELEASE
/// propagate is handled by `CurioDatabase` (CONVENTIONS §6).
enum CurioMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            SchemaV6.self,
            SchemaV7.self,
            SchemaV8.self,
            SchemaV9.self,
            SchemaV10.self,
            SchemaV11.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            // v6 → v7: + bookmarks.spaceId, + spaces table (+ index_spaces_userId).
            .lightweight(fromVersion: SchemaV6.self, toVersion: SchemaV7.self),
            // v7 → v8: + bookmarks.notes.
            .lightweight(fromVersion: SchemaV7.self, toVersion: SchemaV8.self),
            // v8 → v9: + spaces.{description, isPinned, sortIndex, rulesJson} with defaults.
            .lightweight(fromVersion: SchemaV8.self, toVersion: SchemaV9.self),
            // v9 → v10: + index_bookmarks_spaceId, + index_bookmarks_userId_category.
            .lightweight(fromVersion: SchemaV9.self, toVersion: SchemaV10.self),
            // v10 → v11: + index_bookmarks_isAnalyzed, + index_bookmarks_userId_isAnalyzed.
            .lightweight(fromVersion: SchemaV10.self, toVersion: SchemaV11.self)
        ]
    }
}

// MARK: - Versioned schemas
//
// Each schema's `versionIdentifier` mirrors the Room database version. The two model types are the
// SAME final classes across versions; the schema list is what tells SwiftData which entities the
// store contains at each historical version. Because every delta is additive-with-defaults, the
// lightweight stages need no custom willMigrate/didMigrate closures — the new properties (already on
// the models) appear with their default values, and `#Index` declarations recreate the indices that
// the Room v9→v10 / v10→v11 migrations added.

/// Room v6 baseline (pre-Spaces). The earliest version this app migrates from.
enum SchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }
    static var models: [any PersistentModel.Type] { [BookmarkModel.self, SpaceModel.self] }
}

/// Room v7: Spaces introduced (`bookmarks.spaceId` + `spaces` table).
enum SchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }
    static var models: [any PersistentModel.Type] { [BookmarkModel.self, SpaceModel.self] }
}

/// Room v8: `bookmarks.notes`.
enum SchemaV8: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(8, 0, 0) }
    static var models: [any PersistentModel.Type] { [BookmarkModel.self, SpaceModel.self] }
}

/// Room v9: Smart-Space columns on `spaces`.
enum SchemaV9: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(9, 0, 0) }
    static var models: [any PersistentModel.Type] { [BookmarkModel.self, SpaceModel.self] }
}

/// Room v10: Space-membership + category indices on `bookmarks`.
enum SchemaV10: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(10, 0, 0) }
    static var models: [any PersistentModel.Type] { [BookmarkModel.self, SpaceModel.self] }
}

/// Room v11 (current): embedding-backfill + enrichment indices on `bookmarks`.
enum SchemaV11: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(11, 0, 0) }
    static var models: [any PersistentModel.Type] { [BookmarkModel.self, SpaceModel.self] }
}
