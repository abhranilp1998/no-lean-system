package com.nolean.no_lean

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val feedbackHandler = Handler(Looper.getMainLooper())
    private var feedbackTone: ToneGenerator? = null
    private var widgetActionChannel: MethodChannel? = null
    private val actionPreferences by lazy { getSharedPreferences("no_lean_widget_actions", MODE_PRIVATE) }
    private val releaseFeedbackTone = Runnable {
        feedbackTone?.release()
        feedbackTone = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enqueueWidgetAction(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "no_lean/widget").setMethodCallHandler { call, result ->
            if (call.method == "update") {
                val cleanTime = call.argument<String>("cleanTime") ?: "0d 00h 00m"
                val streak = call.argument<String>("streak") ?: "0 DAYS"
                val isRiskWindow = call.argument<Boolean>("isRiskWindow") ?: false
                val hasPledgedToday = call.argument<Boolean>("hasPledgedToday") ?: false
                val lastDoseEpochMillis = call.argument<Number>("lastDoseEpochMillis")?.toLong()
                val editor = getSharedPreferences(NoLeanWidgetProvider.PREFERENCES_NAME, MODE_PRIVATE).edit()
                    .putString("clean_time", cleanTime)
                    .putString("streak_days", streak)
                    .putBoolean(NoLeanWidgetProvider.KEY_IS_RISK_WINDOW, isRiskWindow)
                    .putBoolean(NoLeanWidgetProvider.KEY_HAS_PLEDGED_TODAY, hasPledgedToday)

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
        widgetActionChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "no_lean/widget_actions",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "drainActions") {
                    val actions = readPendingActions()
                    if (actionPreferences.edit().remove("pending").commit()) {
                        result.success(actions)
                    } else {
                        result.error("ACTION_STORAGE", "Could not acknowledge widget action", null)
                    }
                } else {
                    result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "no_lean/feedback").setMethodCallHandler { call, result ->
            if (call.method != "play") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val effect = call.argument<String>("effect") ?: "neonPulse"
            result.success(playFeedbackTone(effect))
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        enqueueWidgetAction(intent)
    }

    private fun readPendingActions(): MutableList<String> {
        return try {
            val array = JSONArray(actionPreferences.getString("pending", "[]"))
            MutableList(array.length()) { array.getString(it) }
        } catch (_: Exception) { mutableListOf() }
    }

    private fun enqueueWidgetAction(intent: Intent?) {
        val action = widgetActionFrom(intent) ?: return
        val pending = readPendingActions()
        if (pending.lastOrNull() != action) pending.add(action)
        // Navigation requests only, never recovery events. Taps are acknowledged
        // after Dart has loaded history and subscribed to the action stream.
        if (actionPreferences.edit().putString("pending", JSONArray(pending.takeLast(20)).toString()).commit()) {
            intent?.removeExtra(EXTRA_WIDGET_ACTION)
            widgetActionChannel?.invokeMethod("actionsAvailable", null)
        }
    }

    private fun widgetActionFrom(intent: Intent?): String? {
        return when (val action = intent?.getStringExtra(EXTRA_WIDGET_ACTION)) {
            WIDGET_ACTION_SOS, WIDGET_ACTION_CRAVING, WIDGET_ACTION_RELAPSE -> action
            else -> null
        }
    }

    private fun playFeedbackTone(effect: String): Boolean {
        val toneAndDuration = when (effect) {
            "terminalTick" -> ToneGenerator.TONE_CDMA_PIP to 35
            "reactorPing" -> ToneGenerator.TONE_PROP_ACK to 95
            "neonPulse" -> ToneGenerator.TONE_PROP_BEEP to 60
            else -> return false
        }

        return try {
            feedbackHandler.removeCallbacks(releaseFeedbackTone)
            feedbackTone?.release()
            feedbackTone = ToneGenerator(AudioManager.STREAM_SYSTEM, 58).also {
                it.startTone(toneAndDuration.first, toneAndDuration.second)
            }
            feedbackHandler.postDelayed(
                releaseFeedbackTone,
                toneAndDuration.second.toLong() + 80L,
            )
            true
        } catch (_: RuntimeException) {
            feedbackTone?.release()
            feedbackTone = null
            false
        }
    }

    override fun onDestroy() {
        feedbackHandler.removeCallbacks(releaseFeedbackTone)
        feedbackTone?.release()
        feedbackTone = null
        widgetActionChannel?.setMethodCallHandler(null)
        widgetActionChannel = null
        super.onDestroy()
    }

    companion object {
        const val EXTRA_WIDGET_ACTION = "com.nolean.no_lean.extra.WIDGET_ACTION"
        const val WIDGET_ACTION_SOS = "sos"
        const val WIDGET_ACTION_CRAVING = "craving"
        const val WIDGET_ACTION_RELAPSE = "relapse"
    }
}
