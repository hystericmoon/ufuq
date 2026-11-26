package app.ufuq.android.sync

import app.ufuq.android.TestStrings
import app.ufuq.android.island.ButtonAction
import app.ufuq.android.island.IslandPageId
import app.ufuq.core.ActivitySource
import app.ufuq.core.PeekEvent
import app.ufuq.core.UsageLevel
import app.ufuq.core.UsageProvider
import app.ufuq.core.sync.SyncEvent
import java.time.Duration
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SyncMapperTest {
    private val now = SyncFixtures.NOW
    private fun page(state: SyncState) = SyncMapper.pageB(state, now, TestStrings, TestSyncStrings)

    @Test fun headlineIsWorstSessionAcrossClaudeAndCodexIgnoringWeeklyAndAntigravity() {
        val h = assertNotNull(SyncMapper.headline(SyncFixtures.snapshot()))
        assertEquals("Claude", h.label)
        assertEquals(0.82, h.fraction)
        assertEquals(UsageProvider.CLAUDE, h.provider)
        assertEquals(now.plus(Duration.ofMinutes(72)), h.resetsAt)
    }

    @Test fun codexWinsWhenItsSessionIsHigher() {
        val snapshot = SyncFixtures.snapshot(
            listOf(SyncFixtures.reading("Claude Work", "claude", "session5h", 0.2), SyncFixtures.reading("Codex", "codex", "session5h", 0.9, 30)),
        )
        assertEquals("Codex", SyncMapper.headline(snapshot)?.label)
    }

    @Test fun fallsBackToOtherWindowsWithoutASessionAndSkipsUnknownKinds() {
        val weeklyOnly = SyncFixtures.snapshot(listOf(SyncFixtures.reading("Claude Work", "claude", "weekly", 0.5), SyncFixtures.reading("X", "newprovider", "session5h", 0.99)))
        assertEquals(0.5, SyncMapper.headline(weeklyOnly)?.fraction)
        assertNull(SyncMapper.headline(SyncFixtures.snapshot(emptyList())))
        assertNull(SyncMapper.headline(SyncFixtures.snapshot(listOf(SyncFixtures.reading("Antigravity", "antigravity", "modelGroup", 0.9, group = "G")))))
    }

    @Test fun liveDataShowsTheUsageSliderWithAmberAtEighty() {
        val p = page(SyncState.Live(SyncFixtures.data()))
        assertEquals(IslandPageId.AI_USAGE, p.id)
        assertEquals(0.82f, p.slider.fraction)
        assertEquals("Claude", p.slider.label)
        assertEquals("82%", p.slider.secondary)
        assertEquals("1:12", p.slider.trailing)
        assertEquals(UsageLevel.WARNING, p.slider.level)
        assertEquals(ButtonAction.REFRESH, p.buttonAction)
        assertTrue("82 percent" in p.slider.description)
    }

    @Test fun ninetySixPercentIsRedWithThePercentStill() {
        val snapshot = SyncFixtures.snapshot(listOf(SyncFixtures.reading("Claude Work", "claude", "session5h", 0.96, 25)))
        val p = page(SyncState.Live(SyncFixtures.data(snapshot)))
        assertEquals(UsageLevel.CRITICAL, p.slider.level)
        assertEquals("96%", p.slider.secondary)
    }

    @Test fun unpairedIsTheEmptyStateThatOpensTheApp() {
        val p = page(SyncState.Unpaired)
        assertEquals("Pair with your Mac", p.slider.label)
        assertEquals(ButtonAction.OPEN_APP, p.buttonAction)
    }

    @Test fun connectingWithoutDataSaysSo() {
        val p = page(SyncState.Connecting())
        assertEquals("Connecting to your Mac", p.slider.label)
        assertEquals(0f, p.slider.fraction)
    }

    @Test fun pairAgainHasAPairButton() {
        val p = page(SyncState.PairAgain)
        assertEquals("Pair again", p.slider.label)
        assertEquals(ButtonAction.PAIR_MAC, p.buttonAction)
        assertEquals("Pair again", p.buttonLabel)
    }

    @Test fun unreachableKeepsLastDataMarkedStale() {
        val fetched = now.minus(Duration.ofMinutes(5))
        val p = page(SyncState.Unreachable(SyncFixtures.data(fetchedAt = fetched)))
        assertEquals(0.82f, p.slider.fraction)
        assertEquals("82%", p.slider.secondary)
        assertEquals("Offline", p.slider.trailing)
        assertTrue("Mac not on this network. Updated 5 minutes ago." in p.slider.description, p.slider.description)
    }

    @Test fun unreachableWithoutDataIsAMessage() {
        val p = page(SyncState.Unreachable(null))
        assertEquals("Mac not on this network", p.slider.label)
        assertEquals(ButtonAction.REFRESH, p.buttonAction)
    }

    @Test fun otherProblemsShowTheReason() {
        val p = page(SyncState.Problem("Clocks differ by more than 5 minutes"))
        assertEquals("Clocks differ by more than 5 minutes", p.slider.secondary)
    }

    @Test fun usageActivityIsTheWorstPercentForTheRightWing() {
        val a = assertNotNull(SyncMapper.usageActivity(SyncState.Live(SyncFixtures.data()), now, TestStrings))
        assertEquals(ActivitySource.AI_USAGE, a.source)
        assertEquals("82%", a.text)
        assertEquals(0.82, a.usageFraction)
        assertNull(SyncMapper.usageActivity(SyncState.Unpaired, now, TestStrings))
        // A Mac that has been gone for a long time stops claiming a number in the pill.
        val old = SyncState.Unreachable(SyncFixtures.data(fetchedAt = now.minus(Duration.ofHours(1))))
        assertNull(SyncMapper.usageActivity(old, now, TestStrings))
    }

    @Test fun agentActivityWhileATaskRunsAndAlertWhenWaiting() {
        val running = SyncState.Live(SyncFixtures.data(SyncFixtures.snapshot(agents = listOf(SyncFixtures.agent("a", "running", "Fix tests")))))
        val activity = assertNotNull(SyncMapper.agentActivity(running, now, TestSyncStrings))
        assertEquals(ActivitySource.AGENT, activity.source)
        assertEquals(false, activity.isAlert)
        assertTrue("Fix tests" in activity.accessibilityLabel)

        val waiting = SyncState.Live(SyncFixtures.data(SyncFixtures.snapshot(agents = listOf(SyncFixtures.agent("a", "running"), SyncFixtures.agent("b", "waiting", "Refactor")))))
        val alert = assertNotNull(SyncMapper.agentActivity(waiting, now, TestSyncStrings))
        assertTrue(alert.isAlert)
        assertEquals("Needs input", alert.text)

        val done = SyncState.Live(SyncFixtures.data(SyncFixtures.snapshot(agents = listOf(SyncFixtures.agent("a", "done")))))
        assertNull(SyncMapper.agentActivity(done, now, TestSyncStrings))
        assertNull(SyncMapper.agentActivity(SyncState.Unpaired, now, TestSyncStrings))
    }

    @Test fun agentWaitingIsACriticalPeekAndDoneIsNormal() {
        val before = listOf(SyncFixtures.agent("a", "running"), SyncFixtures.agent("b", "running"))
        val after = listOf(SyncFixtures.agent("a", "waiting", "Refactor sync"), SyncFixtures.agent("b", "done", "Fix tests"))
        val peeks = SyncMapper.agentPeeks(before, after, TestSyncStrings)
        assertEquals(2, peeks.size)
        val needs = peeks.first { it.title == "Claude needs input" }
        assertEquals(PeekEvent.Priority.CRITICAL, needs.priority)
        assertEquals("Refactor sync", needs.message)
        assertEquals(PeekEvent.Priority.NORMAL, peeks.first { it.title == "Task done" }.priority)
    }

    @Test fun noAgentPeeksOnFirstSnapshotOrWithoutAChange() {
        val agents = listOf(SyncFixtures.agent("a", "waiting"))
        assertTrue(SyncMapper.agentPeeks(null, agents, TestSyncStrings).isEmpty())
        assertTrue(SyncMapper.agentPeeks(agents, agents, TestSyncStrings).isEmpty())
        // A task that appears already done (never seen running) is not announced.
        assertTrue(SyncMapper.agentPeeks(emptyList(), listOf(SyncFixtures.agent("z", "done")), TestSyncStrings).isEmpty())
    }

    @Test fun macEventsBecomePeeksAndOldOnesAreDropped() {
        val fresh = SyncEvent(7, "usage-claude-95", "usage", "Claude Work", "95% of session", "critical", now.minusSeconds(10))
        val peek = assertNotNull(SyncMapper.peek(fresh, now))
        assertEquals("sync-usage-claude-95", peek.id)
        assertEquals(PeekEvent.Priority.CRITICAL, peek.priority)
        assertEquals(SyncMapper.USAGE_MODULE_ID, peek.moduleId)
        val agent = SyncEvent(8, "agent-1", "agent", "Claude needs input", "Refactor", "critical", now)
        assertEquals(SyncMapper.AGENT_MODULE_ID, SyncMapper.peek(agent, now)?.moduleId)
        assertNull(SyncMapper.peek(fresh.copy(createdAt = now.minus(Duration.ofMinutes(10))), now))
    }
}
