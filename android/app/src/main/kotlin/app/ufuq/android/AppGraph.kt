package app.ufuq.android

import android.content.Context
import app.ufuq.android.live.LiveUpdateController
import app.ufuq.android.island.IslandController
import app.ufuq.android.settings.AppSettings
import app.ufuq.android.settings.SettingsRepository
import android.net.ConnectivityManager
import app.ufuq.android.island.AndroidIslandStrings
import app.ufuq.android.sync.AndroidSyncStrings
import app.ufuq.android.sync.NsdMacLocator
import app.ufuq.android.sync.PairingStore
import app.ufuq.android.sync.SyncAgentModule
import app.ufuq.android.sync.SyncController
import app.ufuq.android.sync.SyncUsageModule
import app.ufuq.core.ActivityArbiter
import app.ufuq.core.ModuleRegistry
import app.ufuq.core.PeekQueue
import app.ufuq.core.prayer.PrayerModule
import java.time.Duration
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/** Manual wiring (no Hilt): one instance per process, built lazily by [UfuqApp]. */
class AppGraph(val context: Context) {
    val settings = SettingsRepository(context)
    val prayer = PrayerModule()
    val registry = ModuleRegistry().also { it.register(prayer) }
    val arbiter = ActivityArbiter()
    val peeks = PeekQueue()
    val island = IslandController()
    val liveUpdate = LiveUpdateController(context, this)

    // Mac to phone sync (A6): the pairing, the polling loop and the two modules that feed the island.
    val pairings = PairingStore(context)
    val syncStrings = AndroidSyncStrings(context)
    val sync = SyncController(
        source = pairings,
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
        strings = syncStrings,
        locator = NsdMacLocator(context),
        online = {
            val cm = context.getSystemService(ConnectivityManager::class.java)
            cm == null || cm.activeNetwork != null
        },
    )

    init {
        registry.register(SyncUsageModule(sync, AndroidIslandStrings(context)))
        registry.register(SyncAgentModule(sync, syncStrings))
    }

    /** Points the prayer module at the user's place, method and peek lead time. */
    fun apply(s: AppSettings) {
        prayer.location = s.location
        prayer.settings = s.calculation
        prayer.preAdhanLead = Duration.ofMinutes(s.adhanLeadMinutes.toLong())
    }

    suspend fun currentSettings(): AppSettings = settings.current().also(::apply)
}
