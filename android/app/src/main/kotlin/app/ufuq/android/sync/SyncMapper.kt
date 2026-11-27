package app.ufuq.android.sync

import app.ufuq.android.island.AiUsageSample
import app.ufuq.android.island.ButtonAction
import app.ufuq.android.island.IslandIcon
import app.ufuq.android.island.IslandPageId
import app.ufuq.android.island.IslandPageModel
import app.ufuq.android.island.IslandPages
import app.ufuq.android.island.IslandStrings
import app.ufuq.android.island.SliderModel
import app.ufuq.core.ActivitySource
import app.ufuq.core.LiveActivity
import app.ufuq.core.PeekEvent
import app.ufuq.core.UsageProvider
import app.ufuq.core.UsageThresholds
import app.ufuq.core.UsageWindowKind
import app.ufuq.core.prayer.PrayerFormat
import app.ufuq.core.sync.SyncAgent
import app.ufuq.core.sync.SyncAgentState
import app.ufuq.core.sync.SyncEvent
import app.ufuq.core.sync.SyncSnapshot
import java.time.Duration
import java.time.Instant

/** Texts the sync mapping needs; the app's come from resources, the tests' are plain English. */
interface SyncStrings {
    val connectingTitle: String
    val connectingHint: String
    val connectingDescription: String
    val pairAgainTitle: String
    val pairAgainHint: String
    val pairAgainDescription: String
    val pairButton: String
    val unreachableTitle: String
    val unreachableHint: String
    val unreachableDescription: String

    /** "Offline", the short stale marker inside the slider (the age is in the description). */
    fun staleTrailing(age: Duration): String

    /** "Mac not on this network. Updated 5 minutes ago." for TalkBack. */
    fun staleDescription(usageDescription: String, age: Duration): String
    fun problemDescription(reason: String): String
    val agentWorking: String
    val agentNeedsInput: String
    fun agentWorkingLabel(title: String): String
    fun agentNeedsInputLabel(title: String): String
    val agentNeedsInputPeekTitle: String
    val agentDonePeekTitle: String
}

/** The reading that page B and the pill show: the worst 5-hour session across Claude and Codex accounts. */
data class UsageHeadline(
    val label: String,
    val fraction: Double,
    val resetsAt: Instant?,
    val provider: UsageProvider,
)

object SyncMapper {
    /**
     * Worst session % across Claude accounts and Codex. Without any session reading it falls back
     * to the worst of their other windows; Antigravity (Beta source) is never the headline.
     */
    fun headline(snapshot: SyncSnapshot): UsageHeadline? {
        val candidates = snapshot.readings.mapNotNull { it.toDomain() }
            .filter { (account, _) -> account.provider == UsageProvider.CLAUDE || account.provider == UsageProvider.CODEX }
            .filter { (_, reading) -> reading.snapshot.fraction.isFinite() }
        val sessions = candidates.filter { it.second.kind == UsageWindowKind.Session5h }
        val (account, reading) = (sessions.ifEmpty { candidates }).maxByOrNull { it.second.snapshot.fraction } ?: return null
        val label = when (account.provider) {
            UsageProvider.CLAUDE -> "Claude"
            UsageProvider.CODEX -> "Codex"
            UsageProvider.ANTIGRAVITY -> "Antigravity"
        }
        return UsageHeadline(label, reading.snapshot.fraction.coerceIn(0.0, 1.0), reading.snapshot.resetsAt, account.provider)
    }

    fun sample(headline: UsageHeadline, now: Instant): AiUsageSample =
        AiUsageSample(headline.label, headline.fraction, headline.resetsAt?.let { Duration.between(now, it).coerceAtLeast(Duration.ZERO) })

    /** Page B for every link state. */
    fun pageB(
        state: SyncState,
        now: Instant,
        s: IslandStrings,
        sync: SyncStrings,
        thresholds: UsageThresholds = UsageThresholds.DEFAULT,
    ): IslandPageModel {
        val headline = state.dataOrNull?.snapshot?.let(::headline)
        return when (state) {
            SyncState.Unpaired -> IslandPages.aiUsage(null, s, thresholds)
            SyncState.PairAgain -> message(sync.pairAgainTitle, sync.pairAgainHint, sync.pairAgainDescription, sync.pairButton, ButtonAction.PAIR_MAC)
            is SyncState.Connecting ->
                if (headline == null) message(sync.connectingTitle, sync.connectingHint, sync.connectingDescription, s.openApp, ButtonAction.OPEN_APP)
                else IslandPages.aiUsage(sample(headline, now), s, thresholds)
            is SyncState.Live ->
                if (headline == null) message(sync.connectingTitle, s.pairHint, s.pairDescription, s.openApp, ButtonAction.OPEN_APP)
                else IslandPages.aiUsage(sample(headline, now), s, thresholds)
            is SyncState.Unreachable -> {
                val data = state.data
                if (headline == null || data == null) {
                    message(sync.unreachableTitle, sync.unreachableHint, sync.unreachableDescription, s.refreshUsage, ButtonAction.REFRESH)
                } else {
                    val age = Duration.between(data.fetchedAt, now).coerceAtLeast(Duration.ZERO)
                    val fresh = IslandPages.aiUsage(sample(headline, now), s, thresholds)
                    fresh.copy(
                        slider = fresh.slider.copy(
                            trailing = sync.staleTrailing(age),
                            description = sync.staleDescription(fresh.slider.description, age),
                        ),
                    )
                }
            }
            is SyncState.Problem -> {
                if (headline == null) {
                    message(sync.unreachableTitle, state.reason, sync.problemDescription(state.reason), s.refreshUsage, ButtonAction.REFRESH)
                } else {
                    val fresh = IslandPages.aiUsage(sample(headline, now), s, thresholds)
                    fresh.copy(slider = fresh.slider.copy(trailing = state.reason, description = "${fresh.slider.description}. ${sync.problemDescription(state.reason)}"))
                }
            }
        }
    }

