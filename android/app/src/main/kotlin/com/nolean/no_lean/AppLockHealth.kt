package com.nolean.no_lean

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Lock health (plan P0-1). The service writes a heartbeat on every poll; a
 * WorkManager watchdog and the app read it. When the lock is armed but the
 * heartbeat is stale, or Usage access / overlay is lost, a persistent
 * "Shield OFF" alert is shown instead of failing silently.
 */
object AppLockHealth {
    private const val KEY_HEARTBEAT = "heartbeat_at"
    private const val KEY_STOP_REASON = "stop_reason"
    private const val CHANNEL = "app_lock_health_v1"
    const val ALERT_ID = 902
    private const val WORK_NAME = "no_lean_lock_watchdog"

    /** A heartbeat older than this means the lock is not enforcing. */
    const val STALE_AFTER_MS = 2 * 60 * 1000L

    fun beat(context: Context, now: Long = System.currentTimeMillis()) {
        AppLockConfig.prefs(context).edit().putLong(KEY_HEARTBEAT, now).remove(KEY_STOP_REASON).apply()
    }

    fun heartbeatAt(context: Context): Long = AppLockConfig.prefs(context).getLong(KEY_HEARTBEAT, 0L)

    fun stopReason(context: Context): String? = AppLockConfig.prefs(context).getString(KEY_STOP_REASON, null)

    fun recordStop(context: Context, reason: String) {
        AppLockConfig.prefs(context).edit().putString(KEY_STOP_REASON, reason).apply()
    }

    /** Pure: why the shield is off, or null when healthy / not armed. */
    fun problem(
        armed: Boolean,
        usageAccess: Boolean,
        overlay: Boolean,
        heartbeatAt: Long,
        now: Long,
    ): String? = when {
        !armed -> null
        !usageAccess -> "usage_access"
        !overlay -> "overlay"
        heartbeatAt <= 0L || now - heartbeatAt > STALE_AFTER_MS -> "stale"
        else -> null
    }

    fun canDrawOverlays(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

    /** Checks health, tries a restart, and shows or clears the alert. */
    fun check(context: Context, now: Long = System.currentTimeMillis()) {
        val config = AppLockConfig.load(context)
        var issue = problem(
            config.armed, AppLockService.hasUsageAccess(context), canDrawOverlays(context),
            heartbeatAt(context), now,
        )
        if (issue == "stale") {
            AppLockService.sync(context)
            // A restart that is only requested still counts as off until it beats.
        }
        if (issue == null) clearAlert(context) else showAlert(context, issue, config.hideSensitive)
    }

    fun showAlert(context: Context, issue: String, hideSensitive: Boolean) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Shield status", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    setShowBadge(true)
                    lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                },
            )
        }
        val open = PendingIntent.getActivity(
            context, ALERT_ID,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val text = if (hideSensitive) {
            "Tap to check"
        } else {
            when (issue) {
                "usage_access" -> "Usage access was turned off. Nothing is locked. Tap to fix."
                "overlay" -> "\"Display over other apps\" is off. Locked apps only get a notification. Tap to fix."
                else -> "The lock stopped running. Nothing is locked. Tap to restart."
            }
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.no_lean_launcher)
            .setContentTitle(if (hideSensitive) "NO LEAN" else "Shield OFF")
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build()
        try {
            manager.notify(ALERT_ID, notification)
        } catch (_: SecurityException) {
        }
    }

    fun clearAlert(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(ALERT_ID)
    }

    /** Schedules (or cancels) the 15-minute watchdog to match the config. */
    fun scheduleWatchdog(context: Context) {
        try {
            val work = WorkManager.getInstance(context.applicationContext)
            if (AppLockConfig.load(context).armed) {
                val request = PeriodicWorkRequestBuilder<Watchdog>(15, TimeUnit.MINUTES).build()
                work.enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request)
            } else {
                work.cancelUniqueWork(WORK_NAME)
                clearAlert(context)
            }
        } catch (_: Exception) {
            // WorkManager unavailable: the in-app banner still reports health.
        }
    }

    class Watchdog(context: Context, params: WorkerParameters) : Worker(context, params) {
        override fun doWork(): Result {
            try {
                check(applicationContext)
            } catch (_: Exception) {
            }
            return Result.success()
        }
    }
}
