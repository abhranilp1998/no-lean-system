package com.nolean.no_lean

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews

/**
 * Night timeline: the configured risk window laid out hour by hour. It redraws
 * itself at every local hour and at the window edges via an inexact alarm, so
 * it stays correct without the app being opened.
 *
 * Android 12+ gets responsive layouts (compact below ~4x2, full timeline above);
 * older launchers get a layout picked from the reported widget height.
 */
class NightTimelineWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { id -> render(context, manager, id) }
        if (ids.isNotEmpty()) scheduleNext(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        options: Bundle,
    ) {
        render(context, manager, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_TICK) updateAll(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarms.cancel(tickIntent(context))
    }

    companion object {
        const val KEY_RISK_START = "risk_start_minutes"
        const val KEY_RISK_END = "risk_end_minutes"
        private const val ACTION_TICK = "com.nolean.no_lean.action.NIGHT_TIMELINE_TICK"
        private const val COMPACT_MAX_HEIGHT_DP = 180

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, NightTimelineWidgetProvider::class.java))
            if (ids.isEmpty()) return
            ids.forEach { render(context, manager, it) }
            scheduleNext(context)
        }

        private fun state(context: Context): Pair<NightTimeline.State, Boolean> {
            val prefs = context.getSharedPreferences(NoLeanWidgetProvider.PREFERENCES_NAME, Context.MODE_PRIVATE)
            val privacy = prefs.getBoolean(NoLeanWidgetProvider.KEY_PRIVACY, false)
            val state = NightTimeline.compute(
                nowMillis = System.currentTimeMillis(),
                startMinutes = prefs.getInt(KEY_RISK_START, 17 * 60),
                endMinutes = prefs.getInt(KEY_RISK_END, 21 * 60),
                lastRelapseMillis = if (privacy) 0L else prefs.getLong(NoLeanWidgetProvider.KEY_LAST_DOSE_EPOCH_MILLIS, 0L),
            )
            return state to privacy
        }

        private fun render(context: Context, manager: AppWidgetManager, id: Int) {
            val (state, privacy) = state(context)
            val views = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                RemoteViews(
                    mapOf(
                        SizeF(180f, 110f) to build(context, state, privacy, full = false),
                        SizeF(180f, COMPACT_MAX_HEIGHT_DP.toFloat()) to build(context, state, privacy, full = true),
                    ),
                )
            } else {
                val height = manager.getAppWidgetOptions(id)
                    .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, COMPACT_MAX_HEIGHT_DP)
                build(context, state, privacy, full = height >= COMPACT_MAX_HEIGHT_DP)
            }
            manager.updateAppWidget(id, views)
        }

        internal fun build(
            context: Context,
            state: NightTimeline.State,
            privacy: Boolean,
            full: Boolean,
        ): RemoteViews {
            val layout = if (full) R.layout.night_timeline_widget else R.layout.night_timeline_widget_compact
            val views = RemoteViews(context.packageName, layout)
            val first = state.hours.firstOrNull()?.label ?: ""
            val endLabel = android.text.format.DateFormat.format("HH:mm", state.windowEndMillis).toString()
            views.setTextViewText(R.id.night_window, "$first–$endLabel")
            views.setTextViewText(
                R.id.night_title,
                context.getString(if (privacy) R.string.night_title_private else R.string.night_title),
            )
            val held = state.hours.count { it.mark == NightTimeline.Mark.DONE }
            val headline = when {
                privacy -> context.getString(R.string.night_headline_private)
                state.phase == NightTimeline.Phase.BEATEN -> context.getString(R.string.night_headline_beaten)
                state.phase == NightTimeline.Phase.SLIPPED -> context.getString(R.string.night_headline_slipped)
                state.phase == NightTimeline.Phase.ACTIVE ->
                    context.getString(R.string.night_headline_active, held, state.hours.size)
                else -> context.getString(R.string.night_headline_upcoming, first)
            }
            views.setTextViewText(R.id.night_headline, headline)
            views.setTextColor(
                R.id.night_headline,
                context.getColor(
                    when {
                        privacy -> R.color.widget_muted
                        state.phase == NightTimeline.Phase.BEATEN -> R.color.widget_toxic
                        state.phase == NightTimeline.Phase.SLIPPED -> R.color.widget_muted
                        else -> R.color.widget_cyan
                    },
                ),
            )
            views.setOnClickPendingIntent(R.id.night_root, openApp(context, null, 30))
            if (full) {
                views.removeAllViews(R.id.night_rows)
                state.hours.forEach { hour ->
                    val row = RemoteViews(context.packageName, R.layout.night_timeline_row)
                    row.setTextViewText(R.id.night_row_time, hour.label)
                    val (text, color) = when {
                        privacy -> "" to R.color.widget_muted
                        hour.mark == NightTimeline.Mark.DONE -> context.getString(R.string.night_mark_done) to R.color.widget_toxic
                        hour.mark == NightTimeline.Mark.NOW -> context.getString(R.string.night_mark_now) to R.color.widget_cyan
                        hour.mark == NightTimeline.Mark.SLIPPED -> context.getString(R.string.night_mark_slipped) to R.color.widget_muted
                        else -> context.getString(R.string.night_mark_ahead) to R.color.widget_muted
                    }
                    row.setTextViewText(R.id.night_row_mark, text)
                    row.setTextColor(R.id.night_row_mark, context.getColor(color))
                    views.addView(R.id.night_rows, row)
                }
                views.setViewVisibility(R.id.night_action_sos, View.VISIBLE)
                views.setOnClickPendingIntent(
                    R.id.night_action_sos,
                    openApp(context, MainActivity.WIDGET_ACTION_SOS, 31),
                )
            }
            return views
        }

        private fun openApp(context: Context, action: String?, requestCode: Int): PendingIntent {
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

        private fun tickIntent(context: Context): PendingIntent {
            val intent = Intent(context, NightTimelineWidgetProvider::class.java).apply { action = ACTION_TICK }
            return PendingIntent.getBroadcast(
                context,
                2,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        /** Inexact (no exact-alarm permission needed); a few minutes late is fine. */
        private fun scheduleNext(context: Context) {
            val (state, _) = state(context)
            val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarms.setAndAllowWhileIdle(AlarmManager.RTC, state.nextRefreshMillis, tickIntent(context))
        }
    }
}
