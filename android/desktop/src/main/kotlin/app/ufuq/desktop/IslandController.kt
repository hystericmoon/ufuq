package app.ufuq.desktop

import app.ufuq.core.ActivityArbiter
import app.ufuq.core.PeekEvent
import app.ufuq.core.PeekQueue
import app.ufuq.core.prayer.PrayerModule
import app.ufuq.desktop.island.AiUsageSample
import app.ufuq.desktop.island.ButtonAction
import app.ufuq.desktop.island.EnglishIslandStrings
import app.ufuq.desktop.island.IslandPageModel
import app.ufuq.desktop.island.IslandPages
import app.ufuq.desktop.island.IslandStrings
import app.ufuq.desktop.island.PillMapper
import app.ufuq.desktop.island.PillModel
import app.ufuq.desktop.island.PrayerProgress
import app.ufuq.desktop.settings.DesktopSettings
import app.ufuq.desktop.usage.UsageAlerts
import app.ufuq.desktop.usage.UsageMapper
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant

/** Everything the island window draws. */
data class IslandViewState(
    val mode: NotchState = NotchState.Collapsed,
    val pill: PillModel? = null,
    val pages: List<IslandPageModel> = emptyList(),
)

/**
 * Glue between the modules (:core), the pure [NotchStateMachine] and the window. It owns no
 * threads: [run] is a suspend loop the shell launches, and every action may be called from any
 * thread (the hotkey comes from JNativeHook's). A module that throws leaves its part empty; it never crashes the app.
 */
class IslandController(
    initial: DesktopSettings,
    private val loadUsage: suspend (DesktopSettings, Instant) -> List<AiUsageSample>,
    private val clock: () -> Instant = Instant::now,
    private val strings: IslandStrings = EnglishIslandStrings,
    /** Called before the island expands (remember the window that has focus) and after it closes (give focus back). */
    private val beforeOpen: () -> Unit = {},
    private val afterClose: () -> Unit = {},
    private val onOpenSettings: () -> Unit = {},
) {
    private val lock = Any()
    private val machine = NotchStateMachine()
    private val peeks = PeekQueue()
    private val arbiter = ActivityArbiter()
    private var settings = initial
    private val prayer = PrayerModule(initial.location, initial.calculation, clock = clock)
    private var usage: List<AiUsageSample> = emptyList()
    private var usageDue = true

    private val _state = MutableStateFlow(IslandViewState())
    val state: StateFlow<IslandViewState> = _state.asStateFlow()

    fun updateSettings(new: DesktopSettings) = synchronized(lock) {
        settings = new
        prayer.location = new.location
        prayer.settings = new.calculation
        usageDue = true
        publish(clock())
    }

    // Actions

    fun toggleWithHotkey() = synchronized(lock) {
        if (machine.isExpanded) {
            machine.toggleWithHotkey()
            afterClose()
        } else {
            open(ExpandOrigin.HOTKEY)
        }
        publish(clock())
    }

    fun pillClicked() = synchronized(lock) {
        if (!machine.isExpanded) open(ExpandOrigin.CLICK)
        publish(clock())
    }

    fun escape() = synchronized(lock) {
        val now = clock()
        when (machine.escape()) {
            NotchStateMachine.EscapeResult.COLLAPSED -> afterClose()
            NotchStateMachine.EscapeResult.DISMISSED_PEEK -> peeks.dismissCurrent(now)
            NotchStateMachine.EscapeResult.IGNORED -> Unit
        }
        publish(now)
    }

    fun peekDismiss() = synchronized(lock) {
        val now = clock()
        peeks.dismissCurrent(now)
        publish(now)
    }

    fun peekHold(hold: Boolean) = synchronized(lock) { peeks.setHovering(hold, clock()) }

    fun onAction(action: ButtonAction) {
        when (action) {
            ButtonAction.OPEN_SETTINGS -> onOpenSettings()
            ButtonAction.REFRESH -> synchronized(lock) { usageDue = true }
        }
    }

    fun enqueuePeek(event: PeekEvent) = synchronized(lock) {
        val now = clock()
        peeks.enqueue(event, now)
        publish(now)
    }

    private fun open(origin: ExpandOrigin) {
        beforeOpen()
        machine.open(origin)
    }

    // Time

    /** Recomputes everything for [now]; call about once a second. */
    fun tick(now: Instant = clock()) = synchronized(lock) { publish(now) }

    private fun publish(now: Instant) {
        peeks.tick(now)
        machine.setPeek(peeks.current)

        val activities = listOfNotNull(
            runCatching { prayer.collapsedActivity(now) }.getOrNull(),
            UsageMapper.activity(usage, strings),
        )
        val pill = PillMapper.from(arbiter.layout(activities, now), now)
        val progress = runCatching { PrayerProgress.at(now, prayer) }.getOrNull()
        val pages = IslandPages.all(progress, usage, strings)
        _state.value = IslandViewState(machine.state, pill, pages)
    }

    /** Reads the usage logs and queues peeks for new alerts. */
    suspend fun refreshUsage() {
        val (current, now) = synchronized(lock) { settings to clock() }
        val loaded = try {
            loadUsage(current, now)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emptyList()
        }
        synchronized(lock) {
            UsageAlerts.peeks(usage, loaded, now, strings).forEach { peeks.enqueue(it, now) }
            usage = loaded
            usageDue = false
            publish(now)
        }
    }

    /** The shell's loop: prayer peeks, a tick every second, usage every [usageInterval] or on demand. */
    suspend fun run(usageInterval: Duration = Duration.ofMinutes(1)) = coroutineScope {
        launch { prayer.peekEvents().collect { enqueuePeek(it) } }
        var lastUsage: Instant? = null
        while (true) {
            val now = clock()
            val due = synchronized(lock) { usageDue } || lastUsage?.let { Duration.between(it, now) >= usageInterval } != false
            if (due) {
                lastUsage = now
                refreshUsage()
            }
            tick(now)
            delay(1000)
        }
    }
}
