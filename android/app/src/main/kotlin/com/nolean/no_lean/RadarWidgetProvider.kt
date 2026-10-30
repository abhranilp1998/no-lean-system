package com.nolean.no_lean

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews

/**
 * Static map of saved places, drawn by the app whenever zones change. It is a
 * snapshot, not live tracking; nearby warnings stay with the existing opt-in
 * background zone alerts (notifications).
 */
class RadarWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = updateAll(context)

    companion object {
        fun updateAll(context: Context) {
            val ids = WidgetPack.ids(context, RadarWidgetProvider::class.java)
            if (ids.isEmpty()) return
            val prefs = WidgetPack.prefs(context)
            val count = prefs.getInt(WidgetPack.KEY_RADAR_ZONES, 0)
            val bitmap = prefs.getString(WidgetPack.KEY_RADAR_PATH, null)?.let { WidgetPack.decodeArt(it) }
            val views = RemoteViews(context.packageName, R.layout.radar_widget)
            if (bitmap != null) views.setImageViewBitmap(R.id.radar_image, bitmap)
            views.setTextViewText(
                R.id.radar_caption,
                if (count == 0) context.getString(R.string.radar_empty)
                else context.resources.getQuantityString(R.plurals.radar_places, count, count),
            )
            views.setViewVisibility(R.id.radar_image, if (bitmap != null) View.VISIBLE else View.INVISIBLE)
            views.setOnClickPendingIntent(R.id.radar_root, WidgetPack.openApp(context, MainActivity.WIDGET_ACTION_MAP, 50))
            AppWidgetManager.getInstance(context).updateAppWidget(ids, views)
        }
    }
}
