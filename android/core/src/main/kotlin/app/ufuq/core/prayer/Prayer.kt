package app.ufuq.core.prayer

import java.time.ZoneId

/** An obligatory prayer. On Fridays Dhuhr is shown as [JUMUAH]. */
enum class Prayer { FAJR, DHUHR, ASR, MAGHRIB, ISHA, JUMUAH }

/** The six times of a day: the five prayers and sunrise. */
enum class PrayerTimeSlot { FAJR, SUNRISE, DHUHR, ASR, MAGHRIB, ISHA }

val FIVE_PRAYERS = listOf(Prayer.FAJR, Prayer.DHUHR, Prayer.ASR, Prayer.MAGHRIB, Prayer.ISHA)

/** Indonesian names, as on the Mac app ("Subuh", "Ashar", "Jumat"). */
val Prayer.displayName: String
    get() = when (this) {
        Prayer.FAJR -> "Subuh"
        Prayer.DHUHR -> "Dzuhur"
        Prayer.ASR -> "Ashar"
        Prayer.MAGHRIB -> "Maghrib"
        Prayer.ISHA -> "Isya"
        Prayer.JUMUAH -> "Jumat"
    }

/** The prayer a slot is, or null for sunrise. */
val PrayerTimeSlot.prayer: Prayer?
    get() = when (this) {
        PrayerTimeSlot.FAJR -> Prayer.FAJR
        PrayerTimeSlot.SUNRISE -> null
        PrayerTimeSlot.DHUHR -> Prayer.DHUHR
        PrayerTimeSlot.ASR -> Prayer.ASR
        PrayerTimeSlot.MAGHRIB -> Prayer.MAGHRIB
        PrayerTimeSlot.ISHA -> Prayer.ISHA
    }

/** Where prayer times are calculated for. */
data class PrayerLocation(
    val name: String,
    val latitude: Double,
    val longitude: Double,
    val zone: ZoneId,
    /** Metres above sea level; only the Kemenag method uses it (horizon dip). */
    val elevation: Int = 0,
) {
    companion object {
        /** Jakarta city centre, the primary user's home and the default. */
        val JAKARTA = PrayerLocation("Jakarta", -6.2146, 106.8451, ZoneId.of("Asia/Jakarta"))
    }
}
