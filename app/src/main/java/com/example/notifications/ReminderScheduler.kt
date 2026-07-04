package com.example.notifications

import android.content.Context
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Schedules Curio-owned "remind me to read later" notifications.
 *
 * Uses a delayed one-shot [ReminderWorker] rather than an exact [android.app.AlarmManager] alarm:
 * read-later nudges tolerate WorkManager's few-minutes of slack, and this avoids requesting the
 * privileged SCHEDULE_EXACT_ALARM permission. One unique job per bookmark (`reminder-<id>`), so
 * re-scheduling the same bookmark replaces the previous reminder instead of stacking.
 */
class ReminderScheduler(private val context: Context) {

    /**
     * Schedules a reminder for [bookmarkId] at [atEpochMillis]. A time already in the past fires
     * (essentially) immediately. Returns false when there's nothing to schedule.
     */
    fun schedule(bookmarkId: String, title: String?, url: String?, atEpochMillis: Long): Boolean {
        val delayMs = (atEpochMillis - System.currentTimeMillis()).coerceAtLeast(0L)
        val data = Data.Builder()
            .putString(ReminderWorker.KEY_BOOKMARK_ID, bookmarkId)
            .putString(ReminderWorker.KEY_TITLE, title)
            .putString(ReminderWorker.KEY_URL, url)
            .build()
        val request = OneTimeWorkRequestBuilder<ReminderWorker>()
            .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
            .setInputData(data)
            .addTag(TAG)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            uniqueName(bookmarkId), ExistingWorkPolicy.REPLACE, request
        )
        return true
    }

    /** Cancels a pending reminder for [bookmarkId] (e.g. when the bookmark is deleted). */
    fun cancel(bookmarkId: String) {
        WorkManager.getInstance(context).cancelUniqueWork(uniqueName(bookmarkId))
    }

    private fun uniqueName(bookmarkId: String) = "reminder-$bookmarkId"

    private companion object {
        const val TAG = "curio-reminder"
    }
}
