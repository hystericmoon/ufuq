package app.ufuq.desktop.usage

import app.ufuq.core.PeekEvent
import app.ufuq.desktop.island.AiUsageSample
import app.ufuq.desktop.island.EnglishIslandStrings
import java.time.Duration
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class UsageAlertsTest {
    private val now = Instant.parse("2026-11-26T12:00:00Z")
    private fun sample(f: Double, resets: Long = 3600) = AiUsageSample("Codex", f, Duration.ofSeconds(resets), "5h")
    private fun peeks(prev: List<AiUsageSample>, cur: List<AiUsageSample>) = UsageAlerts.peeks(prev, cur, now, EnglishIslandStrings)

    @Test fun tokenCountsNeverAlert() {
        fun claude(tokens: Long) = AiUsageSample("Claude", 0.0, Duration.ofHours(1), "5h", tokens = tokens)
        assertTrue(peeks(listOf(claude(1_000)), listOf(claude(900_000_000))).isEmpty())
    }

    @Test fun nothingOnTheFirstReading() = assertTrue(peeks(emptyList(), listOf(sample(0.99))).isEmpty())

    @Test fun crossingEightyIsANormalPeek() {
        val p = peeks(listOf(sample(0.79)), listOf(sample(0.81))).single()
        assertEquals(PeekEvent.Priority.NORMAL, p.priority)
        assertEquals("Codex 5h at 81%", p.title)
    }

    @Test fun crossingNinetyFiveIsCritical() {
        val p = peeks(listOf(sample(0.9)), listOf(sample(0.96))).single()
        assertEquals(PeekEvent.Priority.CRITICAL, p.priority)
    }

    @Test fun staleAboveTheLineDoesNotRepeat() = assertTrue(peeks(listOf(sample(0.85)), listOf(sample(0.86))).isEmpty())

    @Test fun aLaterResetIsAPeek() {
        val p = peeks(listOf(sample(0.9, resets = 60)), listOf(sample(0.01, resets = 18_000))).single()
        assertEquals("Codex 5h reset", p.title)
    }
}
