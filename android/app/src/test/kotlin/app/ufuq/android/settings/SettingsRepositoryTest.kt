package app.ufuq.android.settings

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import app.ufuq.core.prayer.CalcMethod
import kotlinx.coroutines.test.runTest
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SettingsRepositoryTest {
    private fun repo() = SettingsRepository(
        PreferenceDataStoreFactory.create { Files.createTempFile("ufuq", ".preferences_pb").also { Files.delete(it) }.toFile() },
    )

    @Test fun defaultsAreJakartaKemenagLiveUpdateOnOverlayOff() = runTest {
        val s = repo().current()
        assertEquals("Jakarta", s.cityName)
        assertEquals(CalcMethod.KEMENAG, s.method)
        assertTrue(s.liveUpdateEnabled)
        assertFalse(s.overlayEnabled)
        assertEquals(10, s.adhanLeadMinutes)
    }

    @Test fun updatesPersist() = runTest {
        val r = repo()
        r.update { it.copy(cityName = "Makassar", zoneId = "Asia/Makassar", overlayEnabled = true, adhanLeadMinutes = 15, method = CalcMethod.MWL) }
        val s = r.current()
        assertEquals("Makassar", s.cityName)
        assertEquals("Asia/Makassar", s.location.zone.id)
        assertTrue(s.overlayEnabled)
        assertEquals(15, s.adhanLeadMinutes)
        assertEquals(CalcMethod.MWL, s.calculation.method)
    }

    @Test fun cityListHasJakartaFirst() {
        assertEquals("Jakarta", Cities.ALL.first().name)
        assertEquals(Cities.ALL.size, Cities.ALL.map { it.name }.toSet().size)
    }
}
