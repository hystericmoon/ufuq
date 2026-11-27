package app.ufuq.android.live

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat
import app.ufuq.android.AppGraph
import app.ufuq.android.graph
import app.ufuq.android.island.IslandService
import app.ufuq.android.prayer.PrayerProgress
import app.ufuq.android.settings.AppSettings
import app.ufuq.core.prayer.PrayerSnapshots
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.time.Instant

/**
 * Posts the next-prayer notification and wakes up again only at the next prayer boundary (one
 * inexact alarm, no polling). While the island runs, this same notification is the island
 * service's foreground notification (one Ufuq card, owner 27 Nov), and the service reposts it
 * every minute so its countdown in words stays right.
 */
class LiveUpdateController(private val context: Context, private val graph: AppGraph) {

    /** Posts or removes the notification for [settings] and schedules the next boundary. */
    fun refresh(settings: AppSettings, now: Instant = Instant.now()) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        // Prayer extras ride on every refresh (settings change, prayer boundary, boot); each is idempotent.
        graph.silence.onRefresh(settings, now)
        graph.travel.onRefresh(settings)
        val pending = alarmIntent()
        val snapshot = post(settings, now)
        if (!settings.liveUpdateEnabled || snapshot == null) {
            alarms.cancel(pending)
            return
        }
        val at = PrayerSnapshots.nextRefresh(now, snapshot)
        // Inexact on purpose: no exact-alarm permission, and a minute late is fine for a countdown.
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at.toEpochMilli(), pending)
    }

    /**
     * Posts (or removes) the notification only: no alarms, no prayer extras. The island service
     * calls it every minute. Returns the snapshot it showed, or null when nothing is shown.
     * While the island runs the notification stays even with the Live Update setting off,
     * because Android needs it to keep the island on screen.
     */
    fun post(settings: AppSettings, now: Instant = Instant.now()): app.ufuq.core.prayer.PrayerSnapshot? {
        val nm = NotificationManagerCompat.from(context)
        val island = graph.island.isShowing
        if (!settings.liveUpdateEnabled && !island) {
            nm.cancel(LiveUpdate.NOTIFICATION_ID)
            return null
        }
        graph.apply(settings)
        val snapshot = graph.prayer.snapshot(now)
        val progress = snapshot?.let { snap -> graph.liveStrategies.firstNotNullOfOrNull { it.progress(now, settings, snap) } }
            ?: PrayerProgress.at(now, graph.prayer)
        if (snapshot == null || progress == null) {
            // The island keeps its fallback notification; it cannot be removed while it runs.
            if (!island) nm.cancel(LiveUpdate.NOTIFICATION_ID)
            return null
        }
        LiveUpdate.ensureChannel(context)
        if (nm.areNotificationsEnabled()) {
            try {
                nm.notify(LiveUpdate.NOTIFICATION_ID, LiveUpdate.build(context, LiveUpdateContent(progress, snapshot.zone, ticking = island)))
            } catch (_: SecurityException) {
                // Permission revoked between the check and the post.
            }
        }
        return snapshot
    }

    private fun alarmIntent(): PendingIntent = PendingIntent.getBroadcast(
        context, 0, Intent(context, LiveUpdateReceiver::class.java),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
}

private val receiverScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

/** Runs [block] off the main thread while keeping the receiver alive until it is done. */
private fun BroadcastReceiver.async(context: Context, block: suspend (Context) -> Unit) {
    val app = context.applicationContext
    val pending = goAsync()
    receiverScope.launch {
        try {
            block(app)
        } finally {
            pending.finish()
        }
    }
}

/** Fires at each prayer boundary and redraws the chip. */
class LiveUpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = async(context) { app ->
        app.graph.liveUpdate.refresh(app.graph.currentSettings())
    }
}

/** Boot, clock and time-zone changes and app updates: redraw the chip and restart the island. */
class SystemEventsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == null) return
        async(context) { app ->
        val s = app.graph.currentSettings()
        app.graph.liveUpdate.refresh(s)
        IslandService.sync(app, s.overlayEnabled)
        }
    }
}
