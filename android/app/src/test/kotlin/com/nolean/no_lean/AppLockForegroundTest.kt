package com.nolean.no_lean

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AppLockForegroundTest {
    private val now = 100_000_000L

    @Test fun freshInstanceLooksBackHours() {
        val from = AppLockForeground.startQueryFrom(now, knowsForeground = false)
        assertEquals(now - AppLockForeground.RESTART_LOOKBACK_MS, from)
        // An app brought to the front 30 minutes before the restart is inside the window.
        assertTrue(now - 30L * 60L * 1000L > from)
    }

    @Test fun knownForegroundKeepsShortWindow() =
        assertEquals(now - 10_000L, AppLockForeground.startQueryFrom(now, knowsForeground = true))
}
