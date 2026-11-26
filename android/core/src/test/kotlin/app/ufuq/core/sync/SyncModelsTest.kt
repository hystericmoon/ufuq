package app.ufuq.core.sync

import app.ufuq.core.UsageProvider
import app.ufuq.core.UsageWindowKind
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SyncModelsTest {
    private val snapshot = SyncJson.decodeFromString(SyncSnapshot.serializer(), SyncFixtures.text("snapshot.json"))

    @Test fun decodesGoldenSnapshot() {
        assertEquals(1, snapshot.version)
        assertEquals(SyncFixtures.GENERATED, snapshot.generatedAt)
        assertEquals(3, snapshot.readings.size)
        val session = snapshot.readings[0]
        assertEquals("claude-work", session.accountId)
        assertEquals(0.82, session.fraction)
        assertEquals(SyncFixtures.GENERATED.plusSeconds(4320), session.resetsAt)
        assertFalse(session.isEstimated)
        assertTrue(snapshot.readings[1].isEstimated)
        assertNull(snapshot.readings[1].resetsAt)
        assertEquals("Gemini Pro", snapshot.readings[2].group)
        assertEquals(listOf(SyncAgentState.WAITING, SyncAgentState.RUNNING), snapshot.agents.map { it.agentState })
    }

    @Test fun mapsToUsageModel() {
        val (account, reading) = snapshot.readings[2].toDomain()!!
        assertEquals(UsageProvider.ANTIGRAVITY, account.provider)
        assertEquals(UsageWindowKind.ModelGroup("Gemini Pro"), reading.kind)
        assertEquals(0.05, reading.snapshot.fraction)
        assertEquals(UsageWindowKind.Session5h, snapshot.readings[0].toDomain()!!.second.kind)
        assertEquals(UsageWindowKind.Weekly, snapshot.readings[1].toDomain()!!.second.kind)
    }

    @Test fun unknownProviderKindAndStateAreSkippedNotFatal() {
        val json = """{"version":1,"generatedAt":"2026-11-28T09:00:00Z","future":1,
            "readings":[{"accountId":"a","accountName":"A","provider":"newco","kind":"weekly","fraction":0.1,"capturedAt":"2026-11-28T09:00:00Z"},
                        {"accountId":"a","accountName":"A","provider":"claude","kind":"daily","fraction":0.1,"capturedAt":"2026-11-28T09:00:00Z"},
                        {"accountId":"a","accountName":"A","provider":"claude","kind":"modelGroup","fraction":0.1,"capturedAt":"2026-11-28T09:00:00Z"}],
            "agents":[{"id":"x","title":"t","state":"paused","updatedAt":"2026-11-28T09:00:00Z"}]}"""
        val decoded = SyncJson.decodeFromString(SyncSnapshot.serializer(), json)
        assertTrue(decoded.readings.all { it.toDomain() == null })
        assertNull(decoded.agents.single().agentState)
    }

    @Test fun roundTrips() {
        val again = SyncJson.decodeFromString(SyncSnapshot.serializer(), SyncJson.encodeToString(SyncSnapshot.serializer(), snapshot))
        assertEquals(snapshot, again)
    }

    @Test fun decodesEventBatch() {
        val json = """{"version":1,"generatedAt":"2026-11-28T09:00:00Z","latestSeq":7,"events":[
            {"seq":7,"id":"e","moduleId":"usage","title":"Claude","message":"95%","priority":"critical","createdAt":"2026-11-28T08:59:59Z"}]}"""
        val batch = SyncJson.decodeFromString(SyncEventBatch.serializer(), json)
        assertEquals(7L, batch.latestSeq)
        assertTrue(batch.events.single().isCritical)
    }
}
