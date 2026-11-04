package com.nolean.no_lean

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.util.SizeF
import android.util.TypedValue
import android.widget.RemoteViews

/**
 * Size buckets shared by every full-screen widget. The widgets have no
 * maximum size: they can be stretched to the whole screen, and each bucket
 * scales text and touch targets up so a big widget is filled, not padded.
 */
enum class WidgetBucket(val minWidthDp: Float, val minHeightDp: Float, val textScale: Float) {
    COMPACT(0f, 0f, 1f),
    FULL(150f, 200f, 1f),
    LARGE(220f, 380f, 1.45f),
    HUGE(280f, 560f, 2f),
    ;

    val isFull get() = this != COMPACT
}

object WidgetSizing {
    /** Pure, for tests and the pre-Android-12 fallback. */
    fun bucketFor(widthDp: Int, heightDp: Int): WidgetBucket =
        WidgetBucket.values().last { widthDp >= it.minWidthDp && heightDp >= it.minHeightDp }

    /**
     * Android 12+: one layout per bucket, the launcher picks by live size.
     * Older: the current size from the widget options (portrait uses the max
     * height and min width, as launchers report them).
     */
    fun views(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        build: (WidgetBucket) -> RemoteViews,
    ): RemoteViews =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            RemoteViews(WidgetBucket.values().associate { SizeF(maxOf(it.minWidthDp, 40f), maxOf(it.minHeightDp, 40f)) to build(it) })
        } else {
            build(currentBucket(context, manager, id))
        }

    fun currentBucket(context: Context, manager: AppWidgetManager, id: Int): WidgetBucket {
        val o = manager.getAppWidgetOptions(id)
        val portrait = context.resources.configuration.orientation != Configuration.ORIENTATION_LANDSCAPE
        val w = o.getInt(if (portrait) AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0)
        val h = o.getInt(if (portrait) AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        return bucketFor(w, h)
    }

    /** Scales the given text views (base sizes in sp) for the bucket. */
    fun scaleText(views: RemoteViews, bucket: WidgetBucket, vararg texts: Pair<Int, Float>) {
        if (bucket.textScale == 1f) return
        texts.forEach { (id, sp) -> views.setTextViewTextSize(id, TypedValue.COMPLEX_UNIT_SP, sp * bucket.textScale) }
    }
}
