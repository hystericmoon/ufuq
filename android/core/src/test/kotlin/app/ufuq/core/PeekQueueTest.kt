package app.ufuq.core

import org.junit.Test
import java.time.Duration
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PeekQueueTest {
    private val t0 = T0

    private fun peek(id: String, priority: PeekEvent.Priority = PeekEvent.Priority.NORMAL, module: String = "m") =
        PeekEvent(id, module, title = id, message = "", priority = priority)

    private val critical = PeekEvent.Priority.CRITICAL

    @Test
    fun `shows one at a time FIFO`() {
        val q = PeekQueue()
        q.enqueue(peek("a"), t0)
        q.enqueue(peek("b"), t0)
        q.enqueue(peek("c"), t0)
        assertEquals("a", q.current?.id)
        assertEquals(listOf("b", "c"), q.pending.map { it.id })
    }

    @Test
    fun `auto dismiss after six seconds`() {
        val q = PeekQueue()
        q.enqueue(peek("a"), t0)
        q.enqueue(peek("b"), t0)
        q.tick(t0 + 5.9)
        assertEquals("a", q.current?.id)
        q.tick(t0 + 6)
        assertEquals("b", q.current?.id)
        q.tick(t0 + 12)
        assertNull(q.current)
    }

    @Test
    fun `critical jumps waiting normals`() {
        val q = PeekQueue()
        q.enqueue(peek("n0", critical), t0) // showing
        q.enqueue(peek("a"), t0)
        q.enqueue(peek("b"), t0)
        q.enqueue(peek("c1", critical), t0)
        q.enqueue(peek("c2", critical), t0)
        assertEquals("n0", q.current?.id, "critical does not preempt critical")
        assertEquals(listOf("c1", "c2", "a", "b"), q.pending.map { it.id })
    }

    @Test
    fun `critical preempts showing normal which returns first`() {
        val q = PeekQueue()
        q.enqueue(peek("a"), t0)
        q.enqueue(peek("b"), t0)
        q.enqueue(peek("adhan", critical), t0 + 2)
        assertEquals("adhan", q.current?.id)
        assertEquals(listOf("a", "b"), q.pending.map { it.id })
        q.tick(t0 + 8)
        assertEquals("a", q.current?.id)
        q.tick(t0 + 13.9)
        assertEquals("a", q.current?.id, "returns with its full duration")
        q.tick(t0 + 14)
        assertEquals("b", q.current?.id)
    }

    @Test
    fun `hover holds and resumes remaining time`() {
        val q = PeekQueue()
        q.enqueue(peek("a"), t0)
        q.enqueue(peek("b"), t0)
        q.setHovering(true, t0 + 4)
        assertTrue(q.isHeld)
        q.tick(t0 + 60)
        assertEquals("a", q.current?.id)
        q.setHovering(false, t0 + 60)
        q.tick(t0 + 61.9)
        assertEquals("a", q.current?.id)
        q.tick(t0 + 62)
        assertEquals("b", q.current?.id)
        assertFalse(q.isHeld)
    }

    @Test
    fun `dismiss shows next`() {
        val q = PeekQueue()
        q.enqueue(peek("a"), t0)
        q.enqueue(peek("b"), t0)
        q.dismissCurrent(t0 + 1)
        assertEquals("b", q.current?.id)
        q.tick(t0 + 6.9)
        assertEquals("b", q.current?.id)
        q.tick(t0 + 7)
        assertNull(q.current)
    }

    @Test
    fun `same id replaces instead of duplicating`() {
        val q = PeekQueue()
        q.enqueue(peek("a"), t0)
        q.enqueue(peek("b"), t0)
        q.enqueue(peek("b"), t0)
        q.enqueue(peek("a"), t0)
        assertEquals("a", q.current?.id)
        assertEquals(listOf("b"), q.pending.map { it.id })
    }

    @Test
    fun `remove all from module`() {
        val q = PeekQueue()
        q.enqueue(peek("a", module = "ai"), t0)
        q.enqueue(peek("b", module = "prayer"), t0)
        q.enqueue(peek("c", module = "ai"), t0)
        q.removeAll("ai", t0)
        assertEquals("b", q.current?.id)
        assertTrue(q.pending.isEmpty())
    }

    @Test
    fun `announcement default`() {
        val p = PeekEvent("x", "ai", title = "Claude Work at 95%", message = "Resets in 40 minutes", priority = critical)
        assertEquals("Claude Work at 95%. Resets in 40 minutes", p.announcement)
        assertEquals(Duration.ofSeconds(6), p.duration)
    }
}
