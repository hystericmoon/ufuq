package app.ufuq.android.silence

/** The values of [android.app.NotificationManager]'s interruption filter, kept here so the logic stays pure. */
object Filter {
    const val UNKNOWN = 0
    const val ALL = 1
    const val PRIORITY = 2
    const val NONE = 3
    const val ALARMS = 4
}

/**
 * What the app changed and when it must undo it. Persisted, so a reboot or a killed process never
 * leaves the phone silenced: [active] says "we changed it", and the next refresh restores.
 */
data class SilenceState(
    val active: Boolean = false,
    val previousFilter: Int = Filter.ALL,
    val appliedFilter: Int = Filter.PRIORITY,
    val restoreAtMillis: Long = 0,
)

/** What the caller must do after a transition. */
data class SilenceStep(
    val state: SilenceState,
    /** Set the interruption filter to this, or leave it when null. */
    val setFilter: Int? = null,
    /** (Re)schedule the restore alarm for this moment. */
    val restoreAlarmAt: Long? = null,
    val cancelRestoreAlarm: Boolean = false,
)

enum class GeofenceEvent { ENTER, LEAVE }

/**
 * Do Not Disturb after the adhan, as a pure state machine. Rules:
 * - It only acts when the phone is fully open ([Filter.ALL]); a Do Not Disturb the user chose is left alone.
 * - It restores only while the filter is still the one it applied; if the user changed it, it stands down.
 * - Starting again while active extends the end, never shortens it.
 */
object SilenceMachine {
    const val APPLIED = Filter.PRIORITY

    fun begin(state: SilenceState, currentFilter: Int, nowMillis: Long, untilMillis: Long): SilenceStep {
        if (untilMillis <= nowMillis) return SilenceStep(state)
        if (state.active && currentFilter == state.appliedFilter) {
            val at = maxOf(state.restoreAtMillis, untilMillis)
            return SilenceStep(state.copy(restoreAtMillis = at), restoreAlarmAt = at)
        }
        if (currentFilter != Filter.ALL) {
            // The user's own Do Not Disturb (or an unknown state): do not touch, and forget any old claim.
            return SilenceStep(SilenceState(), cancelRestoreAlarm = state.active)
        }
        return SilenceStep(
            SilenceState(active = true, previousFilter = currentFilter, appliedFilter = APPLIED, restoreAtMillis = untilMillis),
            setFilter = APPLIED,
            restoreAlarmAt = untilMillis,
        )
    }

    fun end(state: SilenceState, currentFilter: Int): SilenceStep {
        if (!state.active) return SilenceStep(state)
        val restore = if (currentFilter == state.appliedFilter) state.previousFilter else null
        return SilenceStep(SilenceState(), setFilter = restore, cancelRestoreAlarm = true)
    }

    /** Boot, app start, the restore alarm: undo what is due, re-arm what is not. */
    fun recover(state: SilenceState, currentFilter: Int, nowMillis: Long): SilenceStep = when {
        !state.active -> SilenceStep(state)
        nowMillis >= state.restoreAtMillis || currentFilter != state.appliedFilter -> end(state, currentFilter)
        else -> SilenceStep(state, restoreAlarmAt = state.restoreAtMillis)
    }

    fun geofence(state: SilenceState, event: GeofenceEvent, currentFilter: Int, nowMillis: Long, minutes: Int): SilenceStep = when (event) {
        GeofenceEvent.ENTER -> begin(state, currentFilter, nowMillis, nowMillis + minutes * 60_000L)
        GeofenceEvent.LEAVE -> end(state, currentFilter)
    }
}

/** Exact alarm when Android allows it, otherwise an inexact window. */
sealed interface AlarmChoice {
    data object Exact : AlarmChoice
    data class Window(val lengthMillis: Long) : AlarmChoice

    companion object {
        /** Android 12+ widens windows under 10 minutes anyway, so ask for a realistic one. */
        const val WINDOW_MILLIS = 5 * 60_000L

        fun of(canScheduleExact: Boolean): AlarmChoice = if (canScheduleExact) Exact else Window(WINDOW_MILLIS)
    }
}

/** A saved place: entering silences, leaving restores. */
data class Mosque(val id: Int, val name: String, val latitude: Double, val longitude: Double, val radiusMeters: Float = DEFAULT_RADIUS) {
    companion object {
        const val DEFAULT_RADIUS = 100f
    }
}
