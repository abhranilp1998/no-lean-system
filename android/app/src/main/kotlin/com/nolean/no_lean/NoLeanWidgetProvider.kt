package com.nolean.no_lean

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.widget.RemoteViews
import kotlin.math.max

class NoLeanWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val prefs = context.getSharedPreferences("no_lean_widget", Context.MODE_PRIVATE)
        val lastDoseEpochMillis = prefs.getLong(KEY_LAST_DOSE_EPOCH_MILLIS, 0L)
        val nowEpochMillis = System.currentTimeMillis()
        val elapsedMillis = if (lastDoseEpochMillis > 0L) {
            max(0L, nowEpochMillis - lastDoseEpochMillis)
        } else {
            0L
        }
        val wholeDays = elapsedMillis / DAY_MILLIS
        val withinDayMillis = elapsedMillis % DAY_MILLIS

        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.no_lean_widget)
            if (lastDoseEpochMillis > 0L) {
                // Chronometer is rendered and ticked by the launcher process. This gives the
                // widget real seconds without waking this app once a second. Its base is scoped
                // to the current elapsed day so the result is D + H:MM:SS.
                val chronometerBase = SystemClock.elapsedRealtime() - withinDayMillis
                val chronometerFormat = if (withinDayMillis < HOUR_MILLIS) {
                    "${wholeDays}d 00:%s"
                } else {
                    "${wholeDays}d %s"
                }
                views.setChronometer(R.id.widget_clean_time, chronometerBase, chronometerFormat, true)
                views.setTextViewText(
                    R.id.widget_streak,
                    if (wholeDays == 1L) "1 DAY // STREAK ACTIVE" else "$wholeDays DAYS // STREAK ACTIVE",
                )
            } else {
                views.setChronometer(R.id.widget_clean_time, SystemClock.elapsedRealtime(), "0d 00:%s", false)
                views.setTextViewText(
                    R.id.widget_clean_time,
                    prefs.getString("clean_time", "0d 00h 00m 00s"),
                )
                views.setTextViewText(
                    R.id.widget_streak,
                    prefs.getString("streak_days", "OPEN APP TO SYNC"),
                )
            }

            views.setOnClickPendingIntent(R.id.widget_root, openAppPendingIntent(context))
            appWidgetManager.updateAppWidget(id, views)
        }

        if (appWidgetIds.isNotEmpty() && lastDoseEpochMillis > 0L) {
            scheduleNextFormatBoundary(context, elapsedMillis)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (
            intent.action == ACTION_REFRESH_BOUNDARY ||
                intent.action == Intent.ACTION_TIME_CHANGED ||
                intent.action == Intent.ACTION_TIMEZONE_CHANGED ||
                intent.action == Intent.ACTION_BOOT_COMPLETED
        ) {
            updateAllWidgets(context)
        }
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(refreshPendingIntent(context))
    }

    private fun openAppPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun scheduleNextFormatBoundary(context: Context, elapsedMillis: Long) {
        // The system AppWidget update interval bottoms out at 30 minutes. A lightweight,
        // inexact boundary alarm only repairs D/H formatting when the Chronometer rolls over;
        // the launcher's Chronometer continues to supply live seconds between updates.
        val untilNextHour = HOUR_MILLIS - (elapsedMillis % HOUR_MILLIS)
        val triggerAtElapsed = SystemClock.elapsedRealtime() + untilNextHour
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val operation = refreshPendingIntent(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME, triggerAtElapsed, operation)
        } else {
            alarmManager.set(AlarmManager.ELAPSED_REALTIME, triggerAtElapsed, operation)
        }
    }

    private fun refreshPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, NoLeanWidgetProvider::class.java).apply {
            action = ACTION_REFRESH_BOUNDARY
        }
        return PendingIntent.getBroadcast(
            context,
            1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    companion object {
        const val PREFERENCES_NAME = "no_lean_widget"
        const val KEY_LAST_DOSE_EPOCH_MILLIS = "last_dose_epoch_millis"

        private const val ACTION_REFRESH_BOUNDARY =
            "com.nolean.no_lean.action.REFRESH_WIDGET_BOUNDARY"
        private const val HOUR_MILLIS = 60L * 60L * 1000L
        private const val DAY_MILLIS = 24L * HOUR_MILLIS

        private fun updateAllWidgets(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, NoLeanWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) {
                NoLeanWidgetProvider().onUpdate(context, manager, ids)
            }
        }
    }
}
