package com.nolean.no_lean

import android.appwidget.AppWidgetManager
import android.content.Context
import android.widget.RemoteViews

/**
 * The configurable full-screen view of the "NO LEAN Full" widget (one
 * app-wide choice, overridable per placed widget in the app's Widgets page).
 * Classic 4x2/4x3 widgets keep their classic look at every size unless the
 * user picks a view for that particular widget in the app.
 */
object StretchedViews {
    const val KEY_DEFAULT = "stretched_view"
    const val CLASSIC = "classic"

    /** Stored names. Must match Dart nativeName. */
    val CHOICES = listOf("auto", "garden", "shield", "night", "wave", "map", "note")

    enum class View { GARDEN, NIGHT, SHIELD, WAVE, MAP, NOTE }

    fun keyFor(id: Int) = "stretched_view_$id"

    /** Per-widget override, or null (classic widgets stay classic). */
    fun overrideFor(context: Context, id: Int): String? =
        WidgetPack.prefs(context).getString(keyFor(id), null)?.takeIf { it in CHOICES }

    /** Full widget: per-widget override, else the app-wide choice, else auto. */
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

    fun build(context: Context, choice: String, bucket: WidgetBucket, privacy: Boolean): RemoteViews {
        val now = System.currentTimeMillis()
        val night = NightTimeline.compute(now, WidgetPack.riskStart(context), WidgetPack.riskEnd(context), 0L)
        return when (resolve(choice, night.phase, now, night.windowStartMillis, privacy)) {
            View.SHIELD -> EveningShieldWidgetProvider.buildNow(context, bucket)
            View.NIGHT -> NightTimelineWidgetProvider.buildNow(context, bucket)
            View.GARDEN -> GardenWidgetProvider.build(context, bucket)
            View.WAVE -> wave(context, bucket)
            View.MAP -> RadarWidgetProvider.build(context, bucket)
            View.NOTE -> NoteWidgetProvider.buildNow(context, bucket)
        }
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
            "small" to NoLeanSmallWidgetProvider::class.java,
            "medium" to NoLeanWidgetProvider::class.java,
            "large" to NoLeanLargeWidgetProvider::class.java,
            "full" to NoLeanFullWidgetProvider::class.java,
            "tonight" to NightTimelineWidgetProvider::class.java,
            "garden" to GardenWidgetProvider::class.java,
            "evening" to EveningShieldWidgetProvider::class.java,
            "map" to RadarWidgetProvider::class.java,
            "note" to NoteWidgetProvider::class.java,
        ).flatMap { (kind, type) ->
            WidgetPack.ids(context, type).map { mapOf("id" to it, "kind" to kind, "view" to prefs.getString(keyFor(it), null)) }
        }
    }

    fun setOverride(context: Context, id: Int, choice: String?) {
        val edit = WidgetPack.prefs(context).edit()
        if (choice == null || (choice !in CHOICES && choice != CLASSIC)) edit.remove(keyFor(id)) else edit.putString(keyFor(id), choice)
        edit.apply()
    }

    /** Which picker entries exist, for "Add to home screen". */
    fun providerFor(kind: String): Class<*>? = when (kind) {
        "small" -> NoLeanSmallWidgetProvider::class.java
        "medium" -> NoLeanWidgetProvider::class.java
        "large" -> NoLeanLargeWidgetProvider::class.java
        "full" -> NoLeanFullWidgetProvider::class.java
        else -> null
    }
}
