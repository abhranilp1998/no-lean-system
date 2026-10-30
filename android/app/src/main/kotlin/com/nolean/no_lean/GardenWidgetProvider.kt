package com.nolean.no_lean

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews

/**
 * Garden widget. The app pre-renders today's and tomorrow's garden (day and
 * evening variants); this provider only picks the right file, so midnight and
 * the evening switch happen without the app running.
 */
class GardenWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = updateAll(context)

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_TICK) updateAll(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        WidgetPack.cancel(context, tick(context))
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: android.os.Bundle) =
        updateAll(context)

    companion object {
        private const val ACTION_TICK = "com.nolean.no_lean.action.GARDEN_TICK"
        private const val EVENING_FROM_MINUTES = 18 * 60

        private fun tick(context: Context) =
            WidgetPack.broadcast(context, GardenWidgetProvider::class.java, ACTION_TICK, 3)

        fun updateAll(context: Context) {
            val ids = WidgetPack.ids(context, GardenWidgetProvider::class.java)
            if (ids.isEmpty()) return
            val manager = AppWidgetManager.getInstance(context)
            ids.forEach { id -> manager.updateAppWidget(id, WidgetSizing.views(context, manager, id) { build(context, it) }) }
            WidgetPack.schedule(context, tick(context), WidgetPack.nextLocalHour(System.currentTimeMillis()))
        }

        /** The garden art fills the widget at every size (fitCenter). */
        fun build(context: Context, bucket: WidgetBucket): RemoteViews {
            val prefs = WidgetPack.prefs(context)
            val now = System.currentTimeMillis()
            val minute = WidgetPack.minutesOfDay(now)
            val evening = minute >= minOf(EVENING_FROM_MINUTES, WidgetPack.riskStart(context)) || minute < 5 * 60
            val dir = prefs.getString(WidgetPack.KEY_GARDEN_DIR, null)
            val bitmap = dir?.let {
                WidgetPack.gardenFile(
                    it,
                    prefs.getString(WidgetPack.KEY_GARDEN_TODAY, null),
                    prefs.getString(WidgetPack.KEY_GARDEN_TOMORROW, null),
                    WidgetPack.dateKey(now),
                    evening,
                )
            }?.let { WidgetPack.decodeArt(it) }
            val views = RemoteViews(context.packageName, R.layout.garden_widget)
            if (bitmap != null) {
                views.setImageViewBitmap(R.id.garden_image, bitmap)
                views.setViewVisibility(R.id.garden_empty, View.GONE)
            } else {
                views.setViewVisibility(R.id.garden_empty, View.VISIBLE)
            }
            views.setOnClickPendingIntent(R.id.garden_root, WidgetPack.openApp(context, null, 40))
            WidgetSizing.scaleText(views, bucket, R.id.garden_empty to 12f)
            return views
        }
    }
}
