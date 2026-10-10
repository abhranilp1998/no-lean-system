package com.nolean.no_lean

import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** `no_lean/app_lock`: the Dart `MethodChannelAppLockGateway`. */
class AppLockChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "no_lean/app_lock")

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(status())
                    "openUsageAccessSettings" -> result.success(openUsageAccess())
                    "openOverlaySettings" -> result.success(openOverlay())
                    "installedApps" -> result.success(installedApps())
                    "apply" -> {
                        val json = call.arguments as? String
                        if (json == null) {
                            result.success(false)
                        } else {
                            AppLockConfig.save(activity, json)
                            result.success(AppLockService.sync(activity))
                        }
                    }
                    "disable" -> {
                        AppLockConfig.disable(activity)
                        AppLockService.sync(activity)
                        result.success(true)
                    }
                    "grantTemporaryUnlock" -> {
                        val pkg = call.argument<String>("packageName")
                        val millis = call.argument<Number>("millis")?.toLong() ?: 0L
                        if (pkg.isNullOrBlank() || millis <= 0L) {
                            result.success(false)
                        } else {
                            AppLockConfig.grant(activity, pkg, millis)
                            result.success(openApp(pkg))
                        }
                    }
                    "goHome" -> {
                        activity.startActivity(
                            Intent(Intent.ACTION_MAIN)
                                .addCategory(Intent.CATEGORY_HOME)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        result.success(true)
                    }
                    "drainBlocks" -> result.success(AppLockConfig.drainBlocks(activity))
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("APP_LOCK", error.message, null)
            }
        }
    }

    fun notifyBlocksAvailable() {
        channel.invokeMethod("blocksAvailable", null)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    private fun status(): Map<String, Any> {
        val notifications = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            (activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()
        } else {
            true
        }
        return mapOf(
            "usageAccess" to AppLockService.hasUsageAccess(activity),
            "overlay" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(activity)),
            "serviceRunning" to AppLockService.runningOrStarting,
            "notifications" to notifications,
        )
    }

    private fun openUsageAccess(): Boolean {
        val withPackage = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, Uri.parse("package:${activity.packageName}"))
        return start(withPackage) || start(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
    }

    private fun openOverlay(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return start(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${activity.packageName}"))) ||
            start(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION))
    }

    private fun start(intent: Intent): Boolean = try {
        activity.startActivity(intent)
        true
    } catch (_: Exception) {
        false
    }

    private fun openApp(pkg: String): Boolean {
        val launch = activity.packageManager.getLaunchIntentForPackage(pkg) ?: return false
        return start(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun installedApps(): List<Map<String, Any>> {
        val pm = activity.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        val activities = pm.queryIntentActivities(intent, PackageManager.MATCH_ALL)
        val config = AppLockConfig.load(activity)
        return activities
            .map { it.activityInfo }
            .distinctBy { it.packageName }
            .map { info ->
                mapOf(
                    "packageName" to info.packageName,
                    "label" to (info.loadLabel(pm)?.toString() ?: info.packageName),
                    "neverLockable" to AppLockProtected.isProtected(activity, info.packageName, config),
                )
            }
    }
}
