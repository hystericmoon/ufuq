package app.ufuq.android.travel

import app.ufuq.android.settings.AppSettings
import app.ufuq.core.prayer.PrayerLocation
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/** The new place to switch to. The time zone is the system's, applied by the caller. */
data class TravelUpdate(val name: String, val latitude: Double, val longitude: Double)

/** Travel mode maths. No network geocoding: names come from the built-in city list. */
object TravelLogic {
    const val THRESHOLD_KM = 25.0
    const val NEAREST_CITY_KM = 50.0
    const val SAME_CITY_KM = 10.0

    fun distanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val r = 6371.0088
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = sin(dLat / 2).pow(2) + cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) * sin(dLon / 2).pow(2)
        return 2 * r * asin(sqrt(a))
    }

    /** The nearest city within [NEAREST_CITY_KM], or [fallback]. */
    fun nameFor(latitude: Double, longitude: Double, cities: List<PrayerLocation>, fallback: String): String =
        cities.map { it to distanceKm(latitude, longitude, it.latitude, it.longitude) }
            .filter { it.second <= NEAREST_CITY_KM }
            .minByOrNull { it.second }?.first?.name ?: fallback

    /** "Jakarta" within [SAME_CITY_KM] of a listed city, "Near Jakarta" within [NEAREST_CITY_KM], else [fallback]. */
    fun placeName(latitude: Double, longitude: Double, cities: List<PrayerLocation>, fallback: String): String {
        val (city, km) = cities.map { it to distanceKm(latitude, longitude, it.latitude, it.longitude) }.minByOrNull { it.second } ?: return fallback
        return when {
            km <= SAME_CITY_KM -> city.name
            km <= NEAREST_CITY_KM -> "Near ${city.name}"
            else -> fallback
        }
    }

    /** An update when following is on and the fix is at least [THRESHOLD_KM] from the current place. */
    fun plan(settings: AppSettings, latitude: Double, longitude: Double, cities: List<PrayerLocation>, fallback: String): TravelUpdate? {
        if (!settings.followLocation) return null
        if (distanceKm(settings.latitude, settings.longitude, latitude, longitude) < THRESHOLD_KM) return null
        return TravelUpdate(nameFor(latitude, longitude, cities, fallback), latitude, longitude)
    }

    fun apply(settings: AppSettings, update: TravelUpdate, systemZoneId: String): AppSettings = settings.copy(
        cityName = update.name, latitude = update.latitude, longitude = update.longitude,
        zoneId = systemZoneId, usesDeviceLocation = true,
    )
}
