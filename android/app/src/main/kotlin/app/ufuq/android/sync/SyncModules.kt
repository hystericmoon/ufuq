package app.ufuq.android.sync

import app.ufuq.android.island.IslandStrings
import app.ufuq.core.LiveActivity
import app.ufuq.core.ModuleStatus
import app.ufuq.core.PeekEvent
import app.ufuq.core.UfuqModule
import java.time.Instant
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.filter

private fun SyncState.moduleStatus(): ModuleStatus = when (this) {
    SyncState.Unpaired -> ModuleStatus.Unavailable("Not paired")
    SyncState.PairAgain -> ModuleStatus.Unavailable("Pair again")
    is SyncState.Connecting -> ModuleStatus.Ok
    is SyncState.Live -> ModuleStatus.Ok
    is SyncState.Unreachable -> data?.let { ModuleStatus.Stale(it.fetchedAt) } ?: ModuleStatus.Unavailable("Mac not on this network")
    is SyncState.Problem -> ModuleStatus.Unavailable(reason)
}

/** The Mac's AI usage as a right-wing activity (worst 5-hour session across Claude and Codex). */
class SyncUsageModule(private val sync: SyncController, private val strings: IslandStrings) : UfuqModule {
    override val id = SyncMapper.USAGE_MODULE_ID
    override val title = "AI usage (Mac)"
    override var isEnabled = true
    override val status: ModuleStatus get() = sync.state.value.moduleStatus()

    override fun collapsedActivity(now: Instant): LiveActivity? = SyncMapper.usageActivity(sync.state.value, now, strings)

    override fun accessibilitySummary(): String =
        collapsedActivity(Instant.now())?.accessibilityLabel ?: "AI usage from your Mac is not available"
}

/** Agent status from the Mac: an activity while a task runs, plus every peek the Mac link produces. */
class SyncAgentModule(private val sync: SyncController, private val strings: SyncStrings) : UfuqModule {
    override val id = SyncMapper.AGENT_MODULE_ID
    override val title = "Agent status (Mac)"
    override var isEnabled = true
    override val status: ModuleStatus get() = sync.state.value.moduleStatus()

    override fun collapsedActivity(now: Instant): LiveActivity? = SyncMapper.agentActivity(sync.state.value, now, strings)

    /** The Mac's peeks (usage alerts included) and agent changes; the island's PeekQueue shows them. */
    override fun peekEvents(): Flow<PeekEvent> = sync.peeks

    override fun accessibilitySummary(): String =
        collapsedActivity(Instant.now())?.accessibilityLabel ?: "No agent task is running on your Mac"
}
