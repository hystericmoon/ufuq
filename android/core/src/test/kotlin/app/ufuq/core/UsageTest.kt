package app.ufuq.core

import org.junit.Test
import java.time.Duration
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class UsageThresholdTest {
    private val t = UsageThresholds.DEFAULT
    private val t0 = T0

    @Test
    fun levels() {
        assertEquals(UsageLevel.NORMAL, t.level(0.0))
        assertEquals(UsageLevel.NORMAL, t.level(0.7999))
        assertEquals(UsageLevel.WARNING, t.level(0.80))
        assertEquals(UsageLevel.WARNING, t.level(0.9499))
        assertEquals(UsageLevel.CRITICAL, t.level(0.95))
        assertEquals(UsageLevel.CRITICAL, t.level(1.0))
    }

    @Test
    fun `out of range is clamped`() {
        assertEquals(UsageLevel.CRITICAL, t.level(1.7))
        assertEquals(UsageLevel.NORMAL, t.level(-0.2))
        assertEquals(UsageLevel.NORMAL, t.level(Double.NaN))
    }

    private fun snap(f: Double, reset: Long? = null) = UsageSnapshot(f, t0, reset?.let { t0.plusSeconds(it) })

    @Test
    fun `alerts fire once on crossing up`() {
        assertNull(t.alert(null, snap(0.9)))
        assertNull(t.alert(snap(0.5), snap(0.79)))
        assertEquals(UsageAlert.REACHED_WARNING, t.alert(snap(0.79), snap(0.80)))
        assertNull(t.alert(snap(0.81), snap(0.90)))
        assertEquals(UsageAlert.REACHED_CRITICAL, t.alert(snap(0.90), snap(0.95)))
        assertEquals(UsageAlert.REACHED_CRITICAL, t.alert(snap(0.5), snap(0.99)), "skipping amber goes straight to red")
        assertNull(t.alert(snap(0.96), snap(0.99)))
        assertNull(t.alert(snap(0.96), snap(0.85)), "falling never alerts")
    }

    @Test
    fun `reset alert`() {
        assertEquals(UsageAlert.RESET, t.alert(snap(0.9, reset = 100), snap(0.0, reset = 18_100)))
        assertNull(t.alert(snap(0.1, reset = 100), snap(0.2, reset = 100)))
    }

    @Test
    fun `critical alert jumps peek queue`() {
        assertEquals(PeekEvent.Priority.CRITICAL, UsageAlert.REACHED_CRITICAL.peekPriority)
        assertEquals(PeekEvent.Priority.NORMAL, UsageAlert.REACHED_WARNING.peekPriority)
        assertEquals(PeekEvent.Priority.NORMAL, UsageAlert.RESET.peekPriority)
    }
}

class BurnRateTest {
    private val t0 = T0

    private fun s(minutes: Double, f: Double, resetIn: Double? = null) = UsageSnapshot(
        f, t0 + minutes * 60, resetIn?.let { t0 + it * 60 },
    )

    private fun steps(from: Int, through: Int, by: Int) = (from..through step by).map { it.toDouble() }

    @Test
    fun `linear burn`() {
        // 1% per minute; at 40% after 30 min -> 60 min to the limit.
        val samples = steps(0, 30, 5).map { s(it, 0.10 + it / 100) }
        val e = assertNotNull(BurnRate.estimate(samples))
        assertEquals(0.60, e.fractionPerHour, 1e-9)
        assertEquals(60 * 60.0, assertNotNull(e.timeToLimit).toNanos() / 1e9, 1e-6)
        assertTrue(e.hitsLimitBeforeReset)
    }

    @Test
    fun `reset after limit means no hit`() {
        val samples = listOf(s(0.0, 0.10, resetIn = 60.0), s(30.0, 0.40, resetIn = 60.0))
        assertFalse(assertNotNull(BurnRate.estimate(samples)).hitsLimitBeforeReset, "limit at 90 min, reset at 60 min")
        val early = listOf(s(0.0, 0.10, resetIn = 120.0), s(30.0, 0.40, resetIn = 120.0))
        assertTrue(assertNotNull(BurnRate.estimate(early)).hitsLimitBeforeReset)
    }

    @Test
    fun `flat usage has no time to limit`() {
        val e = assertNotNull(BurnRate.estimate(listOf(s(0.0, 0.5), s(10.0, 0.5), s(20.0, 0.5))))
        assertEquals(0.0, e.fractionPerHour)
        assertNull(e.timeToLimit)
        assertFalse(e.hitsLimitBeforeReset)
    }

    @Test
    fun `needs two samples and minimum span`() {
        assertNull(BurnRate.estimate(emptyList()))
        assertNull(BurnRate.estimate(listOf(s(0.0, 0.1))))
        assertNull(BurnRate.estimate(listOf(s(0.0, 0.1), s(4.0, 0.2))), "under 5 min span")
        assertNotNull(BurnRate.estimate(listOf(s(0.0, 0.1), s(5.0, 0.2))))
    }

    @Test
    fun `ignores samples before reset`() {
        // Old window climbed fast to 90%, then reset; new window climbs 0.5% per minute.
        val samples = listOf(s(0.0, 0.50), s(10.0, 0.90), s(20.0, 0.00), s(30.0, 0.05), s(40.0, 0.10))
        assertEquals(0.30, assertNotNull(BurnRate.estimate(samples)).fractionPerHour, 1e-9)
    }

    @Test
    fun `only recent pace counts`() {
        // Slow for 2 h, then 2% per minute in the last hour.
        val samples = steps(0, 120, 10).map { s(it, it / 1200) } +
            steps(130, 180, 10).map { s(it, 0.10 + (it - 120) / 50) }
        assertTrue(assertNotNull(BurnRate.estimate(samples)).fractionPerHour > 1.0)
    }

    @Test
    fun `unsorted input and already at limit`() {
        val e = assertNotNull(BurnRate.estimate(listOf(s(10.0, 1.0), s(0.0, 0.9))))
        assertEquals(Duration.ZERO, e.timeToLimit)
    }
}

class UsageModelTest {
    private fun reading(kind: UsageWindowKind, f: Double) =
        UsageWindowReading(kind, UsageSnapshot(f, java.time.Instant.EPOCH))

    @Test
    fun `worst fraction`() {
        val readings = listOf(
            reading(UsageWindowKind.Session5h, 0.4), reading(UsageWindowKind.Weekly, 0.874),
            reading(UsageWindowKind.ModelGroup("Gemini"), 0.1),
        )
        assertEquals(0.874, UsageSummary.worstFraction(readings))
        assertEquals(UsageWindowKind.Weekly, UsageSummary.worst(readings)?.kind)
        assertEquals(87, UsageSummary.worstPercent(readings))
        assertNull(UsageSummary.worstFraction(emptyList()))
        assertEquals(1.0, UsageSummary.worstFraction(listOf(reading(UsageWindowKind.Weekly, 1.7))))
        assertNull(UsageSummary.worst(listOf(reading(UsageWindowKind.Weekly, Double.NaN))))
    }

    @Test
    fun `usage result status`() {
        val ok: UsageResult<Int> = UsageResult.Available(3)
        assertEquals(3, ok.valueOrNull)
        assertEquals(ModuleStatus.Ok, ok.status)
        val bad: UsageResult<Int> = UsageResult.Unavailable("gone")
        assertNull(bad.valueOrNull)
        assertEquals(ModuleStatus.Unavailable("gone"), bad.status)
    }
}
