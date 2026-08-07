package com.nolean.no_lean

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "no_lean/widget").setMethodCallHandler { call, result ->
            if (call.method == "update") {
                val cleanTime = call.argument<String>("cleanTime") ?: "0d 00h 00m"
                val streak = call.argument<String>("streak") ?: "0 DAYS"
                getSharedPreferences("no_lean_widget", MODE_PRIVATE).edit()
                    .putString("clean_time", cleanTime)
                    .putString("streak_days", streak)
                    .apply()
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
