package com.example.data.remote

import android.content.Context
import android.util.Log
import com.example.domain.model.Bookmark
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import com.google.android.gms.tasks.Task

class FirebaseSyncManager(private val context: Context) {

    private var firestoreInstance: FirebaseFirestore? = null

    init {
        try {
            ensureFirebaseInitialized()
            firestoreInstance = FirebaseFirestore.getInstance()
            Log.d("FirebaseSyncManager", "Firebase Firestore initialized successfully.")
        } catch (e: Exception) {
            Log.e("FirebaseSyncManager", "Failed to obtain Firestore instance: ${e.message}")
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
     * Push or update a single bookmark to Firebase Firestore.
     */
    suspend fun pushBookmark(userId: String, bookmark: Bookmark) {
        val db = firestoreInstance ?: return
        try {
            val documentId = "${userId}_${bookmark.id}"
            val data = hashMapOf(
                "id" to bookmark.id,
                "text" to bookmark.text,
                "createdAt" to bookmark.createdAt,
                "userId" to userId,
                "title" to bookmark.title,
                "url" to bookmark.url,
                "summary" to bookmark.summary,
                "tags" to bookmark.tags.joinToString(","),
                "category" to bookmark.category,
                "imageUrl" to bookmark.imageUrl,
                "ocrText" to bookmark.ocrText,
                "isOcrScheduled" to bookmark.isOcrScheduled,
                "isAnalyzed" to bookmark.isAnalyzed,
                "sourceType" to bookmark.sourceType?.name,
                "sourceId" to bookmark.sourceId,
                "sourceTitle" to bookmark.sourceTitle,
                "sourceAuthors" to bookmark.sourceAuthors,
                "sourceAbstract" to bookmark.sourceAbstract,
                "sourceExtra" to bookmark.sourceExtra,
                "referenceCount" to bookmark.referenceCount,
                "entities" to bookmark.entities,
                "isDeepAnalyzed" to bookmark.isDeepAnalyzed,
                "deepSummary" to bookmark.deepSummary
            )
            db.collection("bookmarks")
                .document(documentId)
                .set(data, SetOptions.merge())
                .awaitTask()
            Log.d("FirebaseSyncManager", "Pushed bookmark successfully to Firestore: ${bookmark.id}")
        } catch (e: Exception) {
            Log.e("FirebaseSyncManager", "Error pushing bookmark ${bookmark.id} to Firestore: ${e.message}")
        }
    }

    /**
     * Bulk upload bookmark list to Firestore.
     */
    suspend fun pushBookmarks(userId: String, bookmarks: List<Bookmark>) {
        bookmarks.forEach { pushBookmark(userId, it) }
    }

    /**
     * Pull all bookmarks associated with a specific user from Firebase Firestore.
     */
    suspend fun pullBookmarks(userId: String): List<Bookmark> {
        val db = firestoreInstance ?: return emptyList()
        return try {
            val querySnapshot = db.collection("bookmarks")
                .whereEqualTo("userId", userId)
                .get()
                .awaitTask()

            querySnapshot.documents.mapNotNull { doc ->
                val id = doc.getString("id") ?: return@mapNotNull null
                val text = doc.getString("text") ?: return@mapNotNull null
                val createdAt = doc.getLong("createdAt") ?: System.currentTimeMillis()
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
     * Delete a list of bookmarks from Firestore.
     */
    suspend fun deleteBookmarks(userId: String, ids: List<String>) {
        val db = firestoreInstance ?: return
        ids.forEach { id ->
            try {
                val documentId = "${userId}_$id"
                db.collection("bookmarks").document(documentId).delete().awaitTask()
                Log.d("FirebaseSyncManager", "Deleted bookmark from Firestore: $id")
            } catch (e: Exception) {
                Log.e("FirebaseSyncManager", "Failed to delete firestore bookmark $id: ${e.message}")
            }
        }
    }
}
