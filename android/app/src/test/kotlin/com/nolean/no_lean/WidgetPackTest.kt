package com.nolean.no_lean

import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Test

class WidgetPackTest {
    private val zone = TimeZone.getTimeZone("Asia/Kolkata")

    @Test fun gardenPicksTodayThenTomorrowAfterMidnight() {
        val dir = "/d"
        assertEquals("/d/garden_today_day.png", WidgetPack.gardenFile(dir, "2026-10-30", "2026-10-31", "2026-10-30", false))
        assertEquals("/d/garden_tomorrow_evening.png", WidgetPack.gardenFile(dir, "2026-10-30", "2026-10-31", "2026-10-31", true))
        // App not opened for days: best available is tomorrow's art.
        assertEquals("/d/garden_tomorrow_day.png", WidgetPack.gardenFile(dir, "2026-10-30", "2026-10-31", "2026-11-03", false))
    }

    @Test fun nextLocalHourUsesLocalTimeNotUtc() {
        val cal = Calendar.getInstance(zone).apply { clear(); set(2026, Calendar.OCTOBER, 30, 19, 10) }
        val next = WidgetPack.nextLocalHour(cal.timeInMillis, Calendar.getInstance(zone))
        cal.set(Calendar.HOUR_OF_DAY, 20); cal.set(Calendar.MINUTE, 0)
        assertEquals(cal.timeInMillis, next)
        assertEquals("2026-10-30", WidgetPack.dateKey(next, Calendar.getInstance(zone)))
    }
}
