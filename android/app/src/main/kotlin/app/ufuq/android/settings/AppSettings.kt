package app.ufuq.android.settings

import app.ufuq.core.prayer.CalcMethod
import app.ufuq.core.prayer.CalculationSettings
import app.ufuq.core.prayer.PrayerLocation
import java.time.ZoneId

/** Everything the user can change. Defaults: Jakarta, Kemenag, Live Update on, island off. */
data class AppSettings(
    val cityName: String = Cities.DEFAULT.name,
    val latitude: Double = Cities.DEFAULT.latitude,
    val longitude: Double = Cities.DEFAULT.longitude,
    val zoneId: String = Cities.DEFAULT.zone.id,
    /** True when the place came from "Use my location" rather than the city list. */
    val usesDeviceLocation: Boolean = false,
    val method: CalcMethod = CalcMethod.KEMENAG,
    /** The island overlay is OFF by default; it needs the "display over other apps" permission. */
    val overlayEnabled: Boolean = false,
    /** The Live Update chip is the accessible default. */
    val liveUpdateEnabled: Boolean = true,
    val adhanLeadMinutes: Int = DEFAULT_LEAD_MINUTES,
    /** The island's mute-adhan button. */
    val adhanMuted: Boolean = false,
    /** Beta: other apps' ongoing notifications in the island. Off by default. */
    val otherAppsEnabled: Boolean = false,
    /** Package names the user allowed; the only thing of this feature that is stored. */
    val otherAppsAllowed: Set<String> = emptySet(),
) {
    val location: PrayerLocation
        get() = PrayerLocation(cityName, latitude, longitude, runCatching { ZoneId.of(zoneId) }.getOrDefault(ZoneId.systemDefault()))

    val calculation: CalculationSettings get() = CalculationSettings(method = method)

    companion object {
        const val DEFAULT_LEAD_MINUTES = 10
        val LEAD_CHOICES = listOf(5, 10, 15, 20)
        val METHODS = listOf(CalcMethod.KEMENAG, CalcMethod.MWL, CalcMethod.UMM_AL_QURA)
    }
}

/** The manual city list. Jakarta first and the default. */
object Cities {
    val DEFAULT = PrayerLocation.JAKARTA

    val ALL: List<PrayerLocation> = listOf(
        PrayerLocation.JAKARTA,
        PrayerLocation("Bandung", -6.9175, 107.6191, ZoneId.of("Asia/Jakarta"), elevation = 768),
        PrayerLocation("Surabaya", -7.2575, 112.7521, ZoneId.of("Asia/Jakarta")),
        PrayerLocation("Yogyakarta", -7.7956, 110.3695, ZoneId.of("Asia/Jakarta")),
        PrayerLocation("Medan", 3.5952, 98.6722, ZoneId.of("Asia/Jakarta")),
        PrayerLocation("Makassar", -5.1477, 119.4327, ZoneId.of("Asia/Makassar")),
        PrayerLocation("Denpasar", -8.6705, 115.2126, ZoneId.of("Asia/Makassar")),
        PrayerLocation("Jayapura", -2.5337, 140.7181, ZoneId.of("Asia/Jayapura")),
        PrayerLocation("Kuala Lumpur", 3.1390, 101.6869, ZoneId.of("Asia/Kuala_Lumpur")),
        PrayerLocation("Singapore", 1.3521, 103.8198, ZoneId.of("Asia/Singapore")),
        PrayerLocation("Makkah", 21.4225, 39.8262, ZoneId.of("Asia/Riyadh")),
        PrayerLocation("Madinah", 24.4672, 39.6111, ZoneId.of("Asia/Riyadh")),
    )

    fun byName(name: String): PrayerLocation? = ALL.firstOrNull { it.name == name }
}
