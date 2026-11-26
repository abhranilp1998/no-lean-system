package com.nolean.no_lean

/** Pure helpers for how far back [AppLockService] reads usage events. */
object AppLockForeground {
    /** Normal (re)start lookback while the service already knows the foreground app. */
    const val SHORT_LOOKBACK_MS = 10_000L

    /**
     * A fresh service instance (first start or a restart after the process
     * died) has no idea which app is in front. Read further back so an app
     * opened before the restart is caught on the first poll instead of only
     * after the next app switch.
     */
    const val RESTART_LOOKBACK_MS = 6L * 60L * 60L * 1000L

    fun startQueryFrom(now: Long, knowsForeground: Boolean): Long =
        now - if (knowsForeground) SHORT_LOOKBACK_MS else RESTART_LOOKBACK_MS
}
