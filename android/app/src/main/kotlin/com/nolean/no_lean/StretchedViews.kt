package com.nolean.no_lean

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * The configurable full-screen view of a stretched NO LEAN widget (and of
 * the "NO LEAN Full" widget). The choice comes from the app (one default for
 * every widget) and can be overridden per placed widget from the app or by
 * tapping the small cycle button on the widget itself.
 */
object StretchedViews {
    const val KEY_DEFAULT = "stretched_view"
    const val ACTION_CYCLE = "com.nolean.no_lean.action.STRETCHED_CYCLE"
    const val EXTRA_ID = "stretched_widget_id"

    /** Stored names, in tap-to-cycle order. Must match Dart nativeName. */
    val CHOICES = listOf("auto", "garden", "shield", "night", "wave", "map", "note")

    enum class View { GARDEN, NIGHT, SHIELD, WAVE, MAP, NOTE }

    fun keyFor(id: Int) = "stretched_view_$id"

    fun next(current: String?): String {
        val i = CHOICES.indexOf(current ?: "auto")
        return CHOICES[(if (i < 0) 0 else i + 1) % CHOICES.size]
    }

    /** Per-widget override, else the app-wide choice, else auto. */
    fun choiceFor(context: Context, id: Int): String {
        val prefs = WidgetPack.prefs(context)
        return prefs.getString(keyFor(id), null) ?: prefs.getString(KEY_DEFAULT, "auto") ?: "auto"
    }

    /** Pure. Privacy mode always forces the neutral timeline. */
    fun resolve(
        choice: String?,
        phase: NightTimeline.Phase,
        nowMillis: Long,
        windowStartMillis: Long,
        privacy: Boolean,
    ): View = when {
        privacy -> View.NIGHT
        choice == "garden" -> View.GARDEN
        choice == "shield" -> View.SHIELD
        choice == "night" -> View.NIGHT
        choice == "wave" -> View.WAVE
        choice == "map" -> View.MAP
        choice == "note" -> View.NOTE
        else -> when (WidgetPack.stretchedView(phase, nowMillis, windowStartMillis, false)) {
            WidgetPack.Stretched.SHIELD -> View.SHIELD
            WidgetPack.Stretched.NIGHT -> View.NIGHT
            WidgetPack.Stretched.GARDEN -> View.GARDEN
        }
    }

    fun build(context: Context, id: Int, bucket: WidgetBucket, privacy: Boolean, receiver: Class<*>): RemoteViews {
        val now = System.currentTimeMillis()
        val night = NightTimeline.compute(now, WidgetPack.riskStart(context), WidgetPack.riskEnd(context), 0L)
        val inner = when (resolve(choiceFor(context, id), night.phase, now, night.windowStartMillis, privacy)) {
            View.SHIELD -> EveningShieldWidgetProvider.buildNow(context, bucket)
            View.NIGHT -> NightTimelineWidgetProvider.buildNow(context, bucket)
            View.GARDEN -> GardenWidgetProvider.build(context, bucket)
            View.WAVE -> wave(context, bucket)
            View.MAP -> RadarWidgetProvider.build(context, bucket)
            View.NOTE -> NoteWidgetProvider.buildNow(context, bucket)
        }
        val host = RemoteViews(context.packageName, R.layout.stretched_host)
        host.removeAllViews(R.id.stretched_content)
        host.addView(R.id.stretched_content, inner)
        val cycle = Intent(context, receiver).apply {
            action = ACTION_CYCLE
            putExtra(EXTRA_ID, id)
        }
        host.setOnClickPendingIntent(
            R.id.stretched_cycle,
            PendingIntent.getBroadcast(
                context,
                10_000 + id,
                cycle,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
        return host
    }

    /** Handles the cycle tap: stores a per-widget override and redraws. */
    fun handleCycle(context: Context, intent: Intent): Boolean {
        if (intent.action != ACTION_CYCLE) return false
        val id = intent.getIntExtra(EXTRA_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        // Only our own placed widgets (the receivers are exported).
        if (placed(context).none { it["id"] == id }) return true
        WidgetPack.prefs(context).edit().putString(keyFor(id), next(choiceFor(context, id))).apply()
        NoLeanWidgetProvider.updateAllWidgets(context)
        return true
    }

    /** Static wave; tapping opens the animated one in the app. */
    private fun wave(context: Context, bucket: WidgetBucket): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.wave_widget)
        views.setOnClickPendingIntent(R.id.wave_root, WidgetPack.openApp(context, MainActivity.WIDGET_ACTION_WAVE, 90))
        WidgetSizing.scaleText(views, bucket, R.id.wave_widget_title to 18f, R.id.wave_widget_hint to 12f)
        return views
    }

    /** Placed stretchable widgets for the app's settings screen. */
    fun placed(context: Context): List<Map<String, Any?>> {
        val prefs = WidgetPack.prefs(context)
        return listOf(
            "medium" to NoLeanWidgetProvider::class.java,
            "large" to NoLeanLargeWidgetProvider::class.java,
            "full" to NoLeanFullWidgetProvider::class.java,
        ).flatMap { (kind, type) ->
            WidgetPack.ids(context, type).map { mapOf("id" to it, "kind" to kind, "view" to prefs.getString(keyFor(it), null)) }
        }
    }

    fun setOverride(context: Context, id: Int, choice: String?) {
        val edit = WidgetPack.prefs(context).edit()
        if (choice == null || choice !in CHOICES) edit.remove(keyFor(id)) else edit.putString(keyFor(id), choice)
        edit.apply()
    }
}
