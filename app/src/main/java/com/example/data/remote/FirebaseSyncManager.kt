package com.example.data.remote

import android.content.Context
import android.util.Log
import com.example.domain.model.Bookmark
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreSettings
import com.google.firebase.firestore.SetOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import com.google.android.gms.tasks.Task

class FirebaseSyncManager(private val context: Context) {

    companion object {
        @Volatile private var persistenceConfigured = false
    }

    private var firestoreInstance: FirebaseFirestore? = null

    init {
        try {
            ensureFirebaseInitialized()
            val db = FirebaseFirestore.getInstance()
            if (!persistenceConfigured) {
                synchronized(FirebaseSyncManager::class.java) {
                    if (!persistenceConfigured) {
                        db.firestoreSettings = FirebaseFirestoreSettings.Builder()
                            .setPersistenceEnabled(true)
                            .build()
                        persistenceConfigured = true
                    }
                }
            }
            firestoreInstance = db
            Log.d("FirebaseSyncManager", "Firebase Firestore initialized successfully.")
        } catch (e: Exception) {
            Log.e("FirebaseSyncManager", "Failed to obtain Firestore instance: ${e.message}")
        }
    }

    /**
     * Ensures an authenticated Firebase session and returns its uid, or null if sign-in failed.
     * The returned uid is used as the Firestore path key (see [userBookmarks]) so the security
     * rule `request.auth.uid == {path uid}` is satisfied.
     */
    private suspend fun ensureAuthenticated(): String? {
        val auth = com.google.firebase.auth.FirebaseAuth.getInstance()
        auth.currentUser?.let { return it.uid }
        return try {
            auth.signInAnonymously().awaitTask().user?.uid
        } catch (e: Exception) {
            Log.w("FirebaseSyncManager", "Anonymous auth failed — Firestore ops skipped", e)
            null
        }
    }

    private fun ensureFirebaseInitialized() {
        if (FirebaseApp.getApps(context).isEmpty()) {
            val options = FirebaseOptions.Builder()
                .setApplicationId("1:101405038565:android:6fd52662a59a4b8f8b855f")
                .setProjectId("curio-cloud-sync")
                .setApiKey("mock_firebase_api_key_curio_studio_platform_sync")
                .build()
            FirebaseApp.initializeApp(context, options)
            Log.d("FirebaseSyncManager", "FirebaseApp initialized with manual fallback credentials.")
        }
    }

    /**
     * Per-user bookmark subcollection, keyed on the Firebase auth uid (NOT the X userId). Scoping
     * documents under `users/{authUid}/bookmarks/{id}` lets the Firestore security rules enforce
     * ownership by PATH (`request.auth.uid == {path uid}`) — see firestore.rules at the repo root.
     *
     * The X identity still lives in each document's `userId` field (see [buildMinimalMap]) so a
     * pulled bookmark can be re-associated with the local user. Because the path uses the anonymous
     * auth uid, sync is per-device: a reinstall mints a new uid and starts a fresh cloud subtree.
     * Cross-device sync would require a custom token whose uid == X userId (needs a backend).
     */
    private fun userBookmarks(db: FirebaseFirestore, authUid: String) =
        db.collection("users").document(authUid).collection("bookmarks")

    /**
     * Converts a Play Services Task into a suspendable coroutine result.
     */
    private suspend fun <T> Task<T>.awaitTask(): T = suspendCancellableCoroutine { continuation ->
        addOnCompleteListener { task ->
            if (task.isSuccessful) {
                continuation.resume(task.result)
            } else {
                continuation.resumeWithException(task.exception ?: Exception("Firebase execution failure"))
            }
        }
    }

    /**
     * Minimal sync payload — omits large PII/content fields (text, ocrText, deepSummary,
     * entities, sourceAbstract) that should remain on-device only.
     */
    private fun buildMinimalMap(userId: String, bookmark: Bookmark): HashMap<String, Any?> = hashMapOf(
        "id" to bookmark.id,
        "userId" to userId,
        "createdAt" to bookmark.createdAt,
        "updatedAt" to FieldValue.serverTimestamp(),
        "isFavorite" to bookmark.isFavorite,
        "isSavedForLater" to bookmark.isSavedForLater,
        "spaceId" to bookmark.spaceId,
        "sourceType" to bookmark.sourceType?.name,
        "sourceId" to bookmark.sourceId,
        "title" to bookmark.title,
        "url" to bookmark.url
    )

    /**
     * Push or update a single bookmark to Firebase Firestore.
     */
    suspend fun pushBookmark(userId: String, bookmark: Bookmark) {
        val authUid = ensureAuthenticated() ?: run {
            Log.w("FirebaseSyncManager", "Skipping Firestore op: not authenticated")
            return
        }
        val db = firestoreInstance ?: return
        try {
            userBookmarks(db, authUid)
                .document(bookmark.id)
                .set(buildMinimalMap(userId, bookmark), SetOptions.merge())
                .awaitTask()
            Log.d("FirebaseSyncManager", "Pushed bookmark successfully to Firestore: ${bookmark.id}")
        } catch (e: Exception) {
            Log.e("FirebaseSyncManager", "Error pushing bookmark ${bookmark.id} to Firestore: ${e.message}")
        }
    }

