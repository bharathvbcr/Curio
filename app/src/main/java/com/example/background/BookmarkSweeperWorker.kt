package com.example.background

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.example.CurioApplication
import com.example.notifications.CurioTask
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Background stale-link cleanup. Runs one sweep pass per invocation; periodicity is owned by
 * WorkManager (see [BookmarkSweeperScheduler]) rather than an in-process loop, which is why this
 * replaced the old foreground `Service` — the work is non-urgent maintenance, not something that
 * warrants a persistent foreground notification.
 *
 * Only DEFINITIVELY dead links (HTTP 404/410) are removed. A connection failure is usually transient
 * (device offline / DNS hiccup) and must NOT delete the user's bookmark — doing so was silent data
 * loss whenever the device was offline.
 *
 * PRIVACY: no AI/cloud enrichment runs here. Per Curio's privacy model, third-party content
 * processing only happens in the foreground with the user present.
 */
class BookmarkSweeperWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        val app = applicationContext as? CurioApplication ?: return Result.success()
        val appContainer = app.appContainer
        val db = appContainer.database
        val okHttpClient = OkHttpClient.Builder()
            .connectTimeout(5, java.util.concurrent.TimeUnit.SECONDS)
            .readTimeout(5, java.util.concurrent.TimeUnit.SECONDS)
            .build()

        return try {
            Log.d(TAG, "Background link-validation sweep started…")

            // Bound the work: only rows with a URL, capped per cycle, paced between requests.
            val toCheck = db.bookmarkDao().getAllBookmarksDirect()
                .filter { !it.url.isNullOrBlank() }
                .take(MAX_CHECKS_PER_CYCLE)

            // Surface the sweep in Curio's single live activity (no-op when nothing to check).
            val activity = appContainer.curioActivityController
            if (toCheck.isNotEmpty()) activity.taskStarted(CurioTask.SWEEP)
            try {
                for ((index, entity) in toCheck.withIndex()) {
                    if (isStopped) break
                    activity.taskProgress(CurioTask.SWEEP, index, toCheck.size)
                    val url = entity.url ?: continue
                    if (checkUrlIsBroken(okHttpClient, url)) {
                        Log.w(TAG, "Dead bookmark link (404/410): $url. Removing.")
                        db.bookmarkDao().deleteBookmarks(listOf(entity.id))
                        try {
                            appContainer.firebaseSyncManager.deleteBookmarks(listOf(entity.id))
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to sync link deletion to Firestore: ${e.message}")
                        }
                    }
                    delay(INTER_REQUEST_DELAY_MS)
                }
            } finally {
                if (toCheck.isNotEmpty()) activity.taskFinished(CurioTask.SWEEP)
            }
            Result.success()
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "Error during background sweep, will retry: ${e.message}", e)
            Result.retry()
        }
    }

    private suspend fun checkUrlIsBroken(client: OkHttpClient, urlString: String): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                val request = Request.Builder()
                    .url(urlString)
                    .head()
                    .build()
                client.newCall(request).execute().use { response ->
                    val code = response.code
                    code == 404 || code == 410
                }
            } catch (e: Exception) {
                // Connection refused / unresolved host / offline are TRANSIENT — treat the link as
                // intact (false) so a temporary network blip never deletes the user's bookmark.
                false
            }
        }
    }

    companion object {
        private const val TAG = "BookmarkSweeperWorker"
        // Bound work per cycle and pace requests so a large library can't fire a burst of HEADs.
        private const val MAX_CHECKS_PER_CYCLE = 50
        private const val INTER_REQUEST_DELAY_MS = 250L
    }
}
