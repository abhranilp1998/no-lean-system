package com.nolean.no_lean

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "no_lean/widget").setMethodCallHandler { call, result ->
            if (call.method == "update") {
                val cleanTime = call.argument<String>("cleanTime") ?: "0d 00h 00m"
                val streak = call.argument<String>("streak") ?: "0 DAYS"
                val lastDoseEpochMillis = call.argument<Number>("lastDoseEpochMillis")?.toLong()
                val editor = getSharedPreferences(NoLeanWidgetProvider.PREFERENCES_NAME, MODE_PRIVATE).edit()
                    .putString("clean_time", cleanTime)
                    .putString("streak_days", streak)

                // Keep the legacy strings above so widgets created before this upgrade still
                // have content. New versions calculate elapsed time from this source of truth.
                if (lastDoseEpochMillis != null && lastDoseEpochMillis > 0L) {
                    editor.putLong(NoLeanWidgetProvider.KEY_LAST_DOSE_EPOCH_MILLIS, lastDoseEpochMillis)
                }
                editor.apply()

                val manager = AppWidgetManager.getInstance(this)
                val component = ComponentName(this, NoLeanWidgetProvider::class.java)
                NoLeanWidgetProvider().onUpdate(this, manager, manager.getAppWidgetIds(component))
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "no_lean/timezone").setMethodCallHandler { call, result ->
            if (call.method == "get") {
                result.success(java.util.TimeZone.getDefault().id)
            } else {
                result.notImplemented()
            }
        }
    }
}
