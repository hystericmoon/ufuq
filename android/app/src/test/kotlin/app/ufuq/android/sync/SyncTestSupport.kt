package app.ufuq.android.sync

import app.ufuq.core.sync.SyncAgent
import app.ufuq.core.sync.SyncReading
import app.ufuq.core.sync.SyncSnapshot
import java.time.Duration
import java.time.Instant

object SyncFixtures {
    val NOW: Instant = Instant.parse("2026-11-28T09:00:00Z")

    fun reading(account: String, provider: String, kind: String, fraction: Double, resetsInMinutes: Long? = null, group: String? = null) =
        SyncReading(
            accountId = account.lowercase().replace(' ', '-'),
            accountName = account,
            provider = provider,
            kind = kind,
            group = group,
            fraction = fraction,
            capturedAt = NOW,
            resetsAt = resetsInMinutes?.let { NOW.plus(Duration.ofMinutes(it)) },
        )

    fun agent(id: String, state: String, title: String = "Task $id", updatedAt: Instant = NOW) = SyncAgent(id, title, state, updatedAt)

    fun snapshot(readings: List<SyncReading> = defaultReadings, agents: List<SyncAgent> = emptyList()) =
        SyncSnapshot(version = 1, generatedAt = NOW, readings = readings, agents = agents)

    val defaultReadings = listOf(
        reading("Claude Work", "claude", "session5h", 0.82, 72),
        reading("Claude Work", "claude", "weekly", 0.91),
        reading("Codex", "codex", "session5h", 0.40, 200),
        reading("Antigravity", "antigravity", "modelGroup", 0.99, group = "Gemini Pro"),
    )

    fun data(snapshot: SyncSnapshot = snapshot(), fetchedAt: Instant = NOW) = SyncData(snapshot, fetchedAt)
}

/** Plain English for the mapping tests. */
object TestSyncStrings : SyncStrings {
    override val connectingTitle = "Connecting to your Mac"
    override val connectingHint = "One moment"
    override val connectingDescription = "AI usage. Connecting to your Mac."
    override val pairAgainTitle = "Pair again"
    override val pairAgainHint = "Mac forgot this phone"
    override val pairAgainDescription = "AI usage. Your Mac no longer recognises this phone. Pair again to see your limits."
    override val pairButton = "Pair again"
    override val unreachableTitle = "Mac not on this network"
    override val unreachableHint = "Retrying"
    override val unreachableDescription = "AI usage. Your Mac is not on this network. Ufuq keeps trying."
    override fun staleTrailing(age: Duration) = "Offline"
    override fun staleDescription(usageDescription: String, age: Duration) =
        "$usageDescription. Mac not on this network. Updated ${age.toMinutes()} minutes ago."
    override fun problemDescription(reason: String) = "Mac sync problem: $reason."
    override val agentWorking = "Working"
    override val agentNeedsInput = "Needs input"
    override fun agentWorkingLabel(title: String) = "Agent task running on your Mac: $title"
    override fun agentNeedsInputLabel(title: String) = "Agent needs input on your Mac: $title"
    override val agentNeedsInputPeekTitle = "Claude needs input"
    override val agentDonePeekTitle = "Task done"
}
