package app.ufuq.desktop

import app.ufuq.core.PeekEvent

/** What the island shows. Pure value (port of the Mac's `NotchState`). */
sealed interface NotchState {
    data object Collapsed : NotchState
    data class Peek(val event: PeekEvent) : NotchState
    data object Expanded : NotchState

    enum class Kind { COLLAPSED, PEEK, EXPANDED }

    val kind: Kind
        get() = when (this) {
            Collapsed -> Kind.COLLAPSED
            is Peek -> Kind.PEEK
            Expanded -> Kind.EXPANDED
        }
}

/** How the expanded panel was opened. Only hover-opened panels close when the mouse leaves. */
enum class ExpandOrigin { HOTKEY, CLICK, HOVER }

/**
 * Pure state machine for the island (port of `NotchStateMachine`). The controller feeds it events
 * and applies the result.
 *
 * - Expanded wins over a peek; when expanded closes, a waiting peek shows.
 * - The hotkey toggles expanded; Esc closes expanded, otherwise dismisses the current peek.
 * - Mouse exit collapses only a panel that hover opened.
 * - The peek content comes from `PeekQueue.current`, which the controller passes to [setPeek].
 */
class NotchStateMachine {
    enum class EscapeResult { IGNORED, COLLAPSED, DISMISSED_PEEK }

    var isExpanded = false
        private set
    var origin: ExpandOrigin? = null
        private set
    var currentPeek: PeekEvent? = null
        private set

    val state: NotchState
        get() = when {
            isExpanded -> NotchState.Expanded
            else -> currentPeek?.let { NotchState.Peek(it) } ?: NotchState.Collapsed
        }

    fun setPeek(event: PeekEvent?) {
        currentPeek = event
    }

    fun open(origin: ExpandOrigin) {
        isExpanded = true
        this.origin = origin
    }

    fun collapse() {
        isExpanded = false
        origin = null
    }

    fun toggleWithHotkey() {
        if (isExpanded) collapse() else open(ExpandOrigin.HOTKEY)
    }

    fun escape(): EscapeResult {
        if (isExpanded) {
            collapse()
            return EscapeResult.COLLAPSED
        }
        if (currentPeek != null) {
            currentPeek = null
            return EscapeResult.DISMISSED_PEEK
        }
        return EscapeResult.IGNORED
    }

    /** Pointer entered the panel. Opens it only when the hover setting is on. */
    fun mouseEntered(hoverEnabled: Boolean) {
        if (!hoverEnabled || isExpanded) return
        open(ExpandOrigin.HOVER)
    }

    /** Pointer left the panel. Collapses only a hover-opened panel. */
    fun mouseExited() {
        if (!isExpanded || origin != ExpandOrigin.HOVER) return
        collapse()
    }
}
