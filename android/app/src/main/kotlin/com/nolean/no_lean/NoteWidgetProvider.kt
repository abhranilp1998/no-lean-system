package com.nolean.no_lean

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.RemoteViews

/**
 * "Letter from future you", as a sealed envelope. The widget only knows
 * whether notes exist; their text stays in the app, which asks for the PIN
 * (when one is set) before showing it. Generic wording only.
 */
class NoteWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = updateAll(context)

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) =
        updateAll(context)

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_TICK) updateAll(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        WidgetPack.cancel(context, tick(context))
    }

    enum class Status { EMPTY, SEALED, READY }

    companion object {
        private const val ACTION_TICK = "com.nolean.no_lean.action.NOTE_TICK"

        private fun tick(context: Context) =
            WidgetPack.broadcast(context, NoteWidgetProvider::class.java, ACTION_TICK, 5)

        /** Ready from the window start until the result hold ends. */
        fun status(hasNotes: Boolean, phase: NightTimeline.Phase): Status = when {
            !hasNotes -> Status.EMPTY
            phase == NightTimeline.Phase.UPCOMING -> Status.SEALED
            else -> Status.READY
        }

        fun updateAll(context: Context) {
            val ids = WidgetPack.ids(context, NoteWidgetProvider::class.java)
            if (ids.isEmpty()) return
            val manager = AppWidgetManager.getInstance(context)
            val night = NightTimeline.compute(
                System.currentTimeMillis(),
                WidgetPack.riskStart(context),
                WidgetPack.riskEnd(context),
                0L,
            )
            val status = status(WidgetPack.prefs(context).getBoolean(WidgetPack.KEY_HAS_NOTES, false), night.phase)
            val start = night.hours.firstOrNull()?.label ?: ""
            ids.forEach { id ->
                manager.updateAppWidget(id, WidgetSizing.views(context, manager, id) { build(context, status, start, it) })
            }
            WidgetPack.schedule(context, tick(context), night.nextRefreshMillis)
        }

        /** Live envelope, for a stretched NO LEAN widget. */
        fun buildNow(context: Context, bucket: WidgetBucket): RemoteViews {
            val night = NightTimeline.compute(
                System.currentTimeMillis(),
                WidgetPack.riskStart(context),
                WidgetPack.riskEnd(context),
                0L,
            )
            val status = status(WidgetPack.prefs(context).getBoolean(WidgetPack.KEY_HAS_NOTES, false), night.phase)
            return build(context, status, night.hours.firstOrNull()?.label ?: "", bucket)
        }

        private fun build(context: Context, status: Status, start: String, bucket: WidgetBucket): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.note_widget)
            views.setTextViewText(
                R.id.note_status,
                when (status) {
                    Status.EMPTY -> context.getString(R.string.note_empty)
                    Status.SEALED -> context.getString(R.string.note_sealed, start)
                    Status.READY -> context.getString(R.string.note_ready)
                },
            )
            views.setInt(R.id.note_envelope, "setImageAlpha", if (status == Status.READY) 255 else 110)
            views.setOnClickPendingIntent(R.id.note_root, WidgetPack.openApp(context, MainActivity.WIDGET_ACTION_LETTER, 80))
            WidgetSizing.scaleText(views, bucket, R.id.note_label to 11f, R.id.note_status to 15f)
            return views
        }
    }
}
