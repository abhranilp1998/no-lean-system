package com.nolean.no_lean

import android.app.Notification
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PrivateNotificationsTest {
    @Test
    fun privateCopyHasNoSensitiveWords() {
        for (copy in PrivateNotifications.every(true)) {
            assertEquals(Notification.VISIBILITY_PUBLIC, copy.visibility)
            assertEquals(copy.title, copy.ticker)
            assertFalse(
                "${copy.source} leaked a sensitive word in:\n${copy.visibleText()}",
                PrivateNotifications.SENSITIVE.containsMatchIn(copy.visibleText()),
            )
        }
        // The three native sources the Dart catalogue names.
        assertEquals(
            setOf("appLockHealth", "appLockService", "appLockBlock"),
            PrivateNotifications.every(true).map { it.source }.toSet(),
        )
    }

    @Test
    fun publicCopyStillNamesTheSensitiveBitsSoThePrivateTestIsReal() {
        val text = PrivateNotifications.every(false).joinToString("\n") { it.visibleText() }
        assertTrue(text.contains("NO LEAN"))
        assertTrue(text.contains("SOS") || text.contains("Shield"))
        assertTrue(PrivateNotifications.every(false).all { it.visibility == Notification.VISIBILITY_PRIVATE })
    }

    @Test
    fun healthIssuesAllGoNeutral() {
        for (issue in listOf("usage_access", "overlay", "stale")) {
            val copy = PrivateNotifications.health(true, issue)
            assertEquals("Reminder", copy.title)
            assertEquals("Tap to check", copy.body)
            assertEquals("Status", copy.channelName)
        }
    }
}
