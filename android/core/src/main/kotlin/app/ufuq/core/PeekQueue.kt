package app.ufuq.core

import java.time.Duration
import java.time.Instant

/**
 * One peek at a time; critical alerts jump the queue.
 *
 * - FIFO within a priority; critical events go ahead of every waiting normal one.
 * - A critical event preempts a normal peek on screen; the interrupted peek goes back to the
 *   front of the normal queue and later shows for its full duration.
 * - A peek auto-dismisses after its duration. Hover (or touch-and-hold) holds it; on release the
 *   remaining time resumes.
 * - Enqueueing an id already waiting replaces that entry (no duplicate alerts).
 *
 * Time is passed in, so the queue is deterministic and testable; the app calls [tick].
 */
class PeekQueue {
    var current: PeekEvent? = null
        private set
    private val _pending = mutableListOf<PeekEvent>()
    val pending: List<PeekEvent> get() = _pending.toList()

    private var deadline: Instant? = null
    private var heldRemaining: Duration? = null

    val isHeld: Boolean get() = heldRemaining != null

    fun enqueue(event: PeekEvent, now: Instant) {
        if (current?.id == event.id) {
            current = event
            return
        }
        _pending.removeAll { it.id == event.id }

        val shown = current
        if (shown != null && event.priority > shown.priority) {
            current = null
            deadline = null
            heldRemaining = null
            insert(shown, atFrontOfPriority = true)
            insert(event, atFrontOfPriority = false)
            advance(now)
            return
        }

        insert(event, atFrontOfPriority = false)
        if (current == null) advance(now)
    }

    /** Dismisses the current peek when its time is up (unless held) and shows the next one. */
    fun tick(now: Instant) {
        val due = deadline
        if (current == null || heldRemaining != null || due == null || now.isBefore(due)) return
        current = null
        advance(now)
    }

    /** Esc or a tap: dismiss now and show the next one. */
    fun dismissCurrent(now: Instant) {
        current = null
        deadline = null
        heldRemaining = null
        advance(now)
    }

    /** A pointer or finger on the peek holds it; leaving resumes the remaining time. */
    fun setHovering(hovering: Boolean, now: Instant) {
        if (current == null) return
        if (hovering) {
            val due = deadline
            if (heldRemaining != null || due == null) return
            heldRemaining = Duration.between(now, due).coerceAtLeast(Duration.ZERO)
        } else {
            val remaining = heldRemaining ?: return
            deadline = now.plus(remaining)
            heldRemaining = null
        }
    }

    /** Drops every waiting and shown peek from a module (e.g. when it is turned off). */
    fun removeAll(fromModule: String, now: Instant) {
        _pending.removeAll { it.moduleId == fromModule }
        if (current?.moduleId == fromModule) dismissCurrent(now)
    }

    private fun insert(event: PeekEvent, atFrontOfPriority: Boolean) {
        val index = if (atFrontOfPriority) {
            _pending.indexOfFirst { it.priority <= event.priority }
        } else {
            _pending.indexOfFirst { it.priority < event.priority }
        }
        _pending.add(if (index >= 0) index else _pending.size, event)
    }

    private fun advance(now: Instant) {
        heldRemaining = null
        if (_pending.isEmpty()) {
            current = null
            deadline = null
            return
        }
        val next = _pending.removeAt(0)
        current = next
        deadline = now.plus(next.duration)
    }
}

