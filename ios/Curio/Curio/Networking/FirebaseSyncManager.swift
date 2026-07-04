import Foundation
import os
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth

/// Firestore-backed cloud mirror for bookmarks. Ports `class FirebaseSyncManager` in
/// `data/remote/FirebaseSyncManager.kt`.
///
/// Behaviors preserved (CONVENTIONS §7 "Firestore asymmetry", Networking cross-cutting):
/// - Anonymous-auth gate: every op first calls `ensureAuthenticated()`, which returns the Firebase
///   auth uid; on failure it logs + no-ops (push/delete) or returns `[]` (pull).
/// - Path scoping: documents live under `users/{authUid}/bookmarks/{id}` — keyed on the Firebase
///   auth uid (NOT the X userId) so the security rule `request.auth.uid == {path uid}` is
///   satisfied. The X identity still lives in each document's `userId` field (`buildMinimalMap`)
///   so a pulled bookmark can be re-associated with the local user. Because the path uses the
///   anonymous auth uid, sync is per-device: a reinstall mints a new uid and starts a fresh cloud
///   subtree. Cross-device sync would require a custom token whose uid == X userId (needs a
///   backend).
/// - Minimal push map (id/userId/createdAt/updatedAt/flags/spaceId/sourceType/sourceId/title/url)
///   vs richer pull (full mapping with safe defaults) — the asymmetry keeps PII/content on-device.
/// - `serverTimestamp()` on push; CSV `tags` split + `SourceType(rawValue:)`-guarded on pull.
/// - 500-doc chunking for batch push/delete.
/// - Resilient: every op is wrapped in do/catch that logs and swallows (never throws). The 15s
///   bound is applied by the Repository's `withTimeout` wrapper around these calls.
///
/// `actor` per CONVENTIONS §5 (owns the lazily-resolved `Firestore` handle).
actor FirebaseSyncManager {

    private var firestoreInstance: Firestore?
    private static let logger = Logger(subsystem: "com.curio.app", category: "FirebaseSyncManager")

    /// On iOS, `FirebaseApp.configure()` is called once at app launch (`CurioApp.init`). This
    /// initializer resolves the `Firestore` handle and applies offline persistence once. The Android
    /// manual `FirebaseOptions` fallback is replaced by `GoogleService-Info.plist` (DESIGN tech map).
    init() {
        // FirebaseApp must already be configured by the app entry point. If not, configure it so
        // the manager is still usable in isolation (tests / previews).
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        // Offline persistence is ON by default for Firestore on Apple platforms (DEPENDENCIES doc),
        // so the Android `setPersistenceEnabled(true)` is satisfied implicitly — no settings mutation
        // is needed (and any mutation must precede the first `Firestore.firestore()` call).
        self.firestoreInstance = Firestore.firestore()
        Self.logger.debug("Firebase Firestore initialized successfully.")
    }

    // MARK: - Auth gate

    /// Port of `ensureAuthenticated`. Ensures an authenticated Firebase session and returns its
    /// uid, or `nil` if sign-in failed. The returned uid is used as the Firestore path key (see
    /// `userBookmarks`) so the security rule `request.auth.uid == {path uid}` is satisfied.
    private func ensureAuthenticated() async -> String? {
        let auth = Auth.auth()
        if let current = auth.currentUser { return current.uid }
        do {
            return try await auth.signInAnonymously().user.uid
        } catch {
            Self.logger.warning("Anonymous auth failed — Firestore ops skipped")
            return nil
        }
    }

    /// Per-user bookmark subcollection reference: `users/{authUid}/bookmarks`, keyed on the
    /// Firebase auth uid (NOT the X userId — see the type doc). Port of `userBookmarks`.
    private func userBookmarks(_ db: Firestore, _ authUid: String) -> CollectionReference {
        db.collection("users").document(authUid).collection("bookmarks")
    }

    // MARK: - Minimal push map

    /// Port of `buildMinimalMap`. Omits large PII/content fields (text, ocrText, deepSummary,
    /// entities, sourceAbstract) that must remain on-device only. `nil` Swift values become explicit
    /// `NSNull` so the dictionary key is present (matching the Kotlin `hashMapOf` that stores `null`
    /// values), then `setData(merge:)` records the field.
    private func buildMinimalMap(userId: String, bookmark: Bookmark) -> [String: Any] {
        [
            "id": bookmark.id,
            "userId": userId,
            "createdAt": bookmark.createdAt,
            "updatedAt": FieldValue.serverTimestamp(),
            "isFavorite": bookmark.isFavorite,
            "isSavedForLater": bookmark.isSavedForLater,
            "spaceId": bookmark.spaceId as Any? ?? NSNull(),
            "sourceType": bookmark.sourceType?.rawValue as Any? ?? NSNull(),
            "sourceId": bookmark.sourceId as Any? ?? NSNull(),
            "title": bookmark.title as Any? ?? NSNull(),
            "url": bookmark.url as Any? ?? NSNull()
        ]
    }

    // MARK: - Push

    /// Port of `pushBookmark`. Auth-gated; `setData(merge:)`; resilient.
    func pushBookmark(userId: String, bookmark: Bookmark) async {
        guard let authUid = await ensureAuthenticated() else {
            Self.logger.warning("Skipping Firestore op: not authenticated")
            return
        }
        guard let db = firestoreInstance else { return }
        do {
            try await userBookmarks(db, authUid)
                .document(bookmark.id)
                .setData(buildMinimalMap(userId: userId, bookmark: bookmark), merge: true)
            Self.logger.debug("Pushed bookmark successfully to Firestore: \(bookmark.id)")
        } catch {
            Self.logger.error("Error pushing bookmark \(bookmark.id) to Firestore")
        }
    }

    /// Port of `pushBookmarks`. Chunks of 500 committed via `WriteBatch`; resilient.
    func pushBookmarks(userId: String, bookmarks: [Bookmark]) async {
        guard let authUid = await ensureAuthenticated() else {
            Self.logger.warning("Skipping Firestore op: not authenticated")
            return
        }
        guard let db = firestoreInstance else { return }
        let userRef = userBookmarks(db, authUid)
        do {
            for chunk in bookmarks.chunked(into: 500) {
                let batch = db.batch()
                for bookmark in chunk {
                    let ref = userRef.document(bookmark.id)
                    batch.setData(buildMinimalMap(userId: userId, bookmark: bookmark), forDocument: ref, merge: true)
                }
                try await batch.commit()
            }
            Self.logger.debug("Bulk pushed \(bookmarks.count) bookmarks to Firestore.")
        } catch {
            Self.logger.error("Error bulk pushing bookmarks to Firestore")
        }
    }

    // MARK: - Pull

    /// Port of `pullBookmarks`. Full mapping with safe defaults; CSV `tags` split; `SourceType`
    /// guarded; resilient → `[]`.
    func pullBookmarks(userId: String) async -> [Bookmark] {
        guard let authUid = await ensureAuthenticated() else {
            Self.logger.warning("Skipping Firestore op: not authenticated")
            return []
        }
        guard let db = firestoreInstance else { return [] }
        do {
            let snapshot = try await userBookmarks(db, authUid).getDocuments()
            return snapshot.documents.compactMap { doc -> Bookmark? in
                let data = doc.data()
                guard let id = data["id"] as? String else { return nil }
                let text = (data["text"] as? String) ?? ""
                let createdAt = Self.long(data["createdAt"]) ?? Int64(Date().timeIntervalSince1970 * 1000)

                let tagCsv = (data["tags"] as? String) ?? ""
                let tags = tagCsv
                    .split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                let isOcrScheduled = (data["isOcrScheduled"] as? Bool) ?? false
                let isAnalyzed = (data["isAnalyzed"] as? Bool) ?? false

                let srcType = (data["sourceType"] as? String).flatMap { SourceType(rawValue: $0) }

                return Bookmark(
                    id: id,
                    text: text,
                    createdAt: createdAt,
                    userId: userId,
                    title: data["title"] as? String,
                    url: data["url"] as? String,
                    summary: data["summary"] as? String,
                    tags: tags,
                    category: data["category"] as? String,
                    imageUrl: data["imageUrl"] as? String,
                    ocrText: data["ocrText"] as? String,
                    isOcrScheduled: isOcrScheduled,
                    isAnalyzed: isAnalyzed,
                    sourceType: srcType,
                    sourceId: data["sourceId"] as? String,
                    sourceTitle: data["sourceTitle"] as? String,
                    sourceAuthors: data["sourceAuthors"] as? String,
                    sourceAbstract: data["sourceAbstract"] as? String,
                    sourceExtra: data["sourceExtra"] as? String,
                    referenceCount: Self.long(data["referenceCount"]).map { Int($0) } ?? 1,
                    entities: data["entities"] as? String,
                    isDeepAnalyzed: (data["isDeepAnalyzed"] as? Bool) ?? false,
                    deepSummary: data["deepSummary"] as? String
                )
            }
        } catch {
            Self.logger.error("Error pulling user \(userId) bookmarks from Firestore")
            return []
        }
    }

    // MARK: - Delete

    /// Port of `deleteBookmarks`. Early-out on empty; auth-gated; 500-chunk `WriteBatch` deletes;
    /// resilient. The `userId` param was dropped (paths are keyed on the auth uid).
    func deleteBookmarks(ids: [String]) async {
        if ids.isEmpty { return }
        guard let authUid = await ensureAuthenticated() else {
            Self.logger.warning("Skipping Firestore op: not authenticated")
            return
        }
        guard let db = firestoreInstance else { return }
        do {
            for chunk in ids.chunked(into: 500) {
                let batch = db.batch()
                for id in chunk {
                    let ref = userBookmarks(db, authUid).document(id)
                    batch.deleteDocument(ref)
                }
                try await batch.commit()
                Self.logger.debug("Batch-deleted \(chunk.count) bookmarks from Firestore")
            }
        } catch {
            Self.logger.error("Failed to batch-delete bookmarks from Firestore")
        }
    }

    // MARK: - Helpers

    /// Mirrors Firestore `getLong(...)` tolerance — coerces `NSNumber`/`Int64`/`Int`/`Double` to
    /// `Int64`, else nil.
    private static func long(_ value: Any?) -> Int64? {
        switch value {
        case let number as NSNumber: return number.int64Value
        case let value as Int64: return value
        case let value as Int: return Int64(value)
        case let value as Double: return Int64(value)
        default: return nil
        }
    }
}

// MARK: - Chunking

private extension Array {
    /// Splits into sub-arrays of at most `size` (mirrors Kotlin `chunked(500)`).
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
