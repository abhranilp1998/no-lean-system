package com.nolean.no_lean

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.telecom.TelecomManager

/**
 * Apps that can never be locked, resolved on this device: the default
 * dialer, every home screen, system settings, apps handling emergency
 * dialling and map links, and NO LEAN itself. Added to the fixed list Dart
 * sends (`never_lockable.dart`).
 */
object AppLockProtected {
    @Volatile private var cached: Set<String>? = null
    @Volatile private var cachedAt = 0L

    fun packages(context: Context): Set<String> {
        val now = System.currentTimeMillis()
        cached?.let { if (now - cachedAt < 10 * 60 * 1000L) return it }
        val pm = context.packageManager
        val result = mutableSetOf(context.packageName, "android", "com.android.systemui")
        fun handlers(intent: Intent) {
            try {
                @Suppress("DEPRECATION")
                pm.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
                    .forEach { result.add(it.activityInfo.packageName) }
            } catch (_: Exception) {
            }
        }
        handlers(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME))
        handlers(Intent(Intent.ACTION_DIAL))
        handlers(Intent(Intent.ACTION_DIAL, Uri.parse("tel:112")))
        handlers(Intent(Intent.ACTION_VIEW, Uri.parse("geo:0,0?q=0,0")))
        handlers(Intent(Settings.ACTION_SETTINGS))
        try {
            val telecom = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
            telecom?.defaultDialerPackage?.let(result::add)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                telecom?.systemDialerPackage?.let(result::add)
            }
        } catch (_: Exception) {
        }
        cached = result
        cachedAt = now
        return result
    }

    fun isProtected(context: Context, packageName: String, config: AppLockConfig? = null): Boolean =
        packageName.isBlank() ||
            packageName.startsWith("com.nolean.no_lean") ||
            packages(context).contains(packageName) ||
            (config?.neverLockable?.contains(packageName) ?: false)
}
