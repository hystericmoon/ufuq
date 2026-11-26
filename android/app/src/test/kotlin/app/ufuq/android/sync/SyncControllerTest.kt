package app.ufuq.android.sync

import app.ufuq.core.PeekEvent
import app.ufuq.core.UsageResult
import app.ufuq.core.sync.PairingPayload
import app.ufuq.core.sync.SyncClient
import app.ufuq.core.sync.SyncEvent
import app.ufuq.core.sync.SyncEventBatch
import app.ufuq.core.sync.SyncSnapshot
import java.time.Clock
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

@OptIn(ExperimentalCoroutinesApi::class)
class SyncControllerTest {
    private val payload = PairingPayload(1, "mac.local", 4000, "dev-1", "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8", "Mac")
    private val clock = Clock.fixed(SyncFixtures.NOW, ZoneOffset.UTC)

    private class FakeSource(initial: PairingPayload?) : PairingSource {
        val flow = MutableStateFlow(initial)
        override val pairing = flow
    }

    private class FakeClient(
        val snapshots: MutableList<UsageResult<SyncSnapshot>> = mutableListOf(),
        val events: MutableList<UsageResult<SyncEventBatch>> = mutableListOf(),
    ) : SyncClient {
        var snapshotCalls = 0
        var eventCalls = 0
        val eventSince = mutableListOf<Long>()

        override suspend fun snapshot(): UsageResult<SyncSnapshot> {
            snapshotCalls++
            return if (snapshots.size > 1) snapshots.removeAt(0) else snapshots.first()
        }

        override suspend fun events(since: Long): UsageResult<SyncEventBatch> {
            eventCalls++
            eventSince += since
            // A real long poll waits; the fake parks for a while so the loop does not spin.
            kotlinx.coroutines.delay(30_000)
            return if (events.size > 1) events.removeAt(0) else events.first()
        }
    }

    private fun TestScope.controller(source: PairingSource, client: FakeClient, online: () -> Boolean = { true }) =
        SyncController(source, backgroundScope, TestSyncStrings, clientFactory = { client }, clock = clock, online = online)

    private val ok = UsageResult.Available(SyncFixtures.snapshot())
    private val emptyEvents = UsageResult.Available(SyncEventBatch(1, SyncFixtures.NOW, 0, emptyList()))

    @Test fun unpairedDoesNotPollAtAll() = runTest {
        val client = FakeClient(mutableListOf(ok), mutableListOf(emptyEvents))
        val c = controller(FakeSource(null), client)
        c.acquire()
        advanceTimeBy(120_000)
        assertEquals(SyncState.Unpaired, c.state.value)
        assertEquals(0, client.snapshotCalls)
        assertEquals(0, client.eventCalls)
    }

    @Test fun pairedGoesLiveAndPollsEvery30Seconds() = runTest {
        val client = FakeClient(mutableListOf(ok), mutableListOf(emptyEvents))
        val c = controller(FakeSource(payload), client)
        c.acquire()
        runCurrent()
        assertIs<SyncState.Live>(c.state.value)
        assertEquals(1, client.snapshotCalls)
        advanceTimeBy(30_001)
        assertEquals(2, client.snapshotCalls)
    }

    @Test fun releasingStopsPolling() = runTest {
        val client = FakeClient(mutableListOf(ok), mutableListOf(emptyEvents))
        val c = controller(FakeSource(payload), client)
        c.acquire()
        runCurrent()
        c.release()
        val calls = client.snapshotCalls
        advanceTimeBy(300_000)
        assertEquals(calls, client.snapshotCalls)
    }

    @Test fun lostMacKeepsLastDataAsUnreachableAndBacksOff() = runTest {
        val client = FakeClient(mutableListOf(ok, UsageResult.Unavailable("Mac not reachable")), mutableListOf(emptyEvents))
        val c = controller(FakeSource(payload), client)
        c.acquire()
        runCurrent()
        advanceTimeBy(30_001)
        val state = assertIs<SyncState.Unreachable>(c.state.value)
        assertEquals(SyncFixtures.NOW, state.data?.fetchedAt)
        val calls = client.snapshotCalls
        advanceTimeBy(2_001) // first backoff step
        assertEquals(calls + 1, client.snapshotCalls)
        advanceTimeBy(3_000) // second step is 4 s, so no new call yet
        assertEquals(calls + 1, client.snapshotCalls)
    }

