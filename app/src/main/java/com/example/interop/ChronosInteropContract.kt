package com.example.interop

import android.net.Uri

/**
 * Curio's mirror of ChronosFlow's interop handoff contract.
 *
 * ChronosFlow exposes a write-only "handoff" path on its exported provider
 * (`content://com.ChronosFlow.VBCR.share/handoff`). Curio inserts a single row to create a
 * reading-list item ("remind me to read later"), an inbox capture, or a follow-up task inside
 * ChronosFlow. There is no shared Gradle module between the two apps, so the path and column names
 * below MUST stay byte-for-byte equal to `com.ChronosFlow.VBCR.interop.InteropContract`.
 *
 * Security is enforced on the ChronosFlow side: the provider verifies Curio's signing certificate
 * (PeerVerifier) and a user-controlled inbound kill-switch before accepting any write.
 */
object ChronosInteropContract {
    const val CHRONOSFLOW_PACKAGE = "com.ChronosFlow.VBCR"
    const val PROVIDER_AUTHORITY = "$CHRONOSFLOW_PACKAGE.share"
    const val PATH_HANDOFF = "handoff"

    /** Discriminator value: one of [KIND_READING], [KIND_INBOX], [KIND_TASK]. */
    const val HANDOFF_KIND = "kind"
    const val HANDOFF_URL = "url"
    const val HANDOFF_TITLE = "title"
    const val HANDOFF_TEXT = "text"
    const val HANDOFF_REMINDER_AT = "reminder_at_epoch_ms"
    const val HANDOFF_NOTES = "notes"

    const val KIND_READING = "reading"
    const val KIND_INBOX = "inbox"
    const val KIND_TASK = "task"

    val HANDOFF_URI: Uri = Uri.parse("content://$PROVIDER_AUTHORITY/$PATH_HANDOFF")
}
