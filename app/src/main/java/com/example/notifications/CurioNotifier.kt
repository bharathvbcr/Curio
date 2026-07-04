package com.example.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.example.MainActivity
import com.example.R

/**
 * Renders the unified [CurioActivityState] as EXACTLY ONE ongoing notification and fires read-later
 * reminders on a separate channel. Nothing else in the app is allowed to post a notification, which
 * is how "many notifications" becomes "one live activity".
 *
 * On Android 16+ (API 36) the ongoing notification opts into the "Live Updates" treatment via
 * [NotificationCompat.Builder.setRequestPromotedOngoing] + [NotificationCompat.ProgressStyle] — the
 * status-bar chip / always-on-display surface. On older devices the same compat builder degrades to
 * a normal ongoing progress notification automatically, so there's a single code path.
 *
 * All posting is guarded by [NotificationManagerCompat.areNotificationsEnabled]; when the user has
 * denied POST_NOTIFICATIONS every call is a silent no-op (the app carries on standalone).
 */
class CurioNotifier(private val context: Context) {

    private val manager = NotificationManagerCompat.from(context)

    init {
        ensureChannels()
    }

    /** Draws the single live activity for [state]. Ongoing while work runs; dismissible for alerts. */
    fun render(state: CurioActivityState) {
        if (!manager.areNotificationsEnabled()) return

        val builder = NotificationCompat.Builder(context, CHANNEL_ACTIVITY)
            .setSmallIcon(R.drawable.ic_stat_curio)
            .setColor(ContextCompat.getColor(context, R.color.curio_accent))
            .setContentTitle(state.headline)
            .setContentIntent(openAppIntent())
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
        state.detail?.let { builder.setContentText(it).setStyle(NotificationCompat.BigTextStyle().bigText(it)) }

        if (state.isOngoing) {
            applyOngoingProgress(builder, state)
        } else {
            // Digest-ready / error: a normal, dismissible notification the user can act on or swipe.
            builder.setOngoing(false)
                .setAutoCancel(true)
                .setCategory(
                    if (state.attention is Attention.Error) NotificationCompat.CATEGORY_ERROR
                    else NotificationCompat.CATEGORY_STATUS
                )
        }

        manager.notify(ACTIVITY_NOTIFICATION_ID, builder.build())
    }

    /** Removes the live activity notification (called when the reduced state goes empty). */
    fun cancelActivity() = manager.cancel(ACTIVITY_NOTIFICATION_ID)

    /**
     * Fires a read-later reminder for a bookmark on the high-importance reminder channel. Tapping a
     * web reminder opens the link directly; anything else opens Curio.
     */
    fun showReminder(bookmarkId: String, title: String?, url: String?) {
        if (!manager.areNotificationsEnabled()) return
        val safeTitle = title?.takeIf { it.isNotBlank() } ?: "Something you saved to read"
        val builder = NotificationCompat.Builder(context, CHANNEL_REMINDERS)
            .setSmallIcon(R.drawable.ic_stat_curio)
            .setColor(ContextCompat.getColor(context, R.color.curio_accent))
            .setContentTitle("Time to read 📖")
            .setContentText(safeTitle)
            .setStyle(NotificationCompat.BigTextStyle().bigText(safeTitle))
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(reminderIntent(bookmarkId, url))

        manager.notify(reminderNotificationId(bookmarkId), builder.build())
    }

    // ── internals ────────────────────────────────────────────────────────────

    private fun applyOngoingProgress(builder: NotificationCompat.Builder, state: CurioActivityState) {
        val accent = ContextCompat.getColor(context, R.color.curio_accent)
        val fraction = state.progress
        val progressStyle = NotificationCompat.ProgressStyle()
            .setProgressSegments(listOf(NotificationCompat.ProgressStyle.Segment(PROGRESS_MAX).setColor(accent)))
            .setProgressIndeterminate(fraction == null)
        if (fraction != null) progressStyle.setProgress((fraction * PROGRESS_MAX).toInt().coerceIn(0, PROGRESS_MAX))

        builder.setOngoing(true)
            .setAutoCancel(false)
            .setStyle(progressStyle)
            .setShortCriticalText(shortStatus(state))
            .setRequestPromotedOngoing(true)
    }

    /** The tiny label the status-bar chip shows: a percentage when known, else the leading task. */
    private fun shortStatus(state: CurioActivityState): String {
        state.progress?.let { return "${(it * 100).toInt()}%" }
        return state.activeTasks.firstOrNull()?.let { shortLabel(it) } ?: "Curio"
    }

    private fun shortLabel(task: CurioTask): String = when (task) {
        CurioTask.SYNC -> "Sync"
        CurioTask.SWEEP -> "Tidy"
        CurioTask.INDEX -> "Index"
        CurioTask.DIGEST -> "Digest"
    }

    private fun openAppIntent(): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    private fun reminderIntent(bookmarkId: String, url: String?): PendingIntent {
        val intent = if (url != null && (url.startsWith("http://") || url.startsWith("https://"))) {
            Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        } else {
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        return PendingIntent.getActivity(
            context, reminderNotificationId(bookmarkId), intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    private fun reminderNotificationId(bookmarkId: String): Int =
        REMINDER_ID_BASE + (bookmarkId.hashCode() and 0xFFFF)

    private fun ensureChannels() {
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ACTIVITY, "Background activity", NotificationManager.IMPORTANCE_LOW).apply {
                description = "One live notification for syncing, tidying, indexing and digests."
                setShowBadge(false)
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_REMINDERS, "Read-later reminders", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Reminders to read the bookmarks you saved for later."
            }
        )
    }

    companion object {
        const val CHANNEL_ACTIVITY = "curio_activity"
        const val CHANNEL_REMINDERS = "curio_reminders"
        const val ACTIVITY_NOTIFICATION_ID = 1001
        private const val REMINDER_ID_BASE = 2000
        private const val PROGRESS_MAX = 100
    }
}
