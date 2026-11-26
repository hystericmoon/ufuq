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
 * Posts the Live Update notification and wakes up again only at the next prayer boundary (one
 * inexact alarm, no polling). The chronometer counts down on its own between boundaries.
 */
class LiveUpdateController(private val context: Context, private val graph: AppGraph) {

    /** Posts or removes the notification for [settings] and schedules the next boundary. */
    fun refresh(settings: AppSettings, now: Instant = Instant.now()) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        val pending = alarmIntent()
        if (!settings.liveUpdateEnabled) {
            NotificationManagerCompat.from(context).cancel(LiveUpdate.NOTIFICATION_ID)
            alarms.cancel(pending)
            return
        }
        graph.apply(settings)
        val snapshot = graph.prayer.snapshot(now) ?: run {
            NotificationManagerCompat.from(context).cancel(LiveUpdate.NOTIFICATION_ID)
            return
        }
        val progress = PrayerProgress.at(now, graph.prayer) ?: return
        LiveUpdate.ensureChannel(context)
        if (NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            try {
                NotificationManagerCompat.from(context).notify(
                    LiveUpdate.NOTIFICATION_ID,
                    LiveUpdate.build(context, LiveUpdateContent(progress, snapshot.zone)),
                )
            } catch (_: SecurityException) {
                // Permission revoked between the check and the post.
            }
        }
        val at = PrayerSnapshots.nextRefresh(now, snapshot)
        // Inexact on purpose: no exact-alarm permission, and a minute late is fine for a countdown.
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at.toEpochMilli(), pending)
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
