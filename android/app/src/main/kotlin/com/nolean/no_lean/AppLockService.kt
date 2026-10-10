package com.nolean.no_lean

import android.Manifest
import android.app.AppOpsManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import org.json.JSONObject
import java.util.Calendar

/**
 * Lightweight foreground service that enforces the app lock.
 *
 * Every ~1 s while the screen is on (and the lock is active) it reads the
 * latest foreground app from UsageStatsManager events. When a locked app
 * comes to the front it brings NO LEAN's blocking screen over it.
 *
 * Fail-safe: no usage access, a broken config or any error means nothing
 * is blocked. The service stops itself when usage access is revoked; the
 * app shows a re-grant banner. It never consumes Home/Back and never draws
 * over other apps itself, so the user can always leave.
 */
class AppLockService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var config: AppLockConfig = AppLockConfig.DISABLED
    private var lastEventQuery = 0L
    private var foregroundPackage: String? = null
    private var lastBlockedPackage: String? = null
    private var lastBlockAt = 0L
    private var lastPermissionCheck = 0L
    private var lastZoneCheck = 0L
    private var insideZone: AppLockConfig.Zone? = null

    private val tick = object : Runnable {
        override fun run() {
            val delay = try {
                poll()
            } catch (_: Exception) {
                // Never crash-loop and never block on an error.
                5_000L
            }
            if (running) handler.postDelayed(this, delay)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        config = AppLockConfig.load(this)
        if (!config.armed || !hasUsageAccess(this)) {
            startInForeground()
            stopSelfSafely()
            return START_NOT_STICKY
        }
        startInForeground()
        handler.removeCallbacks(tick)
        lastEventQuery = System.currentTimeMillis() - 10_000L
        handler.post(tick)
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        handler.removeCallbacks(tick)
        super.onDestroy()
    }

    private fun stopSelfSafely() {
        running = false
        handler.removeCallbacks(tick)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    /** One poll. Returns the delay until the next one. */
    private fun poll(): Long {
        val now = System.currentTimeMillis()
        if (now - lastPermissionCheck > 10_000L) {
            lastPermissionCheck = now
            config = AppLockConfig.load(this)
            if (!config.armed || !hasUsageAccess(this)) {
                stopSelfSafely()
                return 60_000L
            }
        }
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!power.isInteractive) {
            lastEventQuery = now
            return 3_000L
        }
        if (config.lockInsideDangerZones && config.zones.isNotEmpty() && now - lastZoneCheck > 30_000L) {
            lastZoneCheck = now
            insideZone = currentZone()
        }
        val zoneActive = config.lockInsideDangerZones && insideZone != null
        val active = zoneActive || config.scheduleActive(Calendar.getInstance())
        updateForeground(now)
        if (!active) return if (config.lockInsideDangerZones) 2_000L else 5_000L
        val pkg = foregroundPackage ?: return 1_000L
        if (shouldBlock(pkg, now)) {
            if (pkg != lastBlockedPackage || now - lastBlockAt > 3_000L) {
                lastBlockedPackage = pkg
                lastBlockAt = now
                showBlock(pkg, if (zoneActive) insideZone else null)
            }
        }
        return 1_000L
    }

    private fun shouldBlock(pkg: String, now: Long): Boolean =
        config.packages.contains(pkg) &&
            !AppLockProtected.isProtected(this, pkg, config) &&
            !AppLockConfig.isGranted(this, pkg, now)

    private fun updateForeground(now: Long) {
        val usage = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = usage.queryEvents(lastEventQuery, now)
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            @Suppress("DEPRECATION")
            val resumed = event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND ||
                (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                    event.eventType == UsageEvents.Event.ACTIVITY_RESUMED)
            if (resumed) foregroundPackage = event.packageName
        }
        // Small overlap so an event at the boundary is not missed.
        lastEventQuery = now - 500L
    }

    private fun currentZone(): AppLockConfig.Zone? {
        val fine = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarse = checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!fine && !coarse) return null
        return try {
            val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            var best: Location? = null
            for (provider in listOf(LocationManager.PASSIVE_PROVIDER, LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)) {
                val location = try {
                    manager.getLastKnownLocation(provider)
                } catch (_: Exception) {
                    null
                } ?: continue
                if (best == null || location.time > best.time) best = location
            }
            val fix = best ?: return null
            // A stale fix is not evidence of where the user is now.
            if (System.currentTimeMillis() - fix.time > 10 * 60 * 1000L) return null
            AppLockConfig.zoneFor(config.zones, fix, insideZone?.id)
        } catch (_: SecurityException) {
            null
        }
    }

    private fun showBlock(pkg: String, zone: AppLockConfig.Zone?) {
        val request = JSONObject()
            .put("packageName", pkg)
            .put("label", config.labelFor(pkg))
            .put("cause", if (zone != null) "zone" else "schedule")
            .put("zoneName", zone?.name ?: "")
            .put("at", System.currentTimeMillis())
        AppLockConfig.enqueueBlock(this, request)
        val intent = Intent(this, MainActivity::class.java)
            .putExtra(MainActivity.EXTRA_APP_BLOCK, true)
            .addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
            )
        var started = false
        // Android 10+ only lets a background app open an activity when it
        // may display over other apps; without it, fall back to a prompt.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || Settings.canDrawOverlays(this)) {
            started = try {
                startActivity(intent)
                true
            } catch (_: Exception) {
                false
            }
        }
        if (!started) postBlockPrompt(intent)
    }

    private fun postBlockPrompt(intent: Intent) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannels(manager)
        val pending = PendingIntent.getActivity(
            this, BLOCK_NOTIFICATION_ID, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val title = if (config.hideSensitive) "NO LEAN" else "This app is locked"
        val text = if (config.hideSensitive) "Tap to continue" else "Tap for your options: I need this app, SOS, Go home"
        val notification = builder(BLOCK_CHANNEL)
            .setSmallIcon(R.mipmap.no_lean_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(pending)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setCategory(Notification.CATEGORY_REMINDER)
            .build()
        try {
            manager.notify(BLOCK_NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
        }
    }

    private fun startInForeground() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannels(manager)
        val open = PendingIntent.getActivity(
            this, SERVICE_NOTIFICATION_ID,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // Neutral on purpose: never names apps, zones or recovery.
        val notification = builder(SERVICE_CHANNEL)
            .setSmallIcon(R.mipmap.no_lean_launcher)
            .setContentTitle(if (config.hideSensitive) "Service running" else "NO LEAN")
            .setContentText(if (config.hideSensitive) "Active" else "Focus guard on")
            .setContentIntent(open)
            .setOngoing(true)
            .setShowWhen(false)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(SERVICE_NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(SERVICE_NOTIFICATION_ID, notification)
        }
    }

    private fun builder(channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

    private fun ensureChannels(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        manager.createNotificationChannel(
            NotificationChannel(SERVICE_CHANNEL, "Focus guard", NotificationManager.IMPORTANCE_MIN).apply {
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(BLOCK_CHANNEL, "Locked app prompt", NotificationManager.IMPORTANCE_HIGH).apply {
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            },
        )
    }

    companion object {
        private const val SERVICE_CHANNEL = "app_lock_service_v1"
        private const val BLOCK_CHANNEL = "app_lock_block_v1"
        private const val SERVICE_NOTIFICATION_ID = 900
        private const val BLOCK_NOTIFICATION_ID = 901

        @Volatile var running = false
            private set

        @Volatile private var startRequestedAt = 0L

        /** Running, or asked to start a moment ago (start is asynchronous). */
        val runningOrStarting: Boolean
            get() = running || System.currentTimeMillis() - startRequestedAt < 5_000L

        fun hasUsageAccess(context: Context): Boolean = try {
            val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
            } else {
                @Suppress("DEPRECATION")
                ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
            }
            if (mode == AppOpsManager.MODE_DEFAULT) {
                context.checkCallingOrSelfPermission(Manifest.permission.PACKAGE_USAGE_STATS) == PackageManager.PERMISSION_GRANTED
            } else {
                mode == AppOpsManager.MODE_ALLOWED
            }
        } catch (_: Exception) {
            false
        }

        /** Starts or stops the service to match the saved config. */
        fun sync(context: Context): Boolean {
            val config = AppLockConfig.load(context)
            val intent = Intent(context, AppLockService::class.java)
            if (!config.armed || !hasUsageAccess(context)) {
                if (running) context.stopService(intent)
                return false
            }
            startRequestedAt = System.currentTimeMillis()
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (_: Exception) {
                // e.g. background start not allowed right now; the app retries on resume.
                startRequestedAt = 0L
                false
            }
        }
    }
}
