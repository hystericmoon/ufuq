package app.ufuq.android.island

import android.app.Notification
import androidx.core.app.ServiceCompat
import app.ufuq.android.live.LiveUpdate
import app.ufuq.android.live.LiveUpdateContent
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.provider.Settings
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityManager
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.statusBars
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.ui.unit.dp
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.lifecycle.setViewTreeViewModelStoreOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import app.ufuq.android.R
import app.ufuq.android.graph
import app.ufuq.android.prayer.PrayerProgress
import app.ufuq.android.sync.SyncMapper
import app.ufuq.android.sync.SyncState
import app.ufuq.android.ui.MainActivity
import app.ufuq.core.PeekEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant

/**
 * The island: a foreground service that draws a Compose overlay at the camera cutout. Collapsed it
 * is a pill (prayer left, AI or the rotating activity right, from [app.ufuq.core.ActivityArbiter]);
 * a tap expands it into the three-page island; peeks from [app.ufuq.core.PeekQueue] replace the pill
 * for 6 s. Off by default: it needs "Display over other apps" and the user's switch in Settings.
 * The Live Update chip stays the accessible, system-owned way to see the same prayer.
 */
class IslandService : Service(), LifecycleOwner, SavedStateRegistryOwner, ViewModelStoreOwner {
    private val registry = LifecycleRegistry(this)
    private val savedState = SavedStateRegistryController.create(this)
    private val store = ViewModelStore()
    private var scope: CoroutineScope? = null
    private var collapseJob: Job? = null
    private var tickJob: Job? = null
    private var view: View? = null
    private var params: WindowManager.LayoutParams? = null

    private var pill by mutableStateOf<PillModel?>(null)
    private var pages by mutableStateOf<List<IslandPageModel>>(emptyList())
    private var peek by mutableStateOf<PeekEvent?>(null)
    private var expanded by mutableStateOf(false)
    private var gapDp = 0
    private var placement = IslandGeometry.Placement(IslandGeometry.PILL_PADDING_DP, IslandGeometry.DEFAULT_PILL_DP)
    private var startedAt: Instant = Instant.now()
    private var lastPeekId: String? = null
    private var muted = false
    private var syncHeld = false
    private var lastMinuteKey: String? = null

    private val strings by lazy { AndroidIslandStrings(this) }

