package com.nolean.no_lean

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Bundle

/** "NO LEAN Full": hosts any full-screen view at any size (default Auto). */
class NoLeanFullWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = updateAll(context)

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) =
        updateAll(context)

    override fun onReceive(context: Context, intent: Intent) {
        if (StretchedViews.handleCycle(context, intent)) return
        super.onReceive(context, intent)
        if (intent.action == ACTION_TICK) updateAll(context)
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        val edit = WidgetPack.prefs(context).edit()
        ids.forEach { edit.remove(StretchedViews.keyFor(it)) }
        edit.apply()
    }

    companion object {
        private const val ACTION_TICK = "com.nolean.no_lean.action.FULL_TICK"

        fun updateAll(context: Context) {
            val ids = WidgetPack.ids(context, NoLeanFullWidgetProvider::class.java)
            if (ids.isEmpty()) return
            val manager = AppWidgetManager.getInstance(context)
            val privacy = context.getSharedPreferences(NoLeanWidgetProvider.PREFERENCES_NAME, Context.MODE_PRIVATE)
                .getBoolean(NoLeanWidgetProvider.KEY_PRIVACY, false)
            ids.forEach { id ->
                manager.updateAppWidget(
                    id,
                    WidgetSizing.views(context, manager, id) {
                        StretchedViews.build(context, id, it, privacy, NoLeanFullWidgetProvider::class.java)
                    },
                )
            }
            WidgetPack.schedule(
                context,
                WidgetPack.broadcast(context, NoLeanFullWidgetProvider::class.java, ACTION_TICK, 71),
                NightTimelineWidgetProvider.nextRefresh(context),
            )
        }
    }
}
