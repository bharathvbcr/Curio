package com.example.background

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.example.CurioApplication
import com.example.data.embedding.VectorSearch.toByteArray

/**
 * Charging-gated, on-device-ONLY embedding backfill.
 *
 * Runs under a `setRequiresCharging` constraint (see [EmbeddingIndexScheduler]) and embeds any
 * analyzed bookmarks that still lack a vector, using the local EmbeddingGemma provider. It never
 * touches the cloud embedder: per Curio's privacy model, third-party content processing only happens
 * in the foreground with the user present (the same rule [BookmarkSweeperService] documents). If the
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
            val pending = container.bookmarkRepository.getUnembeddedAnalyzed()
            if (pending.isEmpty()) {
                Log.d(TAG, "No unembedded bookmarks — index up to date")
                return Result.success()
            }

            var done = 0
            for (bookmark in pending.take(MAX_PER_RUN)) {
                if (isStopped) break
                val vector = onDevice.embedDocument(bookmark) ?: continue
                container.bookmarkRepository.updateEmbedding(bookmark.id, vector.toByteArray())
                done++
            }
            Log.d(TAG, "On-device indexed $done of ${pending.size} pending bookmarks")

            // More than one batch left → ask WorkManager to run us again (still charging-constrained).
            if (pending.size > MAX_PER_RUN) Result.retry() else Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Background indexing failed: ${e.message}", e)
            Result.retry()
        }
    }

    companion object {
        private const val TAG = "EmbeddingIndexWorker"
        /** Cap per run so a huge library is chunked across charging sessions rather than hogging one. */
        private const val MAX_PER_RUN = 200
    }
}
