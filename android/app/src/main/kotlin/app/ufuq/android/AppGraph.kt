package app.ufuq.android

import android.content.Context
import app.ufuq.android.activities.ActivitiesListenerAdapter
import app.ufuq.android.activities.AndroidActivityStrings
import app.ufuq.android.activities.OtherAppsModule
import app.ufuq.android.live.LiveUpdateController
import app.ufuq.android.island.IslandController
import app.ufuq.android.media.MediaModule
import app.ufuq.android.media.MediaRepository
import app.ufuq.android.settings.AppSettings
import app.ufuq.android.settings.SettingsRepository
import app.ufuq.android.live.LiveUpdateStrategy
import app.ufuq.android.ramadan.RamadanLiveStrategy
import app.ufuq.android.silence.SilenceController
import app.ufuq.android.travel.TravelController
import app.ufuq.core.ActivityArbiter
import app.ufuq.core.ModuleRegistry
import app.ufuq.core.PeekQueue
import app.ufuq.core.prayer.PrayerModule
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import java.time.Duration

/** Manual wiring (no Hilt): one instance per process, built lazily by [UfuqApp]. */
class AppGraph(val context: Context) {
    val settings = SettingsRepository(context)
    val prayer = PrayerModule()
    /** A7: the notification listener calls this adapter (in memory only). */
    val activities = ActivitiesListenerAdapter(context).also { adapter ->
        app.ufuq.android.listener.ListenerRegistry.register(object : app.ufuq.android.listener.ListenerCallback {
            override fun onConnected(service: android.service.notification.NotificationListenerService) =
                adapter.onListenerConnected(runCatching { service.activeNotifications }.getOrNull())
            override fun onDisconnected() = adapter.onListenerDisconnected()
            override fun onPosted(sbn: android.service.notification.StatusBarNotification) = adapter.onNotificationPosted(sbn)
            override fun onRemoved(sbn: android.service.notification.StatusBarNotification) = adapter.onNotificationRemoved(sbn)
        })
    }
    val otherApps = OtherAppsModule(AndroidActivityStrings(context), context.packageName)
    val media = MediaRepository(context).also { it.start() }
    val registry = ModuleRegistry().also {
        it.register(prayer)
        it.register(MediaModule(media))
        it.register(otherApps)
    }
    val arbiter = ActivityArbiter()
    val peeks = PeekQueue()
    val island = IslandController()
    val liveUpdate = LiveUpdateController(context, this)

    // Prayer extras (A4).
    val silence = SilenceController(context) { s, now -> apply(s); prayer.snapshot(now)?.next?.time }
    val travel = TravelController(context, settings)
    val liveStrategies: List<LiveUpdateStrategy> = listOf(RamadanLiveStrategy { prayer.snapshot(it) })

    /** Points the prayer module at the user's place, method and peek lead time. */
    fun apply(s: AppSettings) {
        prayer.location = s.location
        prayer.settings = s.calculation
        prayer.preAdhanLead = Duration.ofMinutes(s.adhanLeadMinutes.toLong())
    }

    /** A7: keeps the other-apps module in step with the listener and the allow list. */
    fun bindOtherApps(scope: kotlinx.coroutines.CoroutineScope) {
        scope.launch {
            combine(activities.ongoing, settings.settings) { list, s -> Triple(list, s.otherAppsEnabled, s.otherAppsAllowed) }
                .collect { (list, enabled, allowed) -> otherApps.update(list, enabled, allowed) }
        }
    }

    suspend fun currentSettings(): AppSettings = settings.current().also(::apply)
}
