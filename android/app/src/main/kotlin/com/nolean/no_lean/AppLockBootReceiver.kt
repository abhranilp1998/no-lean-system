package com.nolean.no_lean

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Restarts the app-lock service after a reboot or an app update. */
class AppLockBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            -> AppLockService.sync(context)
        }
    }
}
