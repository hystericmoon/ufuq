package app.ufuq.desktop

import app.ufuq.core.PeekEvent
import app.ufuq.desktop.island.AiUsageSample
import app.ufuq.desktop.island.ButtonAction
import app.ufuq.desktop.island.IslandPageId
import app.ufuq.desktop.settings.DesktopSettings
import kotlinx.coroutines.runBlocking
import java.time.Duration
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class IslandControllerTest {
    // 12:00 in Jakarta: after Dhuhr, before Ashar.
    private val noon = Instant.parse("2026-11-26T05:00:00Z")
    private var now = noon
    private val log = mutableListOf<String>()
    private var settingsOpened = 0
    private var samples = listOf(AiUsageSample("Codex", 0.82, Duration.ofMinutes(72), "5h"))

    private fun controller() = IslandController(
        initial = DesktopSettings(),
        loadUsage = { _, _ -> samples },
        clock = { now },
        beforeOpen = { log += "before" },
        afterClose = { log += "after" },
        onOpenSettings = { settingsOpened++ },
    )

    @Test fun startsCollapsedWithPrayerOnTheLeftAndAiOnTheRight() = runBlocking {
        val c = controller()
        c.refreshUsage()
        val s = c.state.value
        assertEquals(NotchState.Collapsed, s.mode)
        val pill = assertNotNull(s.pill)
        assertTrue(pill.left.startsWith("Ashar "), pill.left)
        assertEquals("Codex 82%", pill.right)
        assertTrue(pill.description.contains("Ashar in 3 hours"), pill.description)
    }

    @Test fun pagesAreMediaFreePrayerThenAi() = runBlocking {
        val c = controller()
        c.refreshUsage()
        assertEquals(listOf(IslandPageId.PRAYER, IslandPageId.AI_USAGE), c.state.value.pages.map { it.id })
    }

    @Test fun hotkeyOpensRemembersFocusAndEscRestoresIt() = runBlocking {
        val c = controller()
        c.toggleWithHotkey()
        assertEquals(NotchState.Expanded, c.state.value.mode)
        assertEquals(listOf("before"), log)
        c.escape()
        assertEquals(NotchState.Collapsed, c.state.value.mode)
        assertEquals(listOf("before", "after"), log)
        c.toggleWithHotkey()
        c.toggleWithHotkey()
        assertEquals(listOf("before", "after", "before", "after"), log)
    }

    @Test fun clickOpensAndPagesClamp() = runBlocking {
        val c = controller()
        c.refreshUsage()
        c.pillClicked()
        c.selectPage(1)
        assertEquals(1, c.state.value.pageIndex)
        c.selectPage(9)
        assertEquals(1, c.state.value.pageIndex)
        c.selectPage(-3)
        assertEquals(0, c.state.value.pageIndex)
    }

    @Test fun aPeekShowsUntilItsTimeIsUpAndExpandedWinsOverIt() {
        val c = controller()
        val peek = PeekEvent("x", "prayer", "Ashar", "in 10 minutes")
        c.enqueuePeek(peek)
        assertEquals(NotchState.Peek(peek), c.state.value.mode)
        c.pillClicked()
        assertEquals(NotchState.Expanded, c.state.value.mode)
        c.escape()
        assertEquals(NotchState.Peek(peek), c.state.value.mode)
        now = noon.plusSeconds(7)
        c.tick()
        assertEquals(NotchState.Collapsed, c.state.value.mode)
    }

    @Test fun escapeDismissesAPeek() {
        val c = controller()
        c.enqueuePeek(PeekEvent("x", "prayer", "Ashar", "soon"))
        c.escape()
        assertEquals(NotchState.Collapsed, c.state.value.mode)
        assertEquals(emptyList(), log)
    }

    @Test fun hoveringHoldsAPeekPastItsTime() {
        val c = controller()
        c.enqueuePeek(PeekEvent("x", "prayer", "Ashar", "soon"))
        c.peekHold(true)
        now = noon.plusSeconds(30)
        c.tick()
        assertEquals(NotchState.Kind.PEEK, c.state.value.mode.kind)
        c.peekHold(false)
        now = noon.plusSeconds(37)
        c.tick()
        assertEquals(NotchState.Collapsed, c.state.value.mode)
    }

    @Test fun crossingEightyPercentQueuesAPeek() = runBlocking {
        samples = listOf(AiUsageSample("Codex", 0.5, Duration.ofHours(1), "5h"))
        val c = controller()
        c.refreshUsage()
        assertEquals(NotchState.Collapsed, c.state.value.mode)
        samples = listOf(AiUsageSample("Codex", 0.83, Duration.ofHours(1), "5h"))
        c.refreshUsage()
        assertEquals("Codex 5h at 83%", (c.state.value.mode as NotchState.Peek).event.title)
    }

    @Test fun aFailingUsageSourceLeavesTheEmptyPage() = runBlocking {
        val c = IslandController(DesktopSettings(), loadUsage = { _, _ -> error("boom") }, clock = { now })
        c.refreshUsage()
        assertEquals("ai.none", c.state.value.pages.last().key)
    }

    @Test fun buttonActionsOpenSettingsOrRefresh() {
        val c = controller()
        c.onAction(ButtonAction.OPEN_SETTINGS)
        assertEquals(1, settingsOpened)
    }

    @Test fun changingTheCityMovesThePrayerTimes() {
        val c = controller()
        val before = c.state.value.pill?.left
        c.updateSettings(DesktopSettings(cityName = "Jayapura"))
        // Jayapura is two hours ahead of Jakarta, so the same instant shows a different clock time.
        assertTrue(c.state.value.pill?.left != before, "pill did not change for another city")
    }
}
