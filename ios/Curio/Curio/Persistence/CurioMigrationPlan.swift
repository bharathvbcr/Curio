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
    // Only genuinely-distinct schema shapes may appear here: SwiftData throws
    // "Duplicate version checksums across stages detected" if two versioned schemas hash
    // identically. The historical `SchemaV6…V11` all reference the SAME current model classes
    // (their Room-era deltas were column/index additions already baked into `BookmarkModel` /
    // `SpaceModel`), so they share one checksum and cannot be staged. No iOS SwiftData store has
    // ever shipped, so that fictional history is unnecessary — the only real shape change on iOS
    // is adding the semantic cache. We therefore stage just V11 → V12.
    static var schemas: [any VersionedSchema.Type] {
        [
            SchemaV11.self,
            SchemaV12.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            // v11 → v12: + semantic_cache table (new on-device response cache model).
            .lightweight(fromVersion: SchemaV11.self, toVersion: SchemaV12.self)
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

/// Room v11: embedding-backfill + enrichment indices on `bookmarks`.
enum SchemaV11: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(11, 0, 0) }
    static var models: [any PersistentModel.Type] { [BookmarkModel.self, SpaceModel.self] }
}

/// Room v12 (current): adds the on-device semantic response cache (`SemanticCacheEntry`).
enum SchemaV12: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(12, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [BookmarkModel.self, SpaceModel.self, SemanticCacheEntry.self]
    }
}
