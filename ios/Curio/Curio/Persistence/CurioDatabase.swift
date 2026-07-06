import Foundation
import SwiftData
import os

/// Owns the single `ModelContainer` for the app. Direct port of `AppDatabase`'s singleton wiring
/// (`data/local/AppDatabase.kt` `getDatabase`).
///
/// Mirrors the Android setup point-for-point:
/// - Store file named **`curio_database`** (same as the Room db name), placed in **Application
///   Support** (the iOS analogue of the app's internal database dir).
/// - The `Schema` carries both `@Model`s (`BookmarkModel`, `SpaceModel`).
/// - The `CurioMigrationPlan` (v6→v11 lightweight stages) is applied — the analogue of Room's
///   `.addMigrations(MIGRATION_6_7 … MIGRATION_10_11)`.
/// - **DEBUG destructive fallback** (Room `fallbackToDestructiveMigration()` gated on
///   `BuildConfig.DEBUG`): on an incompatible store the store file is deleted and rebuilt, matching
///   the Android debug-only "wipe and continue" behaviour for fast iteration.
/// - **RELEASE propagation**: a real failure is fatal (`fatalError`) rather than silently wiping a
///   user's library — exactly the Android comment's intent ("a release build must crash … rather than
///   silently delete a user's bookmarks").
///
/// The container is a process-wide singleton (`shared`), mirroring Room's `@Volatile INSTANCE`
/// double-checked-locking. `CurioDatabase.shared` is one of the two sanctioned globals (CONVENTIONS
/// §2).
final class CurioDatabase: Sendable {
    /// Process-wide singleton (Room `INSTANCE` analogue). Safe to share: the only stored property is
    /// the immutable, `Sendable` `ModelContainer`.
    static let shared = CurioDatabase()

    /// The Room database file name, preserved verbatim.
    static let storeName = "curio_database"

    let container: ModelContainer

    private static let logger = Logger(subsystem: "com.example.curio", category: "Persistence")

    private init() {
        let schema = Schema([BookmarkModel.self, SpaceModel.self, SemanticCacheEntry.self])
        let storeURL = Self.storeURL()
        let configuration = ModelConfiguration(url: storeURL)

        do {
            self.container = try ModelContainer(
                for: schema,
                migrationPlan: CurioMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            #if DEBUG
            // Debug-only destructive fallback: Room's `fallbackToDestructiveMigration()`. On an
            // incompatible / corrupt store, delete the store files and rebuild a fresh container.
            Self.logger.error(
                "Incompatible store — destructive rebuild (DEBUG only): \(String(describing: error))"
            )
            Self.deleteStore(at: storeURL)
            do {
                self.container = try ModelContainer(
                    for: schema,
                    migrationPlan: CurioMigrationPlan.self,
                    configurations: [configuration]
                )
            } catch {
                // If even a clean store cannot be created, there is nothing recoverable to do.
                fatalError("Failed to rebuild ModelContainer after destructive fallback: \(error)")
            }
            #else
            // Release: never silently wipe a user's library — propagate as a hard failure so a real
            // migration must be written (mirrors the Android release-build crash intent).
            fatalError("Failed to create ModelContainer (no destructive fallback in release): \(error)")
            #endif
        }
    }

    /// Resolves the on-disk store URL: `<Application Support>/curio_database`. Creates the Application
    /// Support directory if it does not yet exist (it is not guaranteed to exist on first launch).
    private static func storeURL() -> URL {
        let fm = FileManager.default
        let base: URL
        do {
            base = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            // Application Support is effectively always available; fall back to the documents dir
            // rather than crashing the whole app over a directory lookup.
            base = (try? fm.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )) ?? fm.temporaryDirectory
        }
        return base.appendingPathComponent(storeName)
    }

    /// Deletes the SwiftData store and its sidecar files (`-wal`, `-shm`) for the destructive
    /// DEBUG fallback. Best-effort — missing files are ignored.
    private static func deleteStore(at url: URL) {
        let fm = FileManager.default
        let sidecars = [url, url.appendingPathExtension("wal"), url.appendingPathExtension("shm")]
        for file in sidecars {
            try? fm.removeItem(at: file)
        }
        // SwiftData may also create a same-named directory for external storage / journals; remove it
        // too if present so the rebuild starts from a truly clean slate.
        let alt = url.deletingLastPathComponent().appendingPathComponent(storeName)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: alt.path, isDirectory: &isDir), isDir.boolValue {
            try? fm.removeItem(at: alt)
        }
    }
}
