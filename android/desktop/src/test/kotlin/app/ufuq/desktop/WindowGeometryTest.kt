package app.ufuq.desktop

import app.ufuq.desktop.island.SliderGeometry
import kotlin.test.Test
import kotlin.test.assertEquals

class WindowGeometryTest {
    private val fullHd = ScreenRect(0, 0, 1920, 1080)

    @Test fun collapsedPillIsCentredAtTheTop() {
        val p = WindowGeometry.place(fullHd, NotchState.Kind.COLLAPSED)
        assertEquals(WindowPlacement(810, WindowGeometry.TOP_MARGIN, 300, 32), p)
    }

    @Test fun peekAndExpandedAreCentredToo() {
        assertEquals(WindowPlacement(784, 8, 352, 92), WindowGeometry.place(fullHd, NotchState.Kind.PEEK))
        assertEquals(WindowPlacement(750, 8, 420, 124), WindowGeometry.place(fullHd, NotchState.Kind.EXPANDED))
    }

    @Test fun aTopTaskbarPushesItDown() {
        val p = WindowGeometry.place(ScreenRect(0, 0, 1920, 1080, insetTop = 40), NotchState.Kind.COLLAPSED)
        assertEquals(48, p.y)
    }

    @Test fun aScreenToTheRightKeepsItsOffset() {
        val p = WindowGeometry.place(ScreenRect(1920, 0, 1280, 720), NotchState.Kind.COLLAPSED)
        assertEquals(1920 + (1280 - 300) / 2, p.x)
    }

    @Test fun aScreenNarrowerThanTheWindowClampsToItsEdge() {
        val p = WindowGeometry.place(ScreenRect(100, 0, 360, 640), NotchState.Kind.EXPANDED)
        assertEquals(100, p.x)
    }

    @Test fun sizesFollowTheSpec() {
        assertEquals(300 to 32, IslandSizes.of(NotchState.Kind.COLLAPSED))
        assertEquals(352 to 92, IslandSizes.of(NotchState.Kind.PEEK))
    }
}

class SliderGeometryTest {
    @Test fun zeroIsTheHandleAloneAtTheStart() {
        val g = SliderGeometry.of(0f, 316f)
        assertEquals(0f, g.handleX)
        assertEquals(0f, g.activeWidth)
        assertEquals(10f, g.inactiveStart)
        assertEquals(306f, g.inactiveWidth)
    }

    @Test fun handleIsProportionalToTheFullWidth() {
        val g = SliderGeometry.of(0.5f, 316f)
        assertEquals(156f, g.handleX)
        assertEquals(150f, g.activeWidth)
        assertEquals(166f, g.inactiveStart)
        assertEquals(150f, g.inactiveWidth)
    }

    @Test fun fullValueEndsAtTheRightEdgeWithNoInactiveTrack() {
        val g = SliderGeometry.of(1f, 316f)
        assertEquals(312f, g.handleX)
        assertEquals(0f, g.inactiveWidth)
        assertEquals(306f, g.activeWidth)
    }

    @Test fun badInputIsClamped() {
        assertEquals(0f, SliderGeometry.of(Float.NaN, 300f).handleX)
        assertEquals(0f, SliderGeometry.of(-1f, 300f).handleX)
        assertEquals(296f, SliderGeometry.of(7f, 300f).handleX)
    }
}
