package app.ufuq.core

import org.junit.Test
import java.time.Duration
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ActivityArbiterTest {
    private val t0 = T0

    private fun act(
        id: String,
        source: ActivitySource,
        alert: Boolean = false,
        deadline: Instant? = null,
        usage: Double? = null,
    ) = LiveActivity(id, id, source, id, id, alert, deadline, usage)

    // Priority

    @Test
    fun `priority order matches spec`() {
        val arbiter = ActivityArbiter()
        assertEquals(WingPriority.ALERT, arbiter.priority(act("a", ActivitySource.AGENT, alert = true), t0))
        assertEquals(WingPriority.PRAYER_SOON, arbiter.priority(act("p", ActivitySource.PRAYER, deadline = t0 + 9 * 60), t0))
        assertEquals(WingPriority.AI_USAGE_HIGH, arbiter.priority(act("ai", ActivitySource.AI_USAGE, usage = 0.80), t0))
        assertEquals(WingPriority.AGENT_RUNNING, arbiter.priority(act("g", ActivitySource.AGENT), t0))
        assertEquals(WingPriority.NOW_PLAYING, arbiter.priority(act("m", ActivitySource.NOW_PLAYING), t0))
        assertEquals(WingPriority.OTHER, arbiter.priority(act("o", ActivitySource.OTHER), t0))
        assertTrue(WingPriority.ALERT > WingPriority.PRAYER_SOON)
        assertTrue(WingPriority.PRAYER_SOON > WingPriority.AI_USAGE_HIGH)
        assertTrue(WingPriority.AI_USAGE_HIGH > WingPriority.AGENT_RUNNING)
        assertTrue(WingPriority.AGENT_RUNNING > WingPriority.NOW_PLAYING)
        assertTrue(WingPriority.NOW_PLAYING > WingPriority.OTHER)
    }

    @Test
    fun `prayer soon only under ten minutes`() {
        val arbiter = ActivityArbiter()
        assertEquals(WingPriority.OTHER, arbiter.priority(act("p", ActivitySource.PRAYER, deadline = t0 + 10 * 60), t0))
        assertEquals(WingPriority.PRAYER_SOON, arbiter.priority(act("p", ActivitySource.PRAYER, deadline = t0 + 599), t0))
        assertEquals(WingPriority.OTHER, arbiter.priority(act("p", ActivitySource.PRAYER, deadline = t0 - 1), t0))
        assertEquals(WingPriority.OTHER, arbiter.priority(act("p", ActivitySource.PRAYER), t0))
    }

    @Test
    fun `AI high only from eighty percent`() {
        val arbiter = ActivityArbiter()
        assertEquals(WingPriority.OTHER, arbiter.priority(act("ai", ActivitySource.AI_USAGE, usage = 0.799), t0))
        assertEquals(WingPriority.AI_USAGE_HIGH, arbiter.priority(act("ai", ActivitySource.AI_USAGE, usage = 0.97), t0))
    }

    @Test
    fun `ranked is stable for ties`() {
        val arbiter = ActivityArbiter()
        val ranked = arbiter.ranked(
            listOf(
                act("m1", ActivitySource.NOW_PLAYING), act("g", ActivitySource.AGENT),
                act("m2", ActivitySource.NOW_PLAYING), act("x", ActivitySource.OTHER, alert = true),
            ),
            t0,
        )
        assertEquals(listOf("x", "g", "m1", "m2"), ranked.map { it.id })
    }

    // Wings

    @Test
    fun `prayer left AI right regardless of priority`() {
        val arbiter = ActivityArbiter()
        val layout = arbiter.layout(
            listOf(act("g", ActivitySource.AGENT), act("ai", ActivitySource.AI_USAGE, usage = 0.1), act("p", ActivitySource.PRAYER)),
            t0,
        )
        assertEquals("p", layout.left?.id)
        assertEquals("ai", layout.right?.id)
        assertEquals("g", layout.rotating?.id)
    }

    @Test
    fun `empty home wing filled by highest priority`() {
        val arbiter = ActivityArbiter()
        val layout = arbiter.layout(
            listOf(act("m", ActivitySource.NOW_PLAYING), act("p", ActivitySource.PRAYER), act("g", ActivitySource.AGENT)),
            t0,
        )
        assertEquals("p", layout.left?.id)
        assertEquals("g", layout.right?.id)
        assertEquals("m", layout.rotating?.id)
    }

    @Test
    fun `empty input`() {
        assertEquals(WingLayout(), ActivityArbiter().layout(emptyList(), t0))
    }

    // Rotation

    @Test
    fun `rotates every eight seconds in priority order`() {
        val arbiter = ActivityArbiter()
        val all = listOf(
            act("p", ActivitySource.PRAYER), act("ai", ActivitySource.AI_USAGE), act("m", ActivitySource.NOW_PLAYING),
            act("o", ActivitySource.OTHER), act("g", ActivitySource.AGENT),
        )
        assertEquals("g", arbiter.layout(all, t0).rotating?.id)
        assertEquals("g", arbiter.layout(all, t0 + 7.9).rotating?.id)
        assertEquals("m", arbiter.layout(all, t0 + 8).rotating?.id)
        assertEquals("m", arbiter.layout(all, t0 + 15).rotating?.id)
        assertEquals("o", arbiter.layout(all, t0 + 16).rotating?.id)
        assertEquals("g", arbiter.layout(all, t0 + 24).rotating?.id, "wraps around")
    }

    @Test
    fun `single rotating item stays`() {
        val arbiter = ActivityArbiter()
        val all = listOf(act("p", ActivitySource.PRAYER), act("ai", ActivitySource.AI_USAGE), act("g", ActivitySource.AGENT))
        for (s in 0..40 step 4) {
            assertEquals("g", arbiter.layout(all, t0 + s).rotating?.id)
        }
    }

    @Test
    fun `removed rotating item is replaced`() {
        val arbiter = ActivityArbiter()
        val p = act("p", ActivitySource.PRAYER)
        val ai = act("ai", ActivitySource.AI_USAGE)
        assertEquals("g", arbiter.layout(listOf(p, ai, act("g", ActivitySource.AGENT), act("m", ActivitySource.NOW_PLAYING)), t0).rotating?.id)
        assertEquals("m", arbiter.layout(listOf(p, ai, act("m", ActivitySource.NOW_PLAYING)), t0 + 2).rotating?.id)
        assertNull(arbiter.layout(listOf(p, ai), t0 + 3).rotating)
    }

    @Test
    fun `alert pins rotating slot`() {
        val arbiter = ActivityArbiter()
        val base = listOf(
            act("p", ActivitySource.PRAYER), act("ai", ActivitySource.AI_USAGE),
            act("g", ActivitySource.AGENT), act("m", ActivitySource.NOW_PLAYING),
        )
        val withAlert = base + act("bat", ActivitySource.OTHER, alert = true)
        assertEquals("bat", arbiter.layout(withAlert, t0).rotating?.id)
        assertEquals("bat", arbiter.layout(withAlert, t0 + 8).rotating?.id)
        assertEquals("bat", arbiter.layout(withAlert, t0 + 30).rotating?.id)
        // Alert cleared: rotation resumes from the top.
        assertEquals("g", arbiter.layout(base, t0 + 31).rotating?.id)
        assertEquals("m", arbiter.layout(base, t0 + 39).rotating?.id)
    }

    @Test
    fun `alert never takes home wing`() {
        val arbiter = ActivityArbiter()
        val layout = arbiter.layout(listOf(act("p", ActivitySource.PRAYER), act("bat", ActivitySource.OTHER, alert = true)), t0)
        assertEquals("p", layout.left?.id)
        assertNull(layout.right)
        assertEquals("bat", layout.rotating?.id)
    }

    @Test
    fun `custom interval`() {
        val arbiter = ActivityArbiter(rotationInterval = Duration.ofSeconds(2))
        val all = listOf(
            act("p", ActivitySource.PRAYER), act("ai", ActivitySource.AI_USAGE),
            act("g", ActivitySource.AGENT), act("m", ActivitySource.NOW_PLAYING),
        )
        assertEquals("g", arbiter.layout(all, t0).rotating?.id)
        assertEquals("m", arbiter.layout(all, t0 + 2).rotating?.id)
    }
}
