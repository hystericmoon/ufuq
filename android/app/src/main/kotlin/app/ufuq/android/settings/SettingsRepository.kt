package app.ufuq.android.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import app.ufuq.core.prayer.CalcMethod
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.settingsStore: DataStore<Preferences> by preferencesDataStore(name = "ufuq_settings")

/** Settings in a DataStore (Preferences). One instance per process, held by the app graph. */
class SettingsRepository(private val store: DataStore<Preferences>) {
    constructor(context: Context) : this(context.applicationContext.settingsStore)

    val settings: Flow<AppSettings> = store.data.map(::read)

    suspend fun current(): AppSettings = settings.first()

    suspend fun update(transform: (AppSettings) -> AppSettings) {
        store.edit { prefs -> write(prefs, transform(read(prefs))) }
    }

    private fun read(p: Preferences): AppSettings {
        val d = AppSettings()
        return AppSettings(
            cityName = p[CITY] ?: d.cityName,
            latitude = p[LAT] ?: d.latitude,
            longitude = p[LON] ?: d.longitude,
            zoneId = p[ZONE] ?: d.zoneId,
            usesDeviceLocation = p[DEVICE_LOCATION] ?: d.usesDeviceLocation,
            method = p[METHOD]?.let { name -> CalcMethod.entries.firstOrNull { it.name == name } } ?: d.method,
            overlayEnabled = p[OVERLAY] ?: d.overlayEnabled,
            liveUpdateEnabled = p[LIVE_UPDATE] ?: d.liveUpdateEnabled,
            adhanLeadMinutes = p[LEAD] ?: d.adhanLeadMinutes,
            adhanMuted = p[MUTED] ?: d.adhanMuted,
            otherAppsEnabled = p[OTHER_APPS] ?: d.otherAppsEnabled,
            otherAppsAllowed = p[OTHER_ALLOWED] ?: d.otherAppsAllowed,
        )
    }

    private fun write(p: androidx.datastore.preferences.core.MutablePreferences, s: AppSettings) {
        p[CITY] = s.cityName
        p[LAT] = s.latitude
        p[LON] = s.longitude
        p[ZONE] = s.zoneId
        p[DEVICE_LOCATION] = s.usesDeviceLocation
        p[METHOD] = s.method.name
        p[OVERLAY] = s.overlayEnabled
        p[LIVE_UPDATE] = s.liveUpdateEnabled
        p[LEAD] = s.adhanLeadMinutes
        p[MUTED] = s.adhanMuted
        p[OTHER_APPS] = s.otherAppsEnabled
        p[OTHER_ALLOWED] = s.otherAppsAllowed
    }

    private companion object {
        val CITY = stringPreferencesKey("city")
        val LAT = doublePreferencesKey("lat")
        val LON = doublePreferencesKey("lon")
        val ZONE = stringPreferencesKey("zone")
        val DEVICE_LOCATION = booleanPreferencesKey("device_location")
        val METHOD = stringPreferencesKey("method")
        val OVERLAY = booleanPreferencesKey("overlay")
        val LIVE_UPDATE = booleanPreferencesKey("live_update")
        val LEAD = intPreferencesKey("adhan_lead")
        val MUTED = booleanPreferencesKey("adhan_muted")
        val OTHER_APPS = booleanPreferencesKey("other_apps")
        val OTHER_ALLOWED = androidx.datastore.preferences.core.stringSetPreferencesKey("other_apps_allowed")
    }
}
