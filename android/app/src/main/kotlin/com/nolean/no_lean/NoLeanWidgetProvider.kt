package com.nolean.no_lean

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import kotlin.math.max

/**
 * Home-screen widget sizes. Every layout has widget_root, widget_status,
 * widget_clean_time, widget_neutral and widget_action_sos; the flags say which
 * optional views exist, because RemoteViews fails the whole update when it
 * touches a view id that the layout does not contain.
 */
enum class NoLeanWidgetSize(
    val layout: Int,
    val hasTitle: Boolean,
    val hasDetails: Boolean,
    val hasCraving: Boolean,
    val hasRelapse: Boolean,
    val hasCode: Boolean,
) {
    SMALL(R.layout.no_lean_widget_small, false, false, false, false, false),
    MEDIUM(R.layout.no_lean_widget, true, true, true, true, false),
    LARGE(R.layout.no_lean_widget_large, true, true, true, true, true),
}

/** The original 4x2 widget. Subclasses only change the size. */
open class NoLeanWidgetProvider(
    private val size: NoLeanWidgetSize = NoLeanWidgetSize.MEDIUM,
) : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val prefs = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
        val privacy = prefs.getBoolean(KEY_PRIVACY, false)
        val lastDoseEpochMillis = if (privacy) 0L else prefs.getLong(KEY_LAST_DOSE_EPOCH_MILLIS, 0L)
        val nowEpochMillis = System.currentTimeMillis()
        val elapsedMillis = if (lastDoseEpochMillis > 0L) {
            max(0L, nowEpochMillis - lastDoseEpochMillis)
        } else {
            0L
        }
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, size.layout)
            if (privacy) {
                bindPrivate(context, views)
            } else {
                bindFull(context, views, prefs, lastDoseEpochMillis, elapsedMillis)
            }
            bindActions(context, views)
            appWidgetManager.updateAppWidget(id, views)
        }

        if (appWidgetIds.isNotEmpty() && lastDoseEpochMillis > 0L) {
            scheduleNextFormatBoundary(context, elapsedMillis)
        }
    }

    /** Neutral copy only: no counter, streak, risk or pledge state. */
    private fun bindPrivate(context: Context, views: RemoteViews) {
        if (size.hasTitle) {
            views.setTextViewText(R.id.widget_title, context.getString(R.string.widget_title_private))
        }
        views.setViewVisibility(R.id.widget_status, View.GONE)
        views.setChronometer(R.id.widget_clean_time, SystemClock.elapsedRealtime(), null, false)
        views.setViewVisibility(R.id.widget_clean_time, View.GONE)
        views.setViewVisibility(R.id.widget_neutral, View.VISIBLE)
        if (size.hasDetails) {
            views.setViewVisibility(R.id.widget_streak, View.GONE)
            views.setViewVisibility(R.id.widget_pledge, View.GONE)
        }
        label(context, views, R.id.widget_action_sos, R.string.widget_action_sos_private)
        if (size.hasCraving) label(context, views, R.id.widget_action_craving, R.string.widget_action_craving_private)
        if (size.hasRelapse) label(context, views, R.id.widget_action_relapse, R.string.widget_action_relapse_private)
        if (size.hasCode) label(context, views, R.id.widget_action_code, R.string.widget_action_code_private)
    }

    private fun bindFull(
        context: Context,
        views: RemoteViews,
        prefs: android.content.SharedPreferences,
        lastDoseEpochMillis: Long,
        elapsedMillis: Long,
    ) {
        val wholeDays = elapsedMillis / DAY_MILLIS
        val withinDayMillis = elapsedMillis % DAY_MILLIS
        val isRiskWindow = prefs.getBoolean(KEY_IS_RISK_WINDOW, false)
        val hasPledgedToday = prefs.getBoolean(KEY_HAS_PLEDGED_TODAY, false)

        if (size.hasTitle) {
            views.setTextViewText(R.id.widget_title, context.getString(R.string.widget_title))
        }
        val status = context.getString(
            if (isRiskWindow) R.string.widget_status_risk else R.string.widget_status_stable,
        )
        views.setViewVisibility(R.id.widget_status, View.VISIBLE)
        views.setTextViewText(R.id.widget_status, status)
        views.setContentDescription(R.id.widget_status, status)
        views.setTextColor(
            R.id.widget_status,
            context.getColor(if (isRiskWindow) R.color.widget_red else R.color.widget_toxic),
        )
        views.setViewVisibility(R.id.widget_clean_time, View.VISIBLE)
        views.setViewVisibility(R.id.widget_neutral, View.GONE)
        if (size.hasDetails) {
            views.setViewVisibility(R.id.widget_streak, View.VISIBLE)
            views.setViewVisibility(R.id.widget_pledge, View.VISIBLE)
        }
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
            if (size.hasDetails) {
                views.setTextViewText(
                    R.id.widget_streak,
                    context.resources.getQuantityString(
                        R.plurals.widget_clean_days,
                        wholeDays.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
                        wholeDays,
                    ),
                )
            }
        } else {
            views.setChronometer(R.id.widget_clean_time, SystemClock.elapsedRealtime(), "0d 00:%s", false)
            views.setTextViewText(
                R.id.widget_clean_time,
                prefs.getString("clean_time", "0d 00h 00m 00s"),
            )
            if (size.hasDetails) {
                views.setTextViewText(
                    R.id.widget_streak,
                    prefs.getString("streak_days", "OPEN APP TO SYNC"),
                )
            }
        }
        if (size.hasDetails) {
            views.setTextViewText(
                R.id.widget_pledge,
                context.getString(
                    if (hasPledgedToday) R.string.widget_pledge_complete else R.string.widget_pledge_pending,
                ),
            )
        }
        label(context, views, R.id.widget_action_sos, R.string.widget_action_sos)
        if (size.hasCraving) label(context, views, R.id.widget_action_craving, R.string.widget_action_craving)
        if (size.hasRelapse) label(context, views, R.id.widget_action_relapse, R.string.widget_action_relapse)
        if (size.hasCode) label(context, views, R.id.widget_action_code, R.string.widget_action_code)
    }

    private fun label(context: Context, views: RemoteViews, id: Int, text: Int) {
        val value = context.getString(text)
        views.setTextViewText(id, value)
        views.setContentDescription(id, value)
    }

    private fun bindActions(context: Context, views: RemoteViews) {
        views.setOnClickPendingIntent(R.id.widget_root, openAppPendingIntent(context))
        views.setOnClickPendingIntent(
            R.id.widget_action_sos,
            widgetActionPendingIntent(context, MainActivity.WIDGET_ACTION_SOS, 10),
        )
        if (size.hasCraving) {
            views.setOnClickPendingIntent(
                R.id.widget_action_craving,
                widgetActionPendingIntent(context, MainActivity.WIDGET_ACTION_CRAVING, 11),
            )
        }
        if (size.hasRelapse) {
            views.setOnClickPendingIntent(
                R.id.widget_action_relapse,
                widgetActionPendingIntent(context, MainActivity.WIDGET_ACTION_RELAPSE, 12),
            )
        }
        if (size.hasCode) {
            views.setOnClickPendingIntent(
                R.id.widget_action_code,
                widgetActionPendingIntent(context, MainActivity.WIDGET_ACTION_CODE, 13),
            )
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
        // The boundary alarm is shared by every size; keep it while any remain.
        if (allWidgetIds(context).isEmpty()) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.cancel(refreshPendingIntent(context))
        }
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

    private fun widgetActionPendingIntent(
        context: Context,
        action: String,
        requestCode: Int,
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_WIDGET_ACTION, action)
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
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
        alarmManager.setAndAllowWhileIdle(
            AlarmManager.ELAPSED_REALTIME,
            triggerAtElapsed,
            operation,
        )
    }

    private fun refreshPendingIntent(context: Context): PendingIntent {
        // Always the 4x2 receiver: it refreshes every size.
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
        const val KEY_IS_RISK_WINDOW = "is_risk_window"
        const val KEY_HAS_PLEDGED_TODAY = "has_pledged_today"
        const val KEY_PRIVACY = "privacy"

        private const val ACTION_REFRESH_BOUNDARY =
            "com.nolean.no_lean.action.REFRESH_WIDGET_BOUNDARY"
        private const val HOUR_MILLIS = 60L * 60L * 1000L
        private const val DAY_MILLIS = 24L * HOUR_MILLIS

        private fun providers(): List<Pair<Class<out NoLeanWidgetProvider>, () -> NoLeanWidgetProvider>> = listOf(
            NoLeanWidgetProvider::class.java to { NoLeanWidgetProvider() },
            NoLeanSmallWidgetProvider::class.java to { NoLeanSmallWidgetProvider() },
            NoLeanLargeWidgetProvider::class.java to { NoLeanLargeWidgetProvider() },
        )

        private fun allWidgetIds(context: Context): List<Int> {
            val manager = AppWidgetManager.getInstance(context)
            return providers().flatMap { (type, _) ->
                manager.getAppWidgetIds(ComponentName(context, type)).toList()
            }
        }

        /** Re-renders every placed widget of every size. */
        fun updateAllWidgets(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            providers().forEach { (type, create) ->
                val ids = manager.getAppWidgetIds(ComponentName(context, type))
                if (ids.isNotEmpty()) create().onUpdate(context, manager, ids)
            }
        }
    }
}

/** 2x1: counter (or neutral line) and one SOS button. */
class NoLeanSmallWidgetProvider : NoLeanWidgetProvider(NoLeanWidgetSize.SMALL)

/** 4x3: everything in 4x2 plus Code Instead. */
class NoLeanLargeWidgetProvider : NoLeanWidgetProvider(NoLeanWidgetSize.LARGE)
