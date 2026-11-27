package app.ufuq.android.travel

import app.ufuq.android.settings.AppSettings
import app.ufuq.android.settings.Cities
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TravelLogicTest {
    private val bandung = Cities.byName("Bandung")!!
    private val on = AppSettings(followLocation = true)

    @Test fun jakartaToBandungIsAbout115Km() {
        val km = TravelLogic.distanceKm(-6.2146, 106.8451, bandung.latitude, bandung.longitude)
        assertTrue(km in 110.0..120.0, "$km")
    }

    @Test fun belowTheThresholdNothingChanges() {
        // About 11 km north of Jakarta's centre.
        assertNull(TravelLogic.plan(on, -6.115, 106.8451, Cities.ALL, "Current location"))
    }

    @Test fun justAboveTheThresholdUpdates() {
        val lat = -6.2146 + 26.0 / 111.19
        assertNotNull(TravelLogic.plan(on, lat, 106.8451, Cities.ALL, "Current location"))
        val under = -6.2146 + 24.0 / 111.19
        assertNull(TravelLogic.plan(on, under, 106.8451, Cities.ALL, "Current location"))
    }

    @Test fun offWhenFollowingIsOff() {
        assertNull(TravelLogic.plan(AppSettings(), bandung.latitude, bandung.longitude, Cities.ALL, "x"))
    }

    @Test fun namesTheNearestCityWithin50KmElseTheFallback() {
        assertEquals("Bandung", TravelLogic.nameFor(-6.95, 107.65, Cities.ALL, "Current location"))
        // Lembang is ~12 km from Bandung.
        assertEquals("Bandung", TravelLogic.nameFor(-6.81, 107.62, Cities.ALL, "Current location"))
        // Cirebon is ~100 km from Bandung and further from every other listed city.
        assertEquals("Current location", TravelLogic.nameFor(-6.7320, 108.5523, Cities.ALL, "Current location"))
    }

    @Test fun applyingSetsCoordinatesNameZoneAndDeviceFlag() {
        val u = TravelLogic.plan(on, -6.95, 107.65, Cities.ALL, "Current location")!!
        val s = TravelLogic.apply(on, u, "Asia/Makassar")
        assertEquals("Bandung", s.cityName)
        assertEquals(-6.95, s.latitude)
        assertEquals("Asia/Makassar", s.zoneId)
        assertTrue(s.usesDeviceLocation)
        // Already there: the next check is a no-op, so one notice only.
        assertNull(TravelLogic.plan(s, -6.95, 107.65, Cities.ALL, "x"))
    }

    @Test fun aDeviceLocationNamesItsNearestCity() {
        assertEquals("Jakarta", TravelLogic.placeName(-6.17, 106.83, Cities.ALL, "My location"))
        // Bogor is about 45 km from Jakarta's centre and not in the list: "Near" keeps it honest.
        val bogor = TravelLogic.placeName(-6.595, 106.816, Cities.ALL, "My location")
        assertTrue(bogor.startsWith("Near ") || bogor == "Bogor", bogor)
        assertEquals("My location", TravelLogic.placeName(-1.0, 130.0, Cities.ALL, "My location"))
    }

    @Test fun settingsShowThePlaceNameOnlyForADeviceLocation() {
        val device = AppSettings(cityName = "My location", latitude = -6.17, longitude = 106.83, usesDeviceLocation = true)
        assertEquals("Jakarta", device.location.name)
        assertEquals("My location", device.cityName)
        assertEquals("Bandung", AppSettings(cityName = "Bandung", latitude = -6.17, longitude = 106.83).location.name)
    }
}
