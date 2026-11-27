package app.ufuq.desktop

import app.ufuq.core.PeekEvent
import app.ufuq.core.PeekQueue
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals

/** Port of App/Tests/NotchStateTests.swift. */
class NotchStateMachineTest {
    private val peek = PeekEvent(id = "p1", moduleId = "prayer", title = "Ashar", message = "in 10 minutes")

    @Test fun startsCollapsed() = assertEquals(NotchState.Collapsed, NotchStateMachine().state)

    @Test fun hotkeyTogglesExpanded() {
        val m = NotchStateMachine()
        m.toggleWithHotkey()
        assertEquals(NotchState.Expanded, m.state)
        assertEquals(ExpandOrigin.HOTKEY, m.origin)
        m.toggleWithHotkey()
        assertEquals(NotchState.Collapsed, m.state)
    }

    @Test fun escapeClosesExpanded() {
        val m = NotchStateMachine()
        m.toggleWithHotkey()
        assertEquals(NotchStateMachine.EscapeResult.COLLAPSED, m.escape())
        assertEquals(NotchState.Collapsed, m.state)
    }

    @Test fun escapeDismissesPeekThenIgnores() {
        val m = NotchStateMachine()
        m.setPeek(peek)
        assertEquals(NotchState.Peek(peek), m.state)
        assertEquals(NotchStateMachine.EscapeResult.DISMISSED_PEEK, m.escape())
        assertEquals(NotchState.Collapsed, m.state)
        assertEquals(NotchStateMachine.EscapeResult.IGNORED, m.escape())
    }

    @Test fun expandedWinsOverPeekAndPeekReturnsAfter() {
        val m = NotchStateMachine()
        m.setPeek(peek)
        m.toggleWithHotkey()
        assertEquals(NotchState.Expanded, m.state)
        m.toggleWithHotkey()
        assertEquals(NotchState.Peek(peek), m.state)
    }

    @Test fun peekEndsWhenQueueEmpties() {
        val m = NotchStateMachine()
        m.setPeek(peek)
        m.setPeek(null)
        assertEquals(NotchState.Collapsed, m.state)
    }

    @Test fun hoverOpensOnlyWhenEnabled() {
        val m = NotchStateMachine()
        m.mouseEntered(hoverEnabled = false)
        assertEquals(NotchState.Collapsed, m.state)
        m.mouseEntered(hoverEnabled = true)
        assertEquals(NotchState.Expanded, m.state)
        assertEquals(ExpandOrigin.HOVER, m.origin)
    }

    @Test fun mouseExitCollapsesOnlyHoverOpened() {
        val hover = NotchStateMachine()
        hover.mouseEntered(hoverEnabled = true)
        hover.mouseExited()
        assertEquals(NotchState.Collapsed, hover.state)

        val hotkey = NotchStateMachine()
        hotkey.toggleWithHotkey()
        hotkey.mouseExited()
        assertEquals(NotchState.Expanded, hotkey.state)
    }

    @Test fun hotkeyAfterHoverKeepsPanelOpenOnExit() {
        val m = NotchStateMachine()
        m.mouseEntered(hoverEnabled = true)
        m.open(ExpandOrigin.HOTKEY)
        m.mouseExited()
        assertEquals(NotchState.Expanded, m.state)
    }

    @Test fun clickOpenKeepsPanelOnMouseExit() {
        val m = NotchStateMachine()
        m.open(ExpandOrigin.CLICK)
        m.mouseExited()
        assertEquals(NotchState.Expanded, m.state)
    }

    @Test fun kindsMatchStates() {
        assertEquals(NotchState.Kind.COLLAPSED, NotchState.Collapsed.kind)
        assertEquals(NotchState.Kind.PEEK, NotchState.Peek(peek).kind)
        assertEquals(NotchState.Kind.EXPANDED, NotchState.Expanded.kind)
    }

    @Test fun peekQueueDrivesPeekAutoReturn() {
        val queue = PeekQueue()
        val m = NotchStateMachine()
        val t0 = Instant.ofEpochSecond(1_000)
        queue.enqueue(peek, t0)
        m.setPeek(queue.current)
        assertEquals(NotchState.Peek(peek), m.state)
        queue.tick(t0.plus(PeekEvent.DEFAULT_DURATION).plusMillis(100))
        m.setPeek(queue.current)
        assertEquals(NotchState.Collapsed, m.state)
    }
}
