package com.nolean.no_lean

import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NightTimelineTest {
    private val zone = TimeZone.getTimeZone("Asia/Kolkata")

    private fun at(day: Int, hour: Int, minute: Int = 0): Long =
        Calendar.getInstance(zone).apply {
            clear()
            set(2026, Calendar.OCTOBER, day, hour, minute)
        }.timeInMillis

    private fun compute(now: Long, relapse: Long = 0L, start: Int = 17 * 60, end: Int = 21 * 60) =
        NightTimeline.compute(now, start, end, relapse, Calendar.getInstance(zone))

    @Test fun beforeWindowIsUpcomingWithFourHours() {
        val s = compute(at(30, 14))
        assertEquals(NightTimeline.Phase.UPCOMING, s.phase)
        assertEquals(listOf("17:00", "18:00", "19:00", "20:00"), s.hours.map { it.label })
        assertEquals(at(30, 15), s.nextRefreshMillis)
    }

    @Test fun duringWindowMarksHeldAndNow() {
        val s = compute(at(30, 19, 20))
        assertEquals(NightTimeline.Phase.ACTIVE, s.phase)
        assertEquals(
            listOf(NightTimeline.Mark.DONE, NightTimeline.Mark.DONE, NightTimeline.Mark.NOW, NightTimeline.Mark.AHEAD),
            s.hours.map { it.mark },
        )
        assertEquals(at(30, 20), s.nextRefreshMillis)
    }

    @Test fun afterWindowWithoutRelapseIsBeaten() {
        assertEquals(NightTimeline.Phase.BEATEN, compute(at(30, 22), relapse = at(29, 18)).phase)
        assertEquals(NightTimeline.Phase.BEATEN, compute(at(31, 8)).phase)
    }

    @Test fun relapseInsideWindowIsSlippedAndMarksItsHour() {
        val s = compute(at(30, 22), relapse = at(30, 18, 30))
        assertEquals(NightTimeline.Phase.SLIPPED, s.phase)
        assertEquals(NightTimeline.Mark.SLIPPED, s.hours[1].mark)
    }

    @Test fun overnightWindowAndCustomWindow() {
        val s = compute(at(31, 1), start = 22 * 60, end = 2 * 60)
        assertEquals(NightTimeline.Phase.ACTIVE, s.phase)
        assertEquals(listOf("22:00", "23:00", "00:00", "01:00"), s.hours.map { it.label })
        assertTrue(s.hours.take(3).all { it.mark == NightTimeline.Mark.DONE })
    }

    @Test fun refreshNeverInThePast() {
        val now = at(30, 20, 59)
        assertTrue(compute(now).nextRefreshMillis > now)
    }
}
