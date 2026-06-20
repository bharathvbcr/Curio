package com.example.background

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
import com.example.CurioApplication
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request

class BookmarkSweeperService : Service() {

    private val serviceJob = SupervisorJob()
    private val serviceScope = CoroutineScope(Dispatchers.IO + serviceJob)
    private var isRunning = false

    companion object {
        // A 30s all-rows network sweep was a demo artifact that drained battery/data. Run it
        // sparingly; stale-link cleanup is not time-critical.
        private const val SWEEP_INTERVAL_MS = 6L * 60 * 60 * 1000   // 6 hours
        // Bound work per cycle and pace requests so a large library can't fire a burst of HEADs.
        private const val MAX_CHECKS_PER_CYCLE = 50
        private const val INTER_REQUEST_DELAY_MS = 250L
        private const val CHANNEL_ID = "curio_sweeper"
        private const val NOTIFICATION_ID = 1001
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                CHANNEL_ID, "Research Index Sync", android.app.NotificationManager.IMPORTANCE_LOW
            )
            (getSystemService(android.app.NotificationManager::class.java))?.createNotificationChannel(channel)
        }
        val notification = androidx.core.app.NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Curio: Syncing bookmarks")
            .setSmallIcon(android.R.drawable.ic_popup_sync)
            .setPriority(androidx.core.app.NotificationCompat.PRIORITY_LOW)
            .build()
        startForeground(NOTIFICATION_ID, notification)

        if (!isRunning) {
            isRunning = true
            Log.d("BookmarkSweeper", "Sweeper Service started")
            startSweeperLoop()
        }
        return START_NOT_STICKY
    }

    private fun startSweeperLoop() {
        serviceScope.launch {
            val app = application as CurioApplication
            val appContainer = app.appContainer
            val db = appContainer.database
            val okHttpClient = OkHttpClient.Builder()
                .connectTimeout(5, java.util.concurrent.TimeUnit.SECONDS)
                .readTimeout(5, java.util.concurrent.TimeUnit.SECONDS)
                .build()

            while (isRunning) {
                try {
                    Log.d("BookmarkSweeper", "Background bookmarks sweeping and link validation cycle started...")
                    
                    // Bound the work: only rows with a URL, capped per cycle, paced between requests.
                    val toCheck = db.bookmarkDao().getAllBookmarksDirect()
                        .filter { !it.url.isNullOrBlank() }
                        .take(MAX_CHECKS_PER_CYCLE)

                    for (entity in toCheck) {
                        val url = entity.url ?: continue
                        // Only delete on a DEFINITIVE dead link (404/410). A connection failure is
                        // usually transient (device offline / DNS hiccup) and must NOT delete the
                        // user's bookmark — doing so was silent data loss whenever the device was offline.
                        if (checkUrlIsBroken(okHttpClient, url)) {
                            Log.w("BookmarkSweeper", "Dead bookmark link (404/410): $url. Removing.")
                            db.bookmarkDao().deleteBookmarks(listOf(entity.id))
                            try {
                                appContainer.firebaseSyncManager.deleteBookmarks(entity.userId, listOf(entity.id))
                            } catch (e: Exception) {
                                Log.e("BookmarkSweeper", "Failed to sync link deletion to Firestore: ${e.message}")
                            }
                        }
                        delay(INTER_REQUEST_DELAY_MS)

                        // NOTE: AI enrichment (summarize / classify / tag) is intentionally NOT
                        // run here. It calls the xAI Grok cloud API, so per Curio's privacy model
                        // it must only run on a visible screen with the user present — never from a
                        // background service. Enrichment is triggered from the foreground in
                        // BookmarkViewModel. This service only performs offline maintenance
                        // (stale-link cleanup) that involves no third-party content processing.
                    }

                } catch (e: Exception) {
                    Log.e("BookmarkSweeper", "Error during background diagnostic cycle: ${e.message}", e)
                }

                delay(SWEEP_INTERVAL_MS)
            }
        }
    }

    private suspend fun checkUrlIsBroken(client: OkHttpClient, urlString: String): Boolean {
        return kotlinx.coroutines.withContext(Dispatchers.IO) {
            try {
                // Perform quick HEAD check
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

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        serviceJob.cancel()
        Log.d("BookmarkSweeper", "Sweeper Service destroyed.")
    }
}
