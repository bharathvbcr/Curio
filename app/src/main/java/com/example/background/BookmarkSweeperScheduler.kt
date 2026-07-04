package com.example.background

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Schedules the periodic [BookmarkSweeperWorker] (stale-link cleanup, every 6 hours).
 *
 * This replaced a foreground `Service` that ran an in-process 6-hour loop: the sweep is non-urgent
 * maintenance, so a deferrable, network-constrained WorkManager job is the correct fit — and it
 * mirrors [EmbeddingIndexScheduler] and the iOS `BGProcessingTask` design.
 */
object BookmarkSweeperScheduler {

    private const val PERIODIC_WORK = "bookmark-sweeper-periodic"

    /** Registers the periodic sweep. Safe to call on every app start (KEEP preserves the timer). */
    fun ensureScheduled(context: Context) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .setRequiresBatteryNotLow(true)
            .build()

        val request = PeriodicWorkRequestBuilder<BookmarkSweeperWorker>(6, TimeUnit.HOURS)
            .setConstraints(constraints)
            .setBackoffCriteria(BackoffPolicy.LINEAR, 30, TimeUnit.MINUTES)
            .build()

        // KEEP: if the periodic job already exists, leave it unchanged so the OS-managed interval
        // timer is not reset on every app launch (UPDATE would effectively never fire when launches
        // are frequent).
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            PERIODIC_WORK,
            ExistingPeriodicWorkPolicy.KEEP,
            request
        )
    }
}
