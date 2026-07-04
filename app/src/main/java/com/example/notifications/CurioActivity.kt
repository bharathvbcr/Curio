package com.example.notifications

/**
 * The single, unified "Curio activity" model.
 *
 * Curio deliberately posts exactly ONE ongoing notification (Android 16 "Live Updates" where
 * available, an ordinary ongoing progress notification otherwise) that collapses every concurrent
 * background operation — sync, the stale-link sweep, the embedding index, and digest generation —
 * into one live-updating item instead of a pile of separate notifications. This file holds the
 * pure, Android-free state so the reduce logic is unit-testable; [CurioActivityController] owns the
 * flow and [CurioNotifier] renders it.
 */

/** A background/async operation Curio can surface in its single live activity. */
enum class CurioTask(val label: String) {
    SYNC("Syncing bookmarks"),
    SWEEP("Tidying links"),
    INDEX("Building search index"),
    DIGEST("Preparing your digest"),
}

/** A momentary state that needs the user's attention; shown in place of the "working" headline. */
sealed interface Attention {
    data object None : Attention
    /** The weekly digest finished generating and is ready to read. */
    data class DigestReady(val itemCount: Int) : Attention
    /** A sync (or handoff) failed; carries a short, human-readable reason. */
    data class Error(val message: String) : Attention
}

/**
 * Immutable snapshot of what Curio is doing right now. All mutators return a new copy so the
 * reducer stays pure. [isEmpty] means "nothing to show" → the notification is dismissed.
 */
data class CurioActivityState(
    val activeTasks: Set<CurioTask> = emptySet(),
    /** Fractional progress (0..1) per task that reports counts; absent = indeterminate. */
    val progressByTask: Map<CurioTask, Float> = emptyMap(),
    val attention: Attention = Attention.None,
) {
    /** Aggregate progress across running tasks, or null when nothing reports a determinate count. */
    val progress: Float?
        get() {
            val known = activeTasks.mapNotNull { progressByTask[it] }
            return if (known.isEmpty()) null else (known.sum() / known.size).coerceIn(0f, 1f)
        }

    /** No running work and nothing awaiting attention → the live activity should be dismissed. */
    val isEmpty: Boolean
        get() = activeTasks.isEmpty() && attention == Attention.None

    /** True while the state represents in-progress work (renders as an ongoing notification). */
    val isOngoing: Boolean
        get() = activeTasks.isNotEmpty() && attention == Attention.None

    /** The notification title. */
    val headline: String
        get() = when (val a = attention) {
            is Attention.DigestReady -> "Your weekly digest is ready"
            is Attention.Error -> "Sync failed"
            Attention.None -> when {
                activeTasks.isEmpty() -> "Curio"
                activeTasks.size == 1 -> activeTasks.first().label + "…"
                else -> "Curio is tidying up…"
            }
        }

    /** The notification's secondary line, or null when there's nothing useful to add. */
    val detail: String?
        get() = when (val a = attention) {
            is Attention.DigestReady ->
                "${a.itemCount} ${if (a.itemCount == 1) "save" else "saves"} from the last 7 days"
            is Attention.Error -> a.message
            Attention.None -> when {
                activeTasks.size > 1 -> activeTasks.joinToString(" · ") { it.label }
                else -> null
            }
        }

    // ── Pure reducers ───────────────────────────────────────────────────────
    fun taskStarted(task: CurioTask): CurioActivityState =
        copy(activeTasks = activeTasks + task)

    fun taskProgress(task: CurioTask, done: Int, total: Int): CurioActivityState {
        if (total <= 0) return taskStarted(task)
        val fraction = (done.toFloat() / total.toFloat()).coerceIn(0f, 1f)
        return copy(activeTasks = activeTasks + task, progressByTask = progressByTask + (task to fraction))
    }

    fun taskFinished(task: CurioTask): CurioActivityState =
        copy(activeTasks = activeTasks - task, progressByTask = progressByTask - task)

    fun withDigestReady(itemCount: Int): CurioActivityState =
        copy(attention = Attention.DigestReady(itemCount))

    fun withError(message: String): CurioActivityState =
        copy(attention = Attention.Error(message))

    fun clearedAttention(): CurioActivityState =
        copy(attention = Attention.None)
}
