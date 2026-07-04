package com.example.background

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.example.CurioApplication
import com.example.data.embedding.VectorSearch.toByteArray
import com.example.notifications.CurioTask

/**
 * Charging-gated, on-device-ONLY embedding backfill.
 *
 * Runs under a `setRequiresCharging` constraint (see [EmbeddingIndexScheduler]) and embeds any
 * analyzed bookmarks that still lack a vector, using the local EmbeddingGemma provider. It never
 * touches the cloud embedder: per Curio's privacy model, third-party content processing only happens
 * in the foreground with the user present (the same rule [BookmarkSweeperWorker] documents). If the
 * model hasn't been downloaded, this is a no-op.
 *
 * Foreground on-demand embedding is unchanged — this worker only *backfills* in bulk while charging.
 */
class EmbeddingIndexWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        val app = applicationContext as? CurioApplication ?: return Result.success()
        val container = app.appContainer
        val onDevice = container.onDeviceEmbeddingProvider

        // On-device only. If EmbeddingGemma isn't present, there's nothing to do in the background.
        if (!onDevice.isOnDevice()) {
            Log.d(TAG, "EmbeddingGemma not downloaded — skipping background indexing")
            return Result.success()
        }

        return try {
            val userId = container.tokenStore.getUserId() ?: run {
                Log.d(TAG, "No signed-in user — skipping background indexing")
                return Result.success()
            }
            val pending = container.bookmarkRepository.getUnembeddedAnalyzed(userId)
            if (pending.isEmpty()) {
                Log.d(TAG, "No unembedded bookmarks — index up to date")
                return Result.success()
            }

            // Accumulate all (id, bytes) pairs, then flush in a single @Transaction (perf-14).
            // This amortises SQLite WAL-flush overhead from O(N) to O(1).
            val batch = pending.take(MAX_PER_RUN)
            val activity = container.curioActivityController
            activity.taskStarted(CurioTask.INDEX)
            val updates = mutableListOf<Pair<String, ByteArray>>()
            try {
                for ((index, bookmark) in batch.withIndex()) {
                    if (isStopped) break
                    activity.taskProgress(CurioTask.INDEX, index, batch.size)
                    val vector = onDevice.embedDocument(bookmark) ?: continue
                    updates += bookmark.id to vector.toByteArray()
                }
            } finally {
                activity.taskFinished(CurioTask.INDEX)
            }
            if (updates.isNotEmpty()) {
                container.bookmarkRepository.updateEmbeddings(updates)
                // New vectors are available → auto-organise in the background so cards are already
                // sorted into Spaces (and clusters discovered) by the time the user opens the app.
                runCatching { container.bookmarkRepository.organizeByEmbedding(userId) }
                    .onFailure { Log.w(TAG, "Background auto-organise failed: ${it.message}") }
            }
            val done = updates.size
            Log.d(TAG, "On-device indexed $done of ${pending.size} pending bookmarks")

            // More than one batch left → ask WorkManager to run us again (still charging-constrained).
            if (pending.size > MAX_PER_RUN) Result.retry() else Result.success()
        } catch (e: java.io.IOException) {
            // Network or I/O — retry
            Log.e(TAG, "I/O error during background indexing, will retry: ${e.message}", e)
            Result.retry()
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            // Model load failure or unrecoverable — don't retry infinitely
            android.util.Log.e("EmbeddingIndexWorker", "Unrecoverable error, giving up", e)
            Result.failure()
        }
    }

    companion object {
        private const val TAG = "EmbeddingIndexWorker"
        /** Cap per run so a huge library is chunked across charging sessions rather than hogging one. */
        private const val MAX_PER_RUN = 200
    }
}
