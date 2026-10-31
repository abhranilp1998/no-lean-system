package com.nolean.no_lean

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.util.Calendar

/**
 * Shared plumbing for the full-screen widget pack (night timeline, garden,
 * evening shield, radar). Every widget in the pack is listed in [providers];
 * a future per-user picker only has to filter that list (and can disable the
 * receiver components) to switch widgets on or off.
 */
object WidgetPack {
    const val KEY_GARDEN_DIR = "garden_dir"
    const val KEY_GARDEN_TODAY = "garden_today"
    const val KEY_GARDEN_TOMORROW = "garden_tomorrow"
    const val KEY_RADAR_PATH = "radar_path"
    const val KEY_RADAR_ZONES = "radar_zones"
    const val KEY_HAS_NOTES = "has_notes"

    fun prefs(context: Context) =
        context.getSharedPreferences(NoLeanWidgetProvider.PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun riskStart(context: Context) = prefs(context).getInt(NightTimelineWidgetProvider.KEY_RISK_START, 17 * 60)
    fun riskEnd(context: Context) = prefs(context).getInt(NightTimelineWidgetProvider.KEY_RISK_END, 21 * 60)

    /** Re-renders every widget in the pack. */
    fun updateAll(context: Context) {
        NightTimelineWidgetProvider.updateAll(context)
        GardenWidgetProvider.updateAll(context)
        EveningShieldWidgetProvider.updateAll(context)
        RadarWidgetProvider.updateAll(context)
        NoteWidgetProvider.updateAll(context)
        NoLeanFullWidgetProvider.updateAll(context)
    }

    fun ids(context: Context, type: Class<out AppWidgetProvider>): IntArray =
        AppWidgetManager.getInstance(context).getAppWidgetIds(ComponentName(context, type))

    fun openApp(context: Context, action: String?, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (action != null) putExtra(MainActivity.EXTRA_WIDGET_ACTION, action)
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun broadcast(context: Context, type: Class<*>, action: String, requestCode: Int): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            requestCode,
            Intent(context, type).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    /** Inexact alarm: no exact-alarm permission; a few minutes late is fine. */
    fun schedule(context: Context, operation: PendingIntent, atMillis: Long) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarms.setAndAllowWhileIdle(AlarmManager.RTC, atMillis, operation)
    }

    fun cancel(context: Context, operation: PendingIntent) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarms.cancel(operation)
    }

    fun nextLocalHour(nowMillis: Long, calendar: Calendar = Calendar.getInstance()): Long {
        calendar.timeInMillis = nowMillis
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        calendar.add(Calendar.HOUR_OF_DAY, 1)
        return calendar.timeInMillis
    }

    fun dateKey(nowMillis: Long, calendar: Calendar = Calendar.getInstance()): String {
        calendar.timeInMillis = nowMillis
        return "%04d-%02d-%02d".format(
            calendar.get(Calendar.YEAR),
            calendar.get(Calendar.MONTH) + 1,
            calendar.get(Calendar.DAY_OF_MONTH),
        )
    }

    /** Which pre-rendered garden file applies now: today's, or tomorrow's after midnight. */
    fun gardenFile(
        dir: String,
        todayKey: String?,
        tomorrowKey: String?,
        nowKey: String,
        evening: Boolean,
    ): String? {
        val day = when (nowKey) {
            todayKey -> "today"
            tomorrowKey -> "tomorrow"
            else -> if (tomorrowKey != null && nowKey > tomorrowKey) "tomorrow" else "today"
        }
        return "$dir/garden_${day}_${if (evening) "evening" else "day"}.png"
    }

    /** Decodes widget art small enough for the RemoteViews bitmap budget. */
    fun decodeArt(path: String, maxSide: Int = 720): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > maxSide) sample *= 2
        return BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
    }

    fun minutesOfDay(nowMillis: Long, calendar: Calendar = Calendar.getInstance()): Int {
        calendar.timeInMillis = nowMillis
        return calendar.get(Calendar.HOUR_OF_DAY) * 60 + calendar.get(Calendar.MINUTE)
    }

    enum class Stretched { GARDEN, NIGHT, SHIELD }

    /**
     * What a stretched NO LEAN widget shows: the shield inside the window,
     * the night timeline in the 3 hours before it and after it ends, and the
     * garden the rest of the day. Privacy mode always gets the neutral
     * timeline.
     */
    fun stretchedView(phase: NightTimeline.Phase, nowMillis: Long, windowStartMillis: Long, privacy: Boolean): Stretched =
        when {
            privacy -> Stretched.NIGHT
            phase == NightTimeline.Phase.ACTIVE -> Stretched.SHIELD
            phase == NightTimeline.Phase.UPCOMING && windowStartMillis - nowMillis > 3 * 3_600_000L -> Stretched.GARDEN
            else -> Stretched.NIGHT
        }
}
