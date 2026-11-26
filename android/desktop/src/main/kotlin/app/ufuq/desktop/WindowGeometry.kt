package app.ufuq.desktop

/** Window sizes in dp (spec: collapsed pill 300x32, peek 352x92; the expanded island is wider than the phone's 104 dp strip to fit page dots). */
object IslandSizes {
    const val COLLAPSED_WIDTH = 300
    const val COLLAPSED_HEIGHT = 32
    const val PEEK_WIDTH = 352
    const val PEEK_HEIGHT = 92
    const val EXPANDED_WIDTH = 420
    const val EXPANDED_HEIGHT = 112

    fun of(kind: NotchState.Kind): Pair<Int, Int> = when (kind) {
        NotchState.Kind.COLLAPSED -> COLLAPSED_WIDTH to COLLAPSED_HEIGHT
        NotchState.Kind.PEEK -> PEEK_WIDTH to PEEK_HEIGHT
        NotchState.Kind.EXPANDED -> EXPANDED_WIDTH to EXPANDED_HEIGHT
    }
}

/** A screen's usable area in dp (AWT user-space units): [insetTop] is a taskbar docked at the top. */
data class ScreenRect(val x: Int, val y: Int, val width: Int, val height: Int, val insetTop: Int = 0)

data class WindowPlacement(val x: Int, val y: Int, val width: Int, val height: Int)

object WindowGeometry {
    /** Gap between the top of the screen (or a top taskbar) and the floating pill. */
    const val TOP_MARGIN = 8

    /** Top centre of [screen]; the window is clamped inside the screen when it is wider than it. */
    fun place(screen: ScreenRect, kind: NotchState.Kind): WindowPlacement {
        val (w, h) = IslandSizes.of(kind)
        val x = (screen.x + (screen.width - w) / 2).coerceIn(screen.x, maxOf(screen.x, screen.x + screen.width - w))
        val y = screen.y + screen.insetTop + TOP_MARGIN
        return WindowPlacement(x, y, w, h)
    }
}
