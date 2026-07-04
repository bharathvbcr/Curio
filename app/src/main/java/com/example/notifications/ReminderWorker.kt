package com.example.notifications

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.example.CurioApplication

/**
 * Fires a single read-later reminder notification when its delayed WorkManager job comes due.
 *
 * Reminders are now owned by Curio in-house (they used to be delegated entirely to the ChronosFlow
 * app). [ReminderScheduler] enqueues one of these per bookmark with an initial delay; on run we hand
 * the payload to [CurioNotifier] to post on the reminder channel. Best-effort: a missing
 * CurioApplication (e.g. in tests) or notification permission just no-ops.
 */
class ReminderWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        val app = applicationContext as? CurioApplication ?: return Result.success()
        val bookmarkId = inputData.getString(KEY_BOOKMARK_ID) ?: return Result.success()
        val title = inputData.getString(KEY_TITLE)
        val url = inputData.getString(KEY_URL)
        app.appContainer.curioNotifier.showReminder(bookmarkId, title, url)
        return Result.success()
    }

    companion object {
        const val KEY_BOOKMARK_ID = "bookmark_id"
        const val KEY_TITLE = "title"
        const val KEY_URL = "url"
    }
}
