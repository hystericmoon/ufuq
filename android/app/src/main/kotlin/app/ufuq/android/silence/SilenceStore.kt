package app.ufuq.android.silence

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * The silence state and the saved mosques, in SharedPreferences: synchronous, so a receiver can
 * read and write it without a coroutine and the "we changed it" flag survives process death.
 */
class SilenceStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("ufuq_silence", Context.MODE_PRIVATE)

    private val _mosques = MutableStateFlow(readMosques())
    val mosques: StateFlow<List<Mosque>> = _mosques

    var state: SilenceState
        get() = SilenceState(
            active = prefs.getBoolean(ACTIVE, false),
            previousFilter = prefs.getInt(PREVIOUS, Filter.ALL),
            appliedFilter = prefs.getInt(APPLIED, SilenceMachine.APPLIED),
            restoreAtMillis = prefs.getLong(RESTORE_AT, 0),
        )
        set(s) {
            // commit(): a flag that guards the phone's sound must reach disk before we return.
            prefs.edit()
                .putBoolean(ACTIVE, s.active).putInt(PREVIOUS, s.previousFilter)
                .putInt(APPLIED, s.appliedFilter).putLong(RESTORE_AT, s.restoreAtMillis)
                .commit()
        }

    fun addMosque(name: String, latitude: Double, longitude: Double): Mosque {
        val list = _mosques.value
        val clean = name.replace(Regex("[\\t\\r\\n|]"), " ").trim().take(40).ifEmpty { "Mosque ${list.size + 1}" }
        val mosque = Mosque((list.maxOfOrNull { it.id } ?: 0) + 1, clean, latitude, longitude)
        saveMosques(list + mosque)
        return mosque
    }

    fun removeMosque(id: Int) = saveMosques(_mosques.value.filterNot { it.id == id })

    private fun saveMosques(list: List<Mosque>) {
        prefs.edit().putString(MOSQUES, list.joinToString("\n") { "${it.id}\t${it.name}\t${it.latitude}\t${it.longitude}\t${it.radiusMeters}" }).apply()
        _mosques.value = list
    }

    private fun readMosques(): List<Mosque> =
        (prefs.getString(MOSQUES, null) ?: "").lines().mapNotNull { line ->
            val p = line.split('\t')
            if (p.size < 5) return@mapNotNull null
            runCatching { Mosque(p[0].toInt(), p[1], p[2].toDouble(), p[3].toDouble(), p[4].toFloat()) }.getOrNull()
        }

    private companion object {
        const val ACTIVE = "active"
        const val PREVIOUS = "previous"
        const val APPLIED = "applied"
        const val RESTORE_AT = "restore_at"
        const val MOSQUES = "mosques"
    }
}
