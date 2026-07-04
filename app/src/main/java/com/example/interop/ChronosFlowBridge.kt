package com.example.interop

import android.content.ContentValues
import android.content.Context
import android.util.Log

/**
 * Hands Curio bookmarks off to the ChronosFlow productivity app via its exported interop provider
 * (see [ChronosInteropContract]). This is the "remind me to read later" / watch-later integration:
 * a Curio bookmark becomes a ChronosFlow reading-list item (optionally with a scheduled reminder),
 * an inbox capture, or a follow-up task.
 *
 * Every call is best-effort. When ChronosFlow isn't installed, wasn't built to accept handoffs, or
 * rejects the caller's signature, the call returns a failed [Result] and Curio carries on
 * standalone — nothing here is allowed to crash a bookmark action.
 */
class ChronosFlowBridge(private val context: Context) {

    /** True when ChronosFlow is installed and its handoff provider is reachable from this app. */
    fun isAvailable(): Boolean = providerOwnerPackage() == ChronosInteropContract.CHRONOSFLOW_PACKAGE

    /**
     * Package that actually owns the handoff authority, or null if unresolved. Guards against an app
     * squatting `com.ChronosFlow.VBCR.share`; the real signature check happens on the provider side.
     */
    private fun providerOwnerPackage(): String? = try {
        context.packageManager
            .resolveContentProvider(ChronosInteropContract.PROVIDER_AUTHORITY, 0)
            ?.packageName
    } catch (e: Exception) {
        null
    }

    /**
     * Saves [url] to ChronosFlow's reading list ("read later"). When [reminderAtEpochMillis] is
     * non-null, ChronosFlow also schedules a "remind me to read later" notification at that time.
     */
    fun sendToReadingList(
        url: String,
        title: String? = null,
        reminderAtEpochMillis: Long? = null,
        notes: String? = null,
    ): Result<Unit> = insert(ChronosInteropContract.KIND_READING) {
        put(ChronosInteropContract.HANDOFF_URL, url)
        title?.takeIf { it.isNotBlank() }?.let { put(ChronosInteropContract.HANDOFF_TITLE, it) }
        notes?.takeIf { it.isNotBlank() }?.let { put(ChronosInteropContract.HANDOFF_NOTES, it) }
        reminderAtEpochMillis?.let { put(ChronosInteropContract.HANDOFF_REMINDER_AT, it) }
    }

    /** Captures [text] (a note or a link) into ChronosFlow's quick-capture inbox for later triage. */
    fun captureToInbox(text: String): Result<Unit> =
        insert(ChronosInteropContract.KIND_INBOX) {
            put(ChronosInteropContract.HANDOFF_TEXT, text)
        }

    /** Creates a follow-up task in ChronosFlow from [title] (with optional [notes] and [url]). */
    fun createTask(title: String, notes: String? = null, url: String? = null): Result<Unit> =
        insert(ChronosInteropContract.KIND_TASK) {
            put(ChronosInteropContract.HANDOFF_TITLE, title)
            notes?.takeIf { it.isNotBlank() }?.let { put(ChronosInteropContract.HANDOFF_TEXT, it) }
            url?.takeIf { it.isNotBlank() }?.let { put(ChronosInteropContract.HANDOFF_URL, it) }
        }

    private fun insert(kind: String, fill: ContentValues.() -> Unit): Result<Unit> {
        if (!isAvailable()) {
            return Result.failure(IllegalStateException("ChronosFlow is not installed"))
        }
        val values = ContentValues().apply {
            put(ChronosInteropContract.HANDOFF_KIND, kind)
            fill()
        }
        return try {
            val uri = context.contentResolver.insert(ChronosInteropContract.HANDOFF_URI, values)
            if (uri != null) {
                Result.success(Unit)
            } else {
                Result.failure(IllegalStateException("ChronosFlow declined the handoff"))
            }
        } catch (e: SecurityException) {
            // Signature not pinned, or the user disabled inbound handoffs in ChronosFlow.
            Log.w(TAG, "ChronosFlow denied $kind handoff: ${e.message}")
            Result.failure(e)
        } catch (e: Exception) {
            Log.w(TAG, "ChronosFlow $kind handoff failed: ${e.message}")
            Result.failure(e)
        }
    }

    private companion object {
        const val TAG = "ChronosFlowBridge"
    }
}
