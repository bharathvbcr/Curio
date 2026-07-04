package com.example.interop

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * Unit tests for the Curio side of the ChronosFlow handoff: the reminder-time presets and the
 * mirrored contract literals (which MUST stay byte-for-byte equal to ChronosFlow's contract, or
 * inserts silently no-op). Robolectric so android.net.Uri (used by the contract) resolves.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ChronosInteropTest {

    private val utc: ZoneId = ZoneOffset.UTC
    private fun ms(iso: String): Long = Instant.parse(iso).toEpochMilli()

    @Test
    fun `NONE has no reminder time`() {
        assertNull(ChronosReminderChoice.NONE.toEpochMillis())
    }

    @Test
    fun `IN_ONE_HOUR is exactly one hour from now`() {
        val now = ms("2026-06-22T18:00:00Z")
        assertEquals(now + 3_600_000L, ChronosReminderChoice.IN_ONE_HOUR.toEpochMillis(now, utc))
    }

    @Test
    fun `TONIGHT is 8pm today when it has not yet passed`() {
        val now = ms("2026-06-22T18:00:00Z")
        assertEquals(ms("2026-06-22T20:00:00Z"), ChronosReminderChoice.TONIGHT.toEpochMillis(now, utc))
    }

    @Test
    fun `TONIGHT rolls to tomorrow when 8pm already passed`() {
        val now = ms("2026-06-22T21:00:00Z")
        assertEquals(ms("2026-06-23T20:00:00Z"), ChronosReminderChoice.TONIGHT.toEpochMillis(now, utc))
    }

    @Test
    fun `TOMORROW is 9am the next day`() {
        val now = ms("2026-06-22T18:00:00Z")
        assertEquals(ms("2026-06-23T09:00:00Z"), ChronosReminderChoice.TOMORROW.toEpochMillis(now, utc))
    }

    @Test
    fun `every concrete reminder time is in the future`() {
        val now = ms("2026-06-22T23:30:00Z")
        ChronosReminderChoice.values()
            .mapNotNull { it.toEpochMillis(now, utc) }
            .forEach { assertTrue("reminder must be in the future", it > now) }
    }

    /**
     * Guards the cross-app contract: these literals are mirrored (not shared) with
     * com.ChronosFlow.VBCR.interop.InteropContract. If either side changes a string, handoff inserts
     * stop matching and silently no-op — so pin the exact values here.
     */
    @Test
    fun `handoff contract literals match the ChronosFlow provider schema`() {
        assertEquals("com.ChronosFlow.VBCR", ChronosInteropContract.CHRONOSFLOW_PACKAGE)
        assertEquals("com.ChronosFlow.VBCR.share", ChronosInteropContract.PROVIDER_AUTHORITY)
        assertEquals("handoff", ChronosInteropContract.PATH_HANDOFF)
        assertEquals("kind", ChronosInteropContract.HANDOFF_KIND)
        assertEquals("url", ChronosInteropContract.HANDOFF_URL)
        assertEquals("title", ChronosInteropContract.HANDOFF_TITLE)
        assertEquals("text", ChronosInteropContract.HANDOFF_TEXT)
        assertEquals("reminder_at_epoch_ms", ChronosInteropContract.HANDOFF_REMINDER_AT)
        assertEquals("notes", ChronosInteropContract.HANDOFF_NOTES)
        assertEquals("reading", ChronosInteropContract.KIND_READING)
        assertEquals("inbox", ChronosInteropContract.KIND_INBOX)
        assertEquals("task", ChronosInteropContract.KIND_TASK)
        assertEquals("content://com.ChronosFlow.VBCR.share/handoff", ChronosInteropContract.HANDOFF_URI.toString())
    }
}