    override val lifecycle: Lifecycle get() = registry
    override val savedStateRegistry: SavedStateRegistry get() = savedState.savedStateRegistry
    override val viewModelStore: ViewModelStore get() = store

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        savedState.performAttach()
        savedState.performRestore(null)
        registry.currentState = Lifecycle.State.CREATED
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startInForeground()
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (view == null) {
            registry.currentState = Lifecycle.State.RESUMED
            addOverlay()
            startedAt = Instant.now()
            val s = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate).also { scope = it }
            val graph = graph
            graph.island.isShowing = view != null
            // The Mac link polls only while the island or the app is visible, and not at all when unpaired.
            graph.sync.acquire()
            syncHeld = true
            s.launch { graph.sync.state.collect { tick() } }
            // The window is as wide as the screen while open and wraps the pill otherwise.
            s.launch { snapshotFlow { expanded || peek != null }.collect { applyLayout() } }
            s.launch { graph.island.expandRequests.collect { expand() } }
            // A track change or play/pause updates the page and the pill at once.
            s.launch { graph.media.state.collect { tick() } }
            s.launch {
                // Switching the island off in Settings stops the service.
                graph.settings.settings.collect { if (!it.overlayEnabled) stopSelf() }
            }
            // One flow per module's peeks; the queue decides what shows and when.
            for (module in graph.registry.enabledModules) {
                s.launch {
                    module.peekEvents().collect { event ->
                        // No pop-up just because the island was switched on or the phone restarted.
                        if (event.priority == PeekEvent.Priority.NORMAL && Duration.between(startedAt, Instant.now()) < QUIET_START) return@collect
                        graph.peeks.enqueue(event, Instant.now())
                        tick()
                    }
                }
            }
            tickJob = s.launch {
                while (true) {
                    val soon = tick()
                    delay(if (expanded || peek != null || soon) 1_000L else 15_000L)
                }
            }
        }
        if (intent?.action == ACTION_EXPAND) expand()
        return START_STICKY
    }

    override fun onDestroy() {
        graph.island.isShowing = false
        // Keep the card: the Live Update setting decides whether it stays (reposted without the
        // per-minute countdown) or goes.
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_DETACH)
        val app = graph
        CoroutineScope(SupervisorJob() + Dispatchers.Default).launch { app.liveUpdate.post(app.currentSettings()) }
        if (syncHeld) graph.sync.release()
        syncHeld = false
        scope?.cancel()
        scope = null
        removeOverlay()
        registry.currentState = Lifecycle.State.DESTROYED
        store.clear()
        super.onDestroy()
    }

    /** Recomputes what the island shows. Returns true when the next prayer is under 10 minutes away (so it ticks each second). */
    private suspend fun tick(): Boolean {
        val graph = graph
        val settings = graph.currentSettings()
        muted = settings.adhanMuted
        val now = Instant.now()
        graph.peeks.tick(now)
        pill = PillMapper.from(graph.arbiter.layout(graph.registry.activities(now), now), now)
        val progress = PrayerProgress.at(now, graph.prayer)
        // The notification's countdown is in whole minutes: repost it when that text changes.
        val minuteKey = progress?.let { "${it.name}|${LiveUpdateContent.inWords(it.remaining)}" }
        if (minuteKey != lastMinuteKey) {
            lastMinuteKey = minuteKey
            graph.liveUpdate.post(settings, now)
        }
        // Page B shows the Mac's usage (or its pairing / offline state) from the sync link.
        val syncState = graph.sync.state.value
        pages = IslandPages.visible(SyncMapper.withPageB(
            IslandPages.all(
                progress, muted, usage = null, strings = strings,
                mediaState = graph.media.state.value, mediaAccess = graph.media.accessGranted(), elapsedNowMs = SystemClock.elapsedRealtime(),
            ),
            syncState, now, strings, graph.syncStrings,
        ), unpaired = syncState == SyncState.Unpaired) + listOfNotNull(graph.otherApps.page(now))
        val current = graph.peeks.current
        if (current?.id != lastPeekId) {
            lastPeekId = current?.id
            if (current != null) onPeekShown(current)
        }
        peek = current
        return progress?.remaining?.let { it < Duration.ofMinutes(10) } == true
    }

    private fun onPeekShown(event: PeekEvent) {
        val v = view ?: return
        // The peek is also a live region; the announcement makes sure TalkBack speaks it at once.
        @Suppress("DEPRECATION")
        v.announceForAccessibility(event.announcement)
        if (event.priority == PeekEvent.Priority.CRITICAL && !muted) v.performHapticFeedback(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.CONTEXT_CLICK)
    }

    private fun addOverlay() {
        val wm = getSystemService(WindowManager::class.java)
        gapDp = IslandGeometry.gapDp(cutoutWidthPx(wm), resources.displayMetrics.density)
        val hole = cutoutRect(wm)
        placement = IslandGeometry.placement(hole?.top, hole?.bottom, resources.displayMetrics.density)
        val composeView = ComposeView(this).apply {
            setViewTreeLifecycleOwner(this@IslandService)
            setViewTreeSavedStateRegistryOwner(this@IslandService)
            setViewTreeViewModelStoreOwner(this@IslandService)
            setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnDetachedFromWindow)
            setContent {
                ProvideIslandMotion {
                    val mode = when {
                        expanded -> IslandMode.Expanded
                        peek != null -> IslandMode.Peek(peek!!)
                        else -> IslandMode.Collapsed
                    }
                    val open = mode != IslandMode.Collapsed
                    // The open card sits under the status bar (option C); a peek keeps hugging the top edge.
                    val top = if (mode == IslandMode.Expanded) maxOf(WindowInsets.statusBars.asPaddingValues().calculateTopPadding(), (placement.topDp + placement.heightDp).dp) + 6.dp else 8.dp
                    Box(if (open) Modifier.fillMaxWidth().padding(start = 10.dp, end = 10.dp, top = top) else Modifier) {
                        IslandContent(
                            mode = mode,
                            pill = pill,
                            pages = pages,
                            gapDp = gapDp,
                            onPillClick = ::expand,
                            onAction = ::onAction,
                            onClose = ::collapse,
                            onPeekDismiss = { graph.peeks.dismissCurrent(Instant.now()); peek = graph.peeks.current },
                            onPeekHold = { graph.peeks.setHovering(it, Instant.now()) },
                            onInteract = ::armCollapse,
                            onSeek = ::onSeek,
                            placement = placement,
                        )
                    }
                }
            }
        }
        val p = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            if (Build.VERSION.SDK_INT >= 30) {
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            } else if (Build.VERSION.SDK_INT >= 28) {
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
            title = getString(R.string.app_name)
        }
        params = p
        runCatching { wm.addView(composeView, p) }.onSuccess { view = composeView }.onFailure { stopSelf() }
    }

    private fun applyLayout() {
        val v = view ?: return
        val p = params ?: return
        val open = expanded || peek != null
        p.width = if (open) WindowManager.LayoutParams.MATCH_PARENT else WindowManager.LayoutParams.WRAP_CONTENT
        p.y = 0
        runCatching { getSystemService(WindowManager::class.java).updateViewLayout(v, p) }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        applyLayout()
    }

    private fun removeOverlay() {
        val v = view ?: return
        view = null
        runCatching { getSystemService(WindowManager::class.java).removeView(v) }
    }

    /** The camera cutout at the top edge; null before Android 11 or without one. */
    private fun cutoutRect(wm: WindowManager): android.graphics.Rect? =
        if (Build.VERSION.SDK_INT < 30) null else wm.currentWindowMetrics.windowInsets.displayCutout?.boundingRectTop?.takeIf { !it.isEmpty }

    /** Width of the camera cutout; null before Android 11 (the pill then keeps a default gap) or without one. */
    private fun cutoutWidthPx(wm: WindowManager): Int? =
        if (Build.VERSION.SDK_INT < 30) null else wm.currentWindowMetrics.windowInsets.displayCutout?.boundingRectTop?.width()?.takeIf { it > 0 }

    private fun expand() {
        expanded = true
        armCollapse()
        scope?.launch { tick() }
    }

    private fun collapse() {
        expanded = false
        collapseJob?.cancel()
    }

    /** Collapses 10 s after the last touch, unless a screen reader is on: those users need no timeout. */
    private fun armCollapse() {
        collapseJob?.cancel()
        val am = getSystemService(AccessibilityManager::class.java)
        if (am?.isTouchExplorationEnabled == true) return
        collapseJob = scope?.launch {
            delay(EXPANDED_SECONDS * 1000L)
            expanded = false
        }
    }

    private fun onAction(action: ButtonAction) {
        when (action) {
            ButtonAction.TOGGLE_MUTE -> scope?.launch {
                graph.settings.update { it.copy(adhanMuted = !it.adhanMuted) }
                tick()
            }
            ButtonAction.OPEN_APP -> {
                collapse()
                startActivity(
                    Intent(this, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
                )
            }
            ButtonAction.REFRESH -> {
                graph.sync.refreshNow()
                scope?.launch { tick() }
            }
            ButtonAction.OPEN_SOURCE -> {
                collapse()
                graph.otherApps.openCurrent()
            }
            ButtonAction.PLAY_PAUSE -> graph.media.togglePlayPause()
            ButtonAction.ALLOW_MEDIA_ACCESS -> {
                collapse()
                startActivity(
                    Intent(this, MainActivity::class.java).setAction(MainActivity.ACTION_ALLOW_MEDIA)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
                )
            }
            ButtonAction.PAIR_MAC -> {
                collapse()
                startActivity(
                    Intent(this, MainActivity::class.java)
                        .putExtra(MainActivity.EXTRA_OPEN_PAIRING, true)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
                )
            }
        }
    }

    /** A drag or TalkBack step on the media slider: [fraction] of the track. */
    private fun onSeek(fraction: Float) {
        val media = graph.media
        val duration = media.state.value?.takeIf { it.seekable }?.durationMs ?: return
        media.seekTo((fraction.coerceIn(0f, 1f) * duration).toLong())
        scope?.launch { tick() }
    }

    /**
     * The island's foreground notification is the next-prayer notification itself (one Ufuq
     * card). It starts from the prayer module as it stands; the first tick reposts it with the
     * user's settings applied.
     */
    private fun startInForeground() {
        LiveUpdate.ensureChannel(this)
        // The old separate "Island" channel (0.1.2 and earlier) is no longer used.
        getSystemService(NotificationManager::class.java).deleteNotificationChannel(OLD_CHANNEL)
        val notification: Notification = runCatching {
            val now = Instant.now()
            val zone = graph.prayer.snapshot(now)?.zone
            val progress = PrayerProgress.at(now, graph.prayer)
            if (zone != null && progress != null) LiveUpdate.build(this, LiveUpdateContent(progress, zone, ticking = true)) else null
        }.getOrNull() ?: LiveUpdate.fallback(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(LiveUpdate.NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(LiveUpdate.NOTIFICATION_ID, notification)
        }
    }

    companion object {
        const val ACTION_EXPAND = "app.ufuq.android.action.EXPAND_ISLAND"
        private const val OLD_CHANNEL = "island"
        private const val EXPANDED_SECONDS = 10
        private val QUIET_START: Duration = Duration.ofSeconds(20)

        /** Starts the island when [wanted] and the permission is granted, stops it otherwise. Safe to call often. */
        fun sync(context: Context, wanted: Boolean) {
            val intent = Intent(context, IslandService::class.java)
            if (wanted && Settings.canDrawOverlays(context)) {
                runCatching { ContextCompat.startForegroundService(context, intent) }
            } else {
                context.stopService(intent)
            }
        }

        /** Starts the island with the expanded card open (the Quick Settings tile). */
        fun expand(context: Context): Boolean {
            if (!Settings.canDrawOverlays(context)) return false
            return runCatching {
                ContextCompat.startForegroundService(context, Intent(context, IslandService::class.java).setAction(ACTION_EXPAND))
            }.isSuccess
        }
    }
}
