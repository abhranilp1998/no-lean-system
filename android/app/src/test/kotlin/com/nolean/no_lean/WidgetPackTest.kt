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

class WidgetSizingTest {
    @org.junit.Test
    fun bucketsGrowWithoutLimit() {
        org.junit.Assert.assertEquals(WidgetBucket.COMPACT, WidgetSizing.bucketFor(180, 110))
        org.junit.Assert.assertEquals(WidgetBucket.FULL, WidgetSizing.bucketFor(250, 250))
        org.junit.Assert.assertEquals(WidgetBucket.LARGE, WidgetSizing.bucketFor(300, 420))
        org.junit.Assert.assertEquals(WidgetBucket.HUGE, WidgetSizing.bucketFor(400, 800))
        org.junit.Assert.assertEquals(WidgetBucket.HUGE, WidgetSizing.bucketFor(5000, 5000))
        // Wide but short stays compact rather than looking stretched.
        org.junit.Assert.assertEquals(WidgetBucket.COMPACT, WidgetSizing.bucketFor(900, 120))
    }

    @org.junit.Test
    fun stretchedNoLeanFollowsTheEvening() {
        val h = 3_600_000L
        val start = 100 * h
        org.junit.Assert.assertEquals(WidgetPack.Stretched.SHIELD, WidgetPack.stretchedView(NightTimeline.Phase.ACTIVE, start + h, start, false))
        org.junit.Assert.assertEquals(WidgetPack.Stretched.NIGHT, WidgetPack.stretchedView(NightTimeline.Phase.UPCOMING, start - 2 * h, start, false))
        org.junit.Assert.assertEquals(WidgetPack.Stretched.GARDEN, WidgetPack.stretchedView(NightTimeline.Phase.UPCOMING, start - 6 * h, start, false))
        org.junit.Assert.assertEquals(WidgetPack.Stretched.NIGHT, WidgetPack.stretchedView(NightTimeline.Phase.BEATEN, start + 5 * h, start, false))
        org.junit.Assert.assertEquals(WidgetPack.Stretched.NIGHT, WidgetPack.stretchedView(NightTimeline.Phase.ACTIVE, start + h, start, true))
    }

    @org.junit.Test
    fun noteIsSealedOutsideTheEvening() {
        org.junit.Assert.assertEquals(NoteWidgetProvider.Status.EMPTY, NoteWidgetProvider.status(false, NightTimeline.Phase.ACTIVE))
        org.junit.Assert.assertEquals(NoteWidgetProvider.Status.SEALED, NoteWidgetProvider.status(true, NightTimeline.Phase.UPCOMING))
        org.junit.Assert.assertEquals(NoteWidgetProvider.Status.READY, NoteWidgetProvider.status(true, NightTimeline.Phase.ACTIVE))
    }
}

class StretchedViewsTest {
    private val h = 3_600_000L
    private val start = 100 * h

    @org.junit.Test
    fun classicWidgetsFillTallSizesWithTheirTallLayout() {
        org.junit.Assert.assertEquals(R.layout.no_lean_widget, NoLeanWidgetSize.MEDIUM.layoutFor(WidgetBucket.COMPACT))
        org.junit.Assert.assertEquals(R.layout.no_lean_widget_tall, NoLeanWidgetSize.MEDIUM.layoutFor(WidgetBucket.FULL))
        org.junit.Assert.assertEquals(R.layout.no_lean_widget_large, NoLeanWidgetSize.LARGE.layoutFor(WidgetBucket.FULL))
        org.junit.Assert.assertEquals(R.layout.no_lean_widget_large_tall, NoLeanWidgetSize.LARGE.layoutFor(WidgetBucket.HUGE))
        org.junit.Assert.assertEquals(R.layout.no_lean_widget_small, NoLeanWidgetSize.SMALL.layoutFor(WidgetBucket.HUGE))
    }

    @org.junit.Test
    fun onlyClassicWidgetsAndFullCanBeAddedFromTheApp() {
        org.junit.Assert.assertEquals(NoLeanFullWidgetProvider::class.java, StretchedViews.providerFor("full"))
        org.junit.Assert.assertEquals(NoLeanWidgetProvider::class.java, StretchedViews.providerFor("medium"))
        org.junit.Assert.assertNull(StretchedViews.providerFor("garden"))
        org.junit.Assert.assertFalse(StretchedViews.CLASSIC in StretchedViews.CHOICES)
    }

    @org.junit.Test
    fun fixedChoicesWinOverTimeOfDay() {
        val p = NightTimeline.Phase.ACTIVE
        org.junit.Assert.assertEquals(StretchedViews.View.GARDEN, StretchedViews.resolve("garden", p, start + h, start, false))
        org.junit.Assert.assertEquals(StretchedViews.View.WAVE, StretchedViews.resolve("wave", p, start + h, start, false))
        org.junit.Assert.assertEquals(StretchedViews.View.MAP, StretchedViews.resolve("map", p, start + h, start, false))
        org.junit.Assert.assertEquals(StretchedViews.View.NOTE, StretchedViews.resolve("note", p, start + h, start, false))
        org.junit.Assert.assertEquals(StretchedViews.View.SHIELD, StretchedViews.resolve("auto", p, start + h, start, false))
        org.junit.Assert.assertEquals(
            StretchedViews.View.GARDEN,
            StretchedViews.resolve(null, NightTimeline.Phase.UPCOMING, start - 6 * h, start, false),
        )
    }

    @org.junit.Test
    fun privacyForcesTheNeutralView() {
        StretchedViews.CHOICES.forEach {
            org.junit.Assert.assertEquals(
                StretchedViews.View.NIGHT,
                StretchedViews.resolve(it, NightTimeline.Phase.ACTIVE, start + h, start, true),
            )
        }
    }
}
