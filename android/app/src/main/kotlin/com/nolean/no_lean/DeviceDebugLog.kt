package com.nolean.no_lean

import android.util.Log

/**
 * TEST BUILD ONLY (test/device-debug-all-open-prs-2026-11-27). Verbose logcat
 * lines for debugging the danger-zone app-block overlay on a real phone.
 * Filter: adb logcat -s NL.AppLockService NL.AppBlock NL.AppLockZone NL.AppBlockDart
 * Never logs coordinates; zone names only by id.
 */
object DeviceDebugLog {
    const val SERVICE = "NL.AppLockService"
    const val BLOCK = "NL.AppBlock"
    const val ZONE = "NL.AppLockZone"

    fun service(message: String) = safe { Log.i(SERVICE, message) }
    fun block(message: String) = safe { Log.i(BLOCK, message) }
    fun blockFail(message: String, error: Throwable? = null) = safe { Log.e(BLOCK, message, error) }
    fun zone(message: String) = safe { Log.i(ZONE, message) }

    private inline fun safe(body: () -> Unit) {
        try {
            body()
        } catch (_: Throwable) {
        }
    }
}