    @Test fun rejectedKeyMeansPairAgainAndStopsPolling() = runTest {
        val client = FakeClient(mutableListOf(UsageResult.Unavailable("Pair again")), mutableListOf(UsageResult.Unavailable("Pair again")))
        val c = controller(FakeSource(payload), client)
        c.acquire()
        runCurrent()
        assertEquals(SyncState.PairAgain, c.state.value)
        val calls = client.snapshotCalls
        advanceTimeBy(300_000)
        assertEquals(calls, client.snapshotCalls)
    }

    @Test fun pairingAgainResumes() = runTest {
        val source = FakeSource(payload)
        val client = FakeClient(mutableListOf(UsageResult.Unavailable("Pair again"), ok), mutableListOf(emptyEvents))
        val c = controller(source, client)
        c.acquire()
        runCurrent()
        assertEquals(SyncState.PairAgain, c.state.value)
        source.flow.value = payload.copy(key = "AQECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8")
        runCurrent()
        assertIs<SyncState.Live>(c.state.value)
    }

    @Test fun forgettingTheMacReturnsToUnpaired() = runTest {
        val source = FakeSource(payload)
        val client = FakeClient(mutableListOf(ok), mutableListOf(emptyEvents))
        val c = controller(source, client)
        c.acquire()
        runCurrent()
        source.flow.value = null
        runCurrent()
        assertEquals(SyncState.Unpaired, c.state.value)
    }

    @Test fun macEventsReachThePeekFlowAndCursorAdvances() = runTest {
        val event = SyncEvent(7, "usage-claude-95", "usage", "Claude Work", "95% of session", "critical", SyncFixtures.NOW)
        val batch = UsageResult.Available(SyncEventBatch(1, SyncFixtures.NOW, 7, listOf(event)))
        val client = FakeClient(mutableListOf(ok), mutableListOf(batch, emptyEvents.let { UsageResult.Available(SyncEventBatch(1, SyncFixtures.NOW, 7, emptyList())) }))
        val c = controller(FakeSource(payload), client)
        val seen = mutableListOf<PeekEvent>()
        backgroundScope.launch { c.peeks.collect { seen += it } }
        runCurrent()
        c.acquire()
        advanceTimeBy(30_001)
        assertEquals(1, seen.size)
        assertEquals(PeekEvent.Priority.CRITICAL, seen[0].priority)
        advanceTimeBy(31_000)
        assertEquals(7L, client.eventSince[1])
    }

    @Test fun agentTransitionsBetweenSnapshotsBecomePeeks() = runTest {
        val running = UsageResult.Available(SyncFixtures.snapshot(agents = listOf(SyncFixtures.agent("a", "running", "Refactor"))))
        val waiting = UsageResult.Available(SyncFixtures.snapshot(agents = listOf(SyncFixtures.agent("a", "waiting", "Refactor"))))
        val client = FakeClient(mutableListOf(running, waiting), mutableListOf(emptyEvents))
        val c = controller(FakeSource(payload), client)
        val seen = mutableListOf<PeekEvent>()
        backgroundScope.launch { c.peeks.collect { seen += it } }
        runCurrent()
        c.acquire()
        advanceTimeBy(30_001)
        assertEquals(listOf("Claude needs input"), seen.map { it.title })
    }

    @Test fun offlinePhoneDoesNotTouchTheNetwork() = runTest {
        val client = FakeClient(mutableListOf(ok), mutableListOf(emptyEvents))
        val c = controller(FakeSource(payload), client, online = { false })
        c.acquire()
        advanceTimeBy(10_000)
        assertEquals(0, client.snapshotCalls)
        assertIs<SyncState.Unreachable>(c.state.value)
    }

    @Test fun backoffDoublesUpToAMinute() {
        assertEquals(listOf(2_000L, 4_000L, 8_000L, 16_000L, 32_000L, 60_000L, 60_000L), (1..7).map(SyncController::backoff))
        assertTrue(SyncController.backoff(100) <= 60_000)
    }
}
