package com.nolean.no_lean

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AppLockHealthTest {
    private val now = 10_000_000L

    @Test fun notArmedIsNeverAProblem() =
        assertNull(AppLockHealth.problem(false, false, false, 0L, now))

    @Test fun healthyWhenFreshHeartbeat() =
        assertNull(AppLockHealth.problem(true, true, true, now - 30_000L, now))

    @Test fun staleHeartbeat() =
        assertEquals("stale", AppLockHealth.problem(true, true, true, now - AppLockHealth.STALE_AFTER_MS - 1, now))

    @Test fun neverBeat() = assertEquals("stale", AppLockHealth.problem(true, true, true, 0L, now))

    @Test fun usageAccessWins() = assertEquals("usage_access", AppLockHealth.problem(true, false, false, now, now))

    @Test fun overlayLost() = assertEquals("overlay", AppLockHealth.problem(true, true, false, now, now))
}
