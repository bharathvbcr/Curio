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

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!isRunning) {
            isRunning = true
            Log.d("BookmarkSweeper", "Sweeper Service started")
            startSweeperLoop()
        }
        return START_STICKY
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
                    
                    val allEntities = db.bookmarkDao().getAllBookmarksDirect()

                    for (entity in allEntities) {
                        val url = entity.url
                        
                        // 1. Detect and clean up stale, broken links (e.g. 404, 410)
                        if (!url.isNullOrBlank()) {
                            val isBroken = checkUrlIsBroken(okHttpClient, url)
                            if (isBroken) {
                                Log.w("BookmarkSweeper", "Broken bookmark link detected: $url. Cleaning up automatically.")
                                db.bookmarkDao().deleteBookmarks(listOf(entity.id))
                                
                                // Sync deletion downstream to Firebase
                                try {
                                    appContainer.firebaseSyncManager.deleteBookmarks(entity.userId, listOf(entity.id))
                                } catch (e: Exception) {
                                    Log.e("BookmarkSweeper", "Failed to sync link deletion to Firestore: ${e.message}")
                                }
                                continue
                            }
                        }

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

                // Sweeper interval: checks every 30 seconds for immediate responsiveness in demonstration
                delay(30_000)
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
                // If the URL has connection refused or host not found, it is also broken/stale
                val msg = e.message ?: ""
                msg.contains("Unable to resolve host") || msg.contains("Connection refused") || msg.contains("Route to host")
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
