package com.example.notifications

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Single source of truth for Curio's unified live activity. Every background source (workers, the
 * ViewModel's sync/digest paths) pushes coarse events here — [taskStarted]/[taskProgress]/
 * [taskFinished]/[digestReady]/[syncError] — and this controller reduces them into one
 * [CurioActivityState] and re-renders the single notification via [CurioNotifier].
 *
 * The state is a [MutableStateFlow]; because StateFlow conflates, a burst of progress updates from a
 * worker collapses to just the latest render — no debounce needed. When the state goes [isEmpty]
 * the notification is cancelled.
 *
 * Thread-safe: all mutators funnel through [MutableStateFlow.update]; the collector runs on the
 * supplied [scope] (an application-lifetime scope, so the activity outlives any screen/ViewModel).
 */
class CurioActivityController(
    private val scope: CoroutineScope,
    private val notifier: CurioNotifier,
) {
    private val _state = MutableStateFlow(CurioActivityState())
    val state: StateFlow<CurioActivityState> = _state.asStateFlow()

    init {
        scope.launch {
            state.collect { current ->
                if (current.isEmpty) notifier.cancelActivity() else notifier.render(current)
            }
        }
    }

    fun taskStarted(task: CurioTask) = _state.update { it.taskStarted(task) }

    fun taskProgress(task: CurioTask, done: Int, total: Int) =
        _state.update { it.taskProgress(task, done, total) }

    fun taskFinished(task: CurioTask) = _state.update { it.taskFinished(task) }

    fun digestReady(itemCount: Int) = _state.update { it.withDigestReady(itemCount) }

    /**
     * Surfaces a transient error, then auto-clears it after [ERROR_LINGER_MS] so a one-off failure
     * doesn't camp permanently in the shade. Active tasks (if any) resume the "working" headline.
     */
    fun syncError(message: String) {
        _state.update { it.withError(message) }
        scope.launch {
            delay(ERROR_LINGER_MS)
            _state.update { if (it.attention is Attention.Error) it.clearedAttention() else it }
        }
    }

    /** Clears any pending attention (digest-ready / error). Call when the user opens the app. */
    fun clearAttention() = _state.update { it.clearedAttention() }

    private companion object {
        const val ERROR_LINGER_MS = 6_000L
    }
}
