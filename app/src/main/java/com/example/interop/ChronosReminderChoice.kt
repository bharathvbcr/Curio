package com.example.interop

import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId

/**
 * Preset "remind me to read later" times offered when handing a bookmark to ChronosFlow. The app
 * has no time picker; these cover the common cases. Each maps to an absolute epoch-millis instant
 * that ChronosFlow schedules a reminder for.
 */
enum class ChronosReminderChoice(val label: String) {
    NONE("No reminder"),
    IN_ONE_HOUR("In 1 hour"),
    TONIGHT("Tonight, 8 PM"),
    TOMORROW("Tomorrow, 9 AM");

    /**
     * The reminder instant in epoch millis, or null for [NONE]. [TONIGHT] and [TOMORROW] always
     * resolve to a future time (rolling forward a day if the wall-clock target has already passed).
     */
    fun toEpochMillis(
        nowMillis: Long = System.currentTimeMillis(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): Long? = when (this) {
        NONE -> null
        IN_ONE_HOUR -> nowMillis + ONE_HOUR_MS
        TONIGHT -> nextOccurrenceOf(LocalTime.of(20, 0), nowMillis, zone)
        TOMORROW -> Instant.ofEpochMilli(nowMillis).atZone(zone).toLocalDate()
            .plusDays(1).atTime(9, 0).atZone(zone).toInstant().toEpochMilli()
    }

    private fun nextOccurrenceOf(time: LocalTime, nowMillis: Long, zone: ZoneId): Long {
        val date = Instant.ofEpochMilli(nowMillis).atZone(zone).toLocalDate()
        val today = date.atTime(time).atZone(zone).toInstant().toEpochMilli()
        // Use plusDays(1) on LocalDate (not raw +24h) so DST transitions don't shift the time.
        return if (today > nowMillis) today
        else date.plusDays(1).atTime(time).atZone(zone).toInstant().toEpochMilli()
    }

    private companion object {
        const val ONE_HOUR_MS = 60L * 60L * 1000L
    }
}
