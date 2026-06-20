package com.example.background

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Schedules the on-device [EmbeddingIndexWorker].
 *
 * The periodic job carries a `requiresCharging` (+ battery-not-low) constraint, so the OS only runs
 * it while plugged in — matching the user's preference to index on-device when charging. The
 * preference is persisted so the choice survives restarts and gates whether the periodic job exists.
 */
object EmbeddingIndexScheduler {

    private const val PREFS = "curio_embedding_prefs"
    private const val KEY_ENABLED = "index_while_charging"

    private const val PERIODIC_WORK = "embedding-index-periodic"
    private const val ONESHOT_WORK = "embedding-index-now"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Whether charging-time on-device indexing is enabled. Defaults to on. */
    fun isEnabled(context: Context): Boolean = prefs(context).getBoolean(KEY_ENABLED, true)

    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
        if (enabled) schedulePeriodic(context) else cancelPeriodic(context)
    }

    /** Registers the periodic charging-gated job if enabled. Safe to call on every app start. */
    fun ensureScheduled(context: Context) {
        if (isEnabled(context)) schedulePeriodic(context)
    }

    private fun schedulePeriodic(context: Context) {
        val constraints = Constraints.Builder()
            .setRequiresCharging(true)
            .setRequiresBatteryNotLow(true)
            .build()

        val request = PeriodicWorkRequestBuilder<EmbeddingIndexWorker>(6, TimeUnit.HOURS)
            .setConstraints(constraints)
            .setBackoffCriteria(BackoffPolicy.LINEAR, 30, TimeUnit.MINUTES)
            .build()

        // KEEP: if the periodic job already exists, leave it unchanged so the OS-managed
        // interval timer is not reset on every app launch (perf-12). UPDATE would reschedule
        // on each launch, effectively never firing when launches are frequent.
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            PERIODIC_WORK,
            ExistingPeriodicWorkPolicy.KEEP,
            request
        )
    }

    private fun cancelPeriodic(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(PERIODIC_WORK)
    }

    /**
     * Fires a one-off backfill immediately (no charging constraint) — for an explicit user action
     * like "build the index now" right after downloading the model. Still on-device only.
     */
    fun runNow(context: Context) {
        val request = OneTimeWorkRequestBuilder<EmbeddingIndexWorker>().build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            ONESHOT_WORK,
            ExistingWorkPolicy.REPLACE,
            request
        )
    }
}
