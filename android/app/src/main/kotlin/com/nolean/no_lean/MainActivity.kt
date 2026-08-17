package com.nolean.no_lean

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val feedbackHandler = Handler(Looper.getMainLooper())
    private var feedbackTone: ToneGenerator? = null
    private val releaseFeedbackTone = Runnable {
        feedbackTone?.release()
        feedbackTone = null
    }

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "no_lean/feedback").setMethodCallHandler { call, result ->
            if (call.method != "play") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val effect = call.argument<String>("effect") ?: "neonPulse"
            result.success(playFeedbackTone(effect))
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
        super.onDestroy()
    }
}
