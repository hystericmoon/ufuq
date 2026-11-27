package app.ufuq.android.silence

import android.content.Context
import android.content.Intent
import android.location.LocationManager
import app.ufuq.android.settings.AppSettings
import java.time.Instant

/**
 * Prayer silence: Do Not Disturb for N minutes after each adhan, and while at a saved mosque.
 * Every entry point ends in [SilenceMachine], so what was changed is always recorded and undone.
 */
class SilenceController(
    private val store: SilenceStore,
    private val dnd: DndGateway,
    private val alarms: SilenceAlarms,
    private val proximity: ProximityRegistrar,
    /** The next adhan strictly after the given moment, for the settings' place and method. */
    private val nextAdhan: (AppSettings, Instant) -> Instant?,
) {
    constructor(context: Context, nextAdhan: (AppSettings, Instant) -> Instant?) :
        this(SilenceStore(context), SystemDnd(context), SystemAlarms(context), SystemProximity(context), nextAdhan)

    val mosques get() = store.mosques

    fun addMosque(name: String, latitude: Double, longitude: Double) = store.addMosque(name, latitude, longitude)
    fun removeMosque(id: Int) = store.removeMosque(id)
    fun hasDndAccess() = dnd.hasAccess()
    fun canScheduleExact() = alarms.canScheduleExact()

    /** Called on every settings change, prayer boundary and boot. Idempotent. */
    fun onRefresh(settings: AppSettings, now: Instant = Instant.now()) {
        if (!settings.silenceEnabled || !dnd.hasAccess()) {
            apply(SilenceMachine.end(store.state, dnd.currentFilter()))
            alarms.cancel(AlarmKind.ADHAN)
            proximity.sync(emptyList())
            return
        }
        apply(SilenceMachine.recover(store.state, dnd.currentFilter(), now.toEpochMilli()))
        // A minute ahead: an alarm that fires right at the adhan must schedule the prayer after it.
        nextAdhan(settings, now.plusSeconds(60))?.let { alarms.schedule(AlarmKind.ADHAN, it.toEpochMilli()) }
        proximity.sync(store.mosques.value)
    }

    /** The adhan alarm. [adhanAt] is when it was due, so a late alarm does not stretch the silence. */
    fun onAdhan(settings: AppSettings, adhanAt: Long, now: Instant = Instant.now()) {
        if (settings.silenceEnabled && dnd.hasAccess()) {
            val until = adhanAt + settings.silenceMinutes * 60_000L
            apply(SilenceMachine.begin(store.state, dnd.currentFilter(), now.toEpochMilli(), until))
        }
        onRefresh(settings, now)
    }

    /** The restore alarm, which must work even when silence was switched off meanwhile. */
    fun onRestore(now: Instant = Instant.now()) {
        apply(SilenceMachine.recover(store.state, dnd.currentFilter(), now.toEpochMilli()))
    }

    fun onGeofence(settings: AppSettings, event: GeofenceEvent, now: Instant = Instant.now()) {
        if (!dnd.hasAccess()) return
        if (!settings.silenceEnabled && event == GeofenceEvent.ENTER) return
        apply(SilenceMachine.geofence(store.state, event, dnd.currentFilter(), now.toEpochMilli(), settings.silenceMinutes))
    }

    private fun apply(step: SilenceStep) {
        // Persist first: if setting the filter dies halfway, the flag still says what to undo.
        store.state = step.state
        step.setFilter?.let { if (dnd.hasAccess()) dnd.setFilter(it) }
        if (step.cancelRestoreAlarm) alarms.cancel(AlarmKind.RESTORE)
        step.restoreAlarmAt?.let { alarms.schedule(AlarmKind.RESTORE, it) }
    }
}

/** Maps the system's proximity broadcast to an event. */
object GeofenceMapping {
    /** `KEY_PROXIMITY_ENTERING` true is entering the radius, false is leaving; absent means no event. */
    fun event(intent: Intent): GeofenceEvent? {
        if (!intent.hasExtra(LocationManager.KEY_PROXIMITY_ENTERING)) return null
        return if (intent.getBooleanExtra(LocationManager.KEY_PROXIMITY_ENTERING, true)) GeofenceEvent.ENTER else GeofenceEvent.LEAVE
    }
}
