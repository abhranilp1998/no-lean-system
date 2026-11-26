package com.nolean.no_lean

import android.app.Notification

/**
 * Visible wording for native notifications (app-lock health, the persistent
 * service notice, and the locked-app prompt) when "Private notifications"
 * is on. Titles, bodies, tickers and channel names must stay free of
 * recovery language; the Dart catalogue in notification_copy.dart is the
 * other half of this list.
 */
object PrivateNotifications {
    const val HEALTH_CHANNEL = "app_lock_health_v1"
    const val SERVICE_CHANNEL = "app_lock_service_v1"
    const val BLOCK_CHANNEL = "app_lock_block_v1"

    const val REMINDER = "Reminder"
    const val TAP_TO_CHECK = "Tap to check"
    const val TAP_TO_CONTINUE = "Tap to continue"

    data class Copy(
        val source: String,
        val channelId: String,
        val channelName: String,
        val title: String,
        val body: String,
        val ticker: String,
        val visibility: Int,
    ) {
        fun visibleText(): String = listOf(channelName, title, body, ticker).joinToString("\n")
    }

    fun visibility(hideSensitive: Boolean): Int =
        if (hideSensitive) Notification.VISIBILITY_PUBLIC else Notification.VISIBILITY_PRIVATE

    fun healthChannelName(hideSensitive: Boolean): String =
        if (hideSensitive) "Status" else "Shield status"

    fun serviceChannelName(hideSensitive: Boolean): String =
        if (hideSensitive) "Service" else "Focus guard"

    fun blockChannelName(hideSensitive: Boolean): String =
        if (hideSensitive) "Prompt" else "Locked app prompt"

    fun health(hideSensitive: Boolean, issue: String): Copy {
        val body = if (hideSensitive) TAP_TO_CHECK else when (issue) {
            "usage_access" -> "Usage access was turned off. Nothing is locked. Tap to fix."
            "overlay" -> "\"Display over other apps\" is off. Locked apps only get a notification. Tap to fix."
            else -> "The lock stopped running. Nothing is locked. Tap to restart."
        }
        val title = if (hideSensitive) REMINDER else "Shield OFF"
        return Copy(
            source = "appLockHealth",
            channelId = HEALTH_CHANNEL,
            channelName = healthChannelName(hideSensitive),
            title = title,
            body = body,
            ticker = title,
            visibility = visibility(hideSensitive),
        )
    }

    fun service(hideSensitive: Boolean): Copy {
        val title = if (hideSensitive) "Service running" else "NO LEAN"
        val body = if (hideSensitive) "Active" else "Focus guard on"
        return Copy(
            source = "appLockService",
            channelId = SERVICE_CHANNEL,
            channelName = serviceChannelName(hideSensitive),
            title = title,
            body = body,
            ticker = title,
            visibility = visibility(hideSensitive),
        )
    }

    fun block(hideSensitive: Boolean): Copy {
        val title = if (hideSensitive) REMINDER else "This app is locked"
        val body = if (hideSensitive) TAP_TO_CONTINUE else "Tap for your options: I need this app, SOS, Go home"
        return Copy(
            source = "appLockBlock",
            channelId = BLOCK_CHANNEL,
            channelName = blockChannelName(hideSensitive),
            title = title,
            body = body,
            ticker = title,
            visibility = visibility(hideSensitive),
        )
    }

    /** Every native notification, for tests that assert private wording. */
    fun every(hideSensitive: Boolean): List<Copy> = listOf(
        health(hideSensitive, "usage_access"),
        health(hideSensitive, "overlay"),
        health(hideSensitive, "stale"),
        service(hideSensitive),
        block(hideSensitive),
    )

    val SENSITIVE = Regex(
        "\\b(?:lean|codeine|benzo|craving|relapse|clean|place|places|sober|addict|recovery|danger|risk|drug|urge|sos)s?\\b",
        RegexOption.IGNORE_CASE,
    )
}
