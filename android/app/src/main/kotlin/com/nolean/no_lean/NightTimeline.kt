package com.nolean.no_lean

import java.util.Calendar

/**
 * Pure model behind the night-timeline widget. Everything is derived from the
 * configured risk window and the last relapse time, so the widget can redraw
 * itself every hour without the Flutter app running.
 */
object NightTimeline {
    enum class Phase { UPCOMING, ACTIVE, BEATEN, SLIPPED }
    enum class Mark { DONE, NOW, AHEAD, SLIPPED }

    data class Hour(val startMillis: Long, val label: String, val mark: Mark)

    data class State(
        val phase: Phase,
        val windowStartMillis: Long,
        val windowEndMillis: Long,
        val hours: List<Hour>,
        /** When the widget must redraw next (next hour edge or window edge). */
        val nextRefreshMillis: Long,
    )

    private const val MINUTE = 60_000L
    private const val HOUR = 60 * MINUTE

    /** How long the beaten / slipped result stays up after the window ends. */
    const val RESULT_HOLD_MILLIS = 12 * HOUR

    fun compute(
        nowMillis: Long,
        startMinutes: Int,
        endMinutes: Int,
        lastRelapseMillis: Long,
        calendar: Calendar = Calendar.getInstance(),
    ): State {
        val durationMinutes = ((endMinutes - startMinutes) % 1440 + 1440) % 1440
        val duration = (if (durationMinutes == 0) 1440 else durationMinutes) * MINUTE
        calendar.timeInMillis = nowMillis
        calendar.set(Calendar.HOUR_OF_DAY, startMinutes / 60)
        calendar.set(Calendar.MINUTE, startMinutes % 60)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        if (calendar.timeInMillis > nowMillis) calendar.add(Calendar.DAY_OF_YEAR, -1)
        var start = calendar.timeInMillis
        var end = start + duration
        val phase: Phase
        if (nowMillis < end) {
            phase = Phase.ACTIVE
        } else if (nowMillis < end + RESULT_HOLD_MILLIS) {
            phase = if (lastRelapseMillis in start until end) Phase.SLIPPED else Phase.BEATEN
        } else {
            phase = Phase.UPCOMING
            calendar.add(Calendar.DAY_OF_YEAR, 1)
            start = calendar.timeInMillis
            end = start + duration
        }
        val hours = mutableListOf<Hour>()
        var cursor = start
        while (cursor < end) {
            calendar.timeInMillis = cursor
            val label = "%02d:%02d".format(
                calendar.get(Calendar.HOUR_OF_DAY),
                calendar.get(Calendar.MINUTE),
            )
            val next = minOf(cursor + HOUR, end)
            val mark = when {
                lastRelapseMillis in cursor until next -> Mark.SLIPPED
                nowMillis >= next -> Mark.DONE
                nowMillis >= cursor -> Mark.NOW
                else -> Mark.AHEAD
            }
            hours += Hour(cursor, label, mark)
            cursor = next
        }
        calendar.timeInMillis = nowMillis
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        calendar.add(Calendar.HOUR_OF_DAY, 1)
        val nextLocalHour = calendar.timeInMillis
        val edge = when (phase) {
            Phase.ACTIVE -> end
            Phase.UPCOMING -> start
            else -> end + RESULT_HOLD_MILLIS
        }
        val nextRefresh = minOf(edge, nextLocalHour)
        return State(phase, start, end, hours, maxOf(nextRefresh, nowMillis + MINUTE))
    }
}