    /** Swaps page B in a page list for the sync-driven one. */
    fun withPageB(pages: List<IslandPageModel>, state: SyncState, now: Instant, s: IslandStrings, sync: SyncStrings): List<IslandPageModel> =
        pages.map { if (it.id == IslandPageId.AI_USAGE) pageB(state, now, s, sync) else it }

    private fun message(title: String, hint: String, description: String, buttonLabel: String, action: ButtonAction) = IslandPageModel(
        id = IslandPageId.AI_USAGE,
        slider = SliderModel(0f, title, hint, description = description, stateText = hint),
        buttonIcon = if (action == ButtonAction.REFRESH) IslandIcon.REFRESH else IslandIcon.PHONE,
        buttonLabel = buttonLabel,
        buttonAction = action,
    )

    /** The collapsed right-wing activity: worst session %, hidden when there is nothing fresh to say. */
    fun usageActivity(state: SyncState, now: Instant, s: IslandStrings): LiveActivity? {
        val data = state.dataOrNull ?: return null
        if (state is SyncState.Unreachable && Duration.between(data.fetchedAt, now) > STALE_PILL_LIMIT) return null
        val headline = headline(data.snapshot) ?: return null
        val percent = (headline.fraction * 100).toInt()
        val resets = headline.resetsAt?.let { Duration.between(now, it).coerceAtLeast(Duration.ZERO) }
        return LiveActivity(
            id = "sync-usage",
            moduleId = USAGE_MODULE_ID,
            source = ActivitySource.AI_USAGE,
            text = s.percent(percent),
            accessibilityLabel = s.usageDescription(headline.label, percent, resets?.let { PrayerFormat.spoken(it) }),
            deadline = headline.resetsAt,
            usageFraction = headline.fraction,
        )
    }

    /** An agent activity while a task runs; an alert while one needs input. Waiting beats running. */
    fun agentActivity(state: SyncState, now: Instant, sync: SyncStrings): LiveActivity? {
        val data = state.dataOrNull ?: return null
        if (state is SyncState.Unreachable) return null
        val agents = data.snapshot.agents
        val waiting = agents.filter { it.agentState == SyncAgentState.WAITING }.maxByOrNull { it.updatedAt }
        val running = agents.filter { it.agentState == SyncAgentState.RUNNING }.maxByOrNull { it.updatedAt }
        return when {
            waiting != null -> LiveActivity("sync-agent", AGENT_MODULE_ID, ActivitySource.AGENT, sync.agentNeedsInput, sync.agentNeedsInputLabel(waiting.title), isAlert = true)
            running != null -> LiveActivity("sync-agent", AGENT_MODULE_ID, ActivitySource.AGENT, sync.agentWorking, sync.agentWorkingLabel(running.title))
            else -> null
        }
    }

    /** A Mac peek as a phone peek. Old events (the log replays up to 200 on first contact) are dropped. */
    fun peek(event: SyncEvent, now: Instant): PeekEvent? {
        if (Duration.between(event.createdAt, now) > MAX_EVENT_AGE) return null
        return PeekEvent(
            id = "sync-${event.id}",
            moduleId = if (event.moduleId.startsWith("agent")) AGENT_MODULE_ID else USAGE_MODULE_ID,
            title = event.title,
            message = event.message,
            priority = if (event.isCritical) PeekEvent.Priority.CRITICAL else PeekEvent.Priority.NORMAL,
        )
    }

    /**
     * Peeks for agents that changed state between two snapshots: "needs input" is critical, a
     * finished task is normal. Nothing fires on the first snapshot ([previous] null).
     */
    fun agentPeeks(previous: List<SyncAgent>?, current: List<SyncAgent>, sync: SyncStrings): List<PeekEvent> {
        if (previous == null) return emptyList()
        val before = previous.associateBy { it.id }
        return current.mapNotNull { agent ->
            val was = before[agent.id]?.agentState
            val now = agent.agentState
            when {
                now == SyncAgentState.WAITING && was != SyncAgentState.WAITING ->
                    PeekEvent("sync-agent-${agent.id}-waiting-${agent.updatedAt.epochSecond}", AGENT_MODULE_ID, sync.agentNeedsInputPeekTitle, agent.title, PeekEvent.Priority.CRITICAL)
                now == SyncAgentState.DONE && was != null && was != SyncAgentState.DONE ->
                    PeekEvent("sync-agent-${agent.id}-done-${agent.updatedAt.epochSecond}", AGENT_MODULE_ID, sync.agentDonePeekTitle, agent.title)
                else -> null
            }
        }
    }

    const val USAGE_MODULE_ID = "sync-usage"
    const val AGENT_MODULE_ID = "sync-agent"
    private val MAX_EVENT_AGE: Duration = Duration.ofMinutes(2)
    private val STALE_PILL_LIMIT: Duration = Duration.ofMinutes(15)
}
