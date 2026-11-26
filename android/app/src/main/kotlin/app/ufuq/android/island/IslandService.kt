package app.ufuq.android.island

import android.app.Notification
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
import android.provider.Settings
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityManager
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
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
    private var startedAt: Instant = Instant.now()
    private var lastPeekId: String? = null
    private var muted = false

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
            // The window is as wide as the screen while open and wraps the pill otherwise.
            s.launch { snapshotFlow { expanded || peek != null }.collect { applyLayout() } }
            s.launch { graph.island.expandRequests.collect { expand() } }
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
        pages = IslandPages.all(progress, muted, usage = null, strings = strings)
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
                    Box(if (open) Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 8.dp) else Modifier) {
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
            ButtonAction.REFRESH -> scope?.launch { tick() }
        }
    }

    private fun startInForeground() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, getString(R.string.channel_island), NotificationManager.IMPORTANCE_MIN),
        )
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(ContextCompat.getColor(this, R.color.notification_accent))
            .setContentTitle(getString(R.string.island_notification_title))
            .setContentText(getString(R.string.island_notification_text))
            .setContentIntent(open)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        const val ACTION_EXPAND = "app.ufuq.android.action.EXPAND_ISLAND"
        private const val CHANNEL = "island"
        private const val NOTIFICATION_ID = 101
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
