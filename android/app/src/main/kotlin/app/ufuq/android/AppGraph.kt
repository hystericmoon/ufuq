package app.ufuq.android

import android.content.Context
import app.ufuq.android.live.LiveUpdateController
import app.ufuq.android.island.IslandController
import app.ufuq.android.settings.AppSettings
import app.ufuq.android.settings.SettingsRepository
import app.ufuq.core.ActivityArbiter
import app.ufuq.core.ModuleRegistry
import app.ufuq.core.PeekQueue
import app.ufuq.core.prayer.PrayerModule
import java.time.Duration

/** Manual wiring (no Hilt): one instance per process, built lazily by [UfuqApp]. */
class AppGraph(val context: Context) {
    val settings = SettingsRepository(context)
    val prayer = PrayerModule()
    val registry = ModuleRegistry().also { it.register(prayer) }
    val arbiter = ActivityArbiter()
    val peeks = PeekQueue()
    val island = IslandController()
    val liveUpdate = LiveUpdateController(context, this)

    /** Points the prayer module at the user's place, method and peek lead time. */
    fun apply(s: AppSettings) {
        prayer.location = s.location
        prayer.settings = s.calculation
        prayer.preAdhanLead = Duration.ofMinutes(s.adhanLeadMinutes.toLong())
    }

    suspend fun currentSettings(): AppSettings = settings.current().also(::apply)
}
