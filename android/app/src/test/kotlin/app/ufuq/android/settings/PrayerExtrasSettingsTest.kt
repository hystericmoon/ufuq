package app.ufuq.android.settings

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import kotlinx.coroutines.test.runTest
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PrayerExtrasSettingsTest {
    private fun repo() = SettingsRepository(
        PreferenceDataStoreFactory.create { Files.createTempFile("ufuq", ".preferences_pb").also { Files.delete(it) }.toFile() },
    )

    @Test fun allExtrasAreOffByDefaultAndSilenceIsFifteenMinutes() = runTest {
        val s = repo().current()
        assertFalse(s.silenceEnabled)
        assertFalse(s.ramadanManual)
        assertFalse(s.followLocation)
        assertEquals(15, s.silenceMinutes)
    }

    @Test fun extrasPersistAndSilenceMinutesStayInFiveToFortyFive() = runTest {
        val r = repo()
        r.update { it.copy(silenceEnabled = true, ramadanManual = true, followLocation = true, silenceMinutes = 90) }
        val s = r.current()
        assertTrue(s.silenceEnabled && s.ramadanManual && s.followLocation)
        assertEquals(45, s.silenceMinutes)
        r.update { it.copy(silenceMinutes = 1) }
        assertEquals(5, r.current().silenceMinutes)
    }
}