    /**
     * Bulk upload bookmark list to Firestore using WriteBatch (max 500 per batch).
     */
    suspend fun pushBookmarks(userId: String, bookmarks: List<Bookmark>) {
        val authUid = ensureAuthenticated() ?: run {
            Log.w("FirebaseSyncManager", "Skipping Firestore op: not authenticated")
            return
        }
        val db = firestoreInstance ?: return
        val userRef = userBookmarks(db, authUid)
        try {
            bookmarks.chunked(500).forEach { chunk ->
                val batch = db.batch()
                chunk.forEach { bookmark ->
                    val ref = userRef.document(bookmark.id)
                    batch.set(ref, buildMinimalMap(userId, bookmark), SetOptions.merge())
                }
                batch.commit().awaitTask()
            }
            Log.d("FirebaseSyncManager", "Bulk pushed ${bookmarks.size} bookmarks to Firestore.")
        } catch (e: Exception) {
            Log.e("FirebaseSyncManager", "Error bulk pushing bookmarks to Firestore: ${e.message}")
        }
    }

    /**
     * Pull all bookmarks associated with a specific user from Firebase Firestore.
     */
    suspend fun pullBookmarks(userId: String): List<Bookmark> {
        val authUid = ensureAuthenticated() ?: run {
            Log.w("FirebaseSyncManager", "Skipping Firestore op: not authenticated")
            return emptyList()
        }
        val db = firestoreInstance ?: return emptyList()
        return try {
            val querySnapshot = userBookmarks(db, authUid)
                .get()
                .awaitTask()

            querySnapshot.documents.mapNotNull { doc ->
                val id = doc.getString("id") ?: return@mapNotNull null
                val text = doc.getString("text") ?: ""
                val createdAt = doc.getLong("createdAt") ?: System.currentTimeMillis()
                // TODO: last-writer-wins conflict resolution — read cloudUpdatedAt here and
                //  compare against the local copy's createdAt as a proxy once BookmarkEntity
                //  gains an `updatedAt` column. For now, the repository merge in
                //  BookmarkRepositoryImpl prefers the local copy's enriched fields.
                val cloudUpdatedAtMs: Long? = doc.getTimestamp("updatedAt")?.toDate()?.time
                Log.v("FirebaseSyncManager", "doc=$id cloudUpdatedAt=$cloudUpdatedAtMs")
                val title = doc.getString("title")
                val url = doc.getString("url")
                val summary = doc.getString("summary")
                val tagCsv = doc.getString("tags") ?: ""
                val tags = tagCsv.split(",").map { it.trim() }.filter { it.isNotEmpty() }
                val category = doc.getString("category")
                val imageUrl = doc.getString("imageUrl")
                val ocrText = doc.getString("ocrText")
                val isOcrScheduled = doc.getBoolean("isOcrScheduled") ?: false
                val isAnalyzed = doc.getBoolean("isAnalyzed") ?: false

                val srcTypeName = doc.getString("sourceType")
                val srcType = srcTypeName?.let {
                    runCatching { com.example.domain.model.SourceType.valueOf(it) }.getOrNull()
                }
                Bookmark(
                    id = id, text = text, createdAt = createdAt, userId = userId,
                    title = title, url = url, summary = summary, tags = tags,
                    category = category, imageUrl = imageUrl, ocrText = ocrText,
                    isOcrScheduled = isOcrScheduled, isAnalyzed = isAnalyzed,
                    sourceType = srcType,
                    sourceId = doc.getString("sourceId"),
                    sourceTitle = doc.getString("sourceTitle"),
                    sourceAuthors = doc.getString("sourceAuthors"),
                    sourceAbstract = doc.getString("sourceAbstract"),
                    sourceExtra = doc.getString("sourceExtra"),
                    referenceCount = doc.getLong("referenceCount")?.toInt() ?: 1,
                    entities = doc.getString("entities"),
                    isDeepAnalyzed = doc.getBoolean("isDeepAnalyzed") ?: false,
                    deepSummary = doc.getString("deepSummary")
                )
            }
        } catch (e: Exception) {
            Log.e("FirebaseSyncManager", "Error pulling user $userId bookmarks from Firestore: ${e.message}")
            emptyList()
        }
    }

    /**
     * Delete a list of bookmarks from Firestore using WriteBatch (perf-13).
     *
     * Previously each document was deleted in its own round-trip inside a loop, costing O(N)
     * RPCs. WriteBatch coalesces up to 500 deletes per commit, reducing network round-trips to
     * O(N/500) and cutting Firestore billing units proportionally.
     */
    suspend fun deleteBookmarks(ids: List<String>) {
        if (ids.isEmpty()) return
        val authUid = ensureAuthenticated() ?: run {
            Log.w("FirebaseSyncManager", "Skipping Firestore op: not authenticated")
            return
        }
        val db = firestoreInstance ?: return
        try {
            ids.chunked(500).forEach { chunk ->
                val batch = db.batch()
                chunk.forEach { id ->
                    val ref = userBookmarks(db, authUid).document(id)
                    batch.delete(ref)
                }
                batch.commit().awaitTask()
                Log.d("FirebaseSyncManager", "Batch-deleted ${chunk.size} bookmarks from Firestore")
            }
        } catch (e: Exception) {
            Log.e("FirebaseSyncManager", "Failed to batch-delete bookmarks from Firestore: ${e.message}")
        }
    }
}
