package com.nolean.no_lean

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews

class NoLeanWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val prefs = context.getSharedPreferences("no_lean_widget", Context.MODE_PRIVATE)
        val cleanTime = prefs.getString("clean_time", "0d 00h 00m")
        val streak = prefs.getString("streak_days", "0 DAYS")
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, com.nolean.no_lean.R.layout.no_lean_widget)
            views.setTextViewText(com.nolean.no_lean.R.id.widget_clean_time, cleanTime)
            views.setTextViewText(com.nolean.no_lean.R.id.widget_streak, streak)
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
