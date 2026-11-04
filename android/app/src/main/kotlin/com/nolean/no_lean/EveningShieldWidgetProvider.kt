package com.nolean.no_lean

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews

/**
 * Evening shield. Quiet outside the configured window; inside it the widget
 * turns red with a countdown to the window's end and three big buttons:
 * Call (opens the dialer, no number is stored on the widget), Walk 10 min (a
 * countdown on the widget itself) and Ride it out (opens the wave screen).
 * A widget cannot hide other apps, so this is deliberately not a launcher.
 */
class EveningShieldWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = updateAll(context)

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) =
        updateAll(context)

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_WALK -> {
                WidgetPack.prefs(context).edit()
                    .putLong(KEY_WALK_UNTIL, System.currentTimeMillis() + WALK_MILLIS).apply()
                // Also redraws a stretched NO LEAN widget showing the shield.
                NoLeanWidgetProvider.updateAllWidgets(context)
            }
            ACTION_TICK -> updateAll(context)
        }
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        WidgetPack.cancel(context, tick(context))
    }

    companion object {
        private const val ACTION_TICK = "com.nolean.no_lean.action.SHIELD_TICK"
        private const val ACTION_WALK = "com.nolean.no_lean.action.SHIELD_WALK"
        private const val KEY_WALK_UNTIL = "shield_walk_until"
        const val WALK_MILLIS = 10 * 60_000L
        private const val FULL_MIN_HEIGHT_DP = 200

        private fun tick(context: Context) =
            WidgetPack.broadcast(context, EveningShieldWidgetProvider::class.java, ACTION_TICK, 4)

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = WidgetPack.ids(context, EveningShieldWidgetProvider::class.java)
            if (ids.isEmpty()) return
            val now = System.currentTimeMillis()
            val night = NightTimeline.compute(now, WidgetPack.riskStart(context), WidgetPack.riskEnd(context), 0L)
            val active = night.phase == NightTimeline.Phase.ACTIVE
            val walkUntil = WidgetPack.prefs(context).getLong(KEY_WALK_UNTIL, 0L).takeIf { it > now }
            ids.forEach { id ->
                val views = WidgetSizing.views(context, manager, id) { build(context, now, night, active, walkUntil, it) }
                manager.updateAppWidget(id, views)
            }
            val edge = if (active) night.windowEndMillis else night.windowStartMillis.let {
                if (it > now) it else it + 24 * 3_600_000L
            }
            WidgetPack.schedule(context, tick(context), minOf(edge, walkUntil ?: Long.MAX_VALUE))
        }

        internal fun build(
            context: Context,
            now: Long,
            night: NightTimeline.State,
            active: Boolean,
            walkUntil: Long?,
            bucket: WidgetBucket,
        ): RemoteViews {
            val full = bucket.isFull
            val views = RemoteViews(
                context.packageName,
                if (full) R.layout.evening_shield_widget else R.layout.evening_shield_widget_compact,
            )
            views.setInt(
                R.id.shield_root,
                "setBackgroundResource",
                if (active) R.drawable.evening_shield_background_active else R.drawable.no_lean_widget_background,
            )
            val start = night.hours.firstOrNull()?.label ?: ""
            if (active) {
                views.setTextViewText(R.id.shield_title, context.getString(R.string.shield_title_active))
                // Launcher-ticked countdown to the window's end; no app wakeups.
                val base = SystemClock.elapsedRealtime() + (night.windowEndMillis - now)
                views.setChronometer(R.id.shield_countdown, base, context.getString(R.string.shield_countdown_format), true)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) views.setChronometerCountDown(R.id.shield_countdown, true)
                views.setViewVisibility(R.id.shield_countdown, View.VISIBLE)
            } else {
                views.setTextViewText(R.id.shield_title, context.getString(R.string.shield_title_quiet, start))
                views.setViewVisibility(R.id.shield_countdown, View.GONE)
            }
            views.setOnClickPendingIntent(R.id.shield_root, WidgetPack.openApp(context, null, 60))
            views.setOnClickPendingIntent(R.id.shield_action_ride, WidgetPack.openApp(context, MainActivity.WIDGET_ACTION_WAVE, 61))
            if (full) {
                val dial = PendingIntent.getActivity(
                    context,
                    62,
                    Intent(Intent.ACTION_DIAL).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                views.setOnClickPendingIntent(R.id.shield_action_call, dial)
                views.setOnClickPendingIntent(
                    R.id.shield_action_walk,
                    WidgetPack.broadcast(context, EveningShieldWidgetProvider::class.java, ACTION_WALK, 63),
                )
                if (walkUntil != null) {
                    val base = SystemClock.elapsedRealtime() + (walkUntil - now)
                    views.setChronometer(R.id.shield_walk_timer, base, context.getString(R.string.shield_walk_format), true)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) views.setChronometerCountDown(R.id.shield_walk_timer, true)
                    views.setViewVisibility(R.id.shield_walk_timer, View.VISIBLE)
                    views.setViewVisibility(R.id.shield_action_walk, View.GONE)
                } else {
                    views.setViewVisibility(R.id.shield_walk_timer, View.GONE)
                    views.setViewVisibility(R.id.shield_action_walk, View.VISIBLE)
                }
            }
            WidgetSizing.scaleText(
                views,
                bucket,
                R.id.shield_title to 11f,
                R.id.shield_countdown to (if (full) 34f else 22f),
                R.id.shield_action_ride to 15f,
                *(if (full) arrayOf(R.id.shield_action_call to 15f, R.id.shield_action_walk to 15f, R.id.shield_walk_timer to 15f) else emptyArray()),
            )
            return views
        }

        /** Live shield state, for the stretched NO LEAN widget. */
        fun buildNow(context: Context, bucket: WidgetBucket): RemoteViews {
            val now = System.currentTimeMillis()
            val night = NightTimeline.compute(now, WidgetPack.riskStart(context), WidgetPack.riskEnd(context), 0L)
            val walkUntil = WidgetPack.prefs(context).getLong(KEY_WALK_UNTIL, 0L).takeIf { it > now }
            return build(context, now, night, night.phase == NightTimeline.Phase.ACTIVE, walkUntil, bucket)
        }
    }
}
