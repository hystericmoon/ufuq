package app.ufuq.desktop.settings

import app.ufuq.core.prayer.CalcMethod
import java.io.File
import java.util.Properties
import kotlin.test.Test
import kotlin.test.assertEquals

class SettingsStoreTest {
    @Test fun defaultsAreJakartaKemenag() {
        val s = DesktopSettings()
        assertEquals("Jakarta", s.location.name)
        assertEquals(CalcMethod.KEMENAG, s.method)
        assertEquals(emptyList(), s.claudeDirs)
        assertEquals(null, s.reduceMotion)
    }

    @Test fun updateDefaultsAreDailyCheckNoBeta() {
        val s = DesktopSettings()
        assertEquals(true, s.autoCheckUpdates)
        assertEquals(false, s.betaUpdates)
        assertEquals(0L, s.lastUpdateCheck)
    }

    @Test fun twelveCitiesJakartaFirst() {
        assertEquals(12, Cities.ALL.size)
        assertEquals("Jakarta", Cities.ALL.first().name)
        assertEquals("Asia/Makassar", Cities.byName("Denpasar")?.zone?.id)
    }

    @Test fun roundTripsThroughAFile() {
        val dir = kotlin.io.path.createTempDirectory("ufuq-settings").toFile()
        try {
            val store = SettingsStore(File(dir, "nested/settings.properties"))
            val s = DesktopSettings("Makassar", CalcMethod.MWL, listOf("C:\\Users\\me\\.claude", "D:\\work\\.claude-work"), true, true, 1234, 5678, false, true, 99L)
            store.save(s)
            assertEquals(s, store.load())
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test fun missingOrBrokenFilesGiveDefaults() {
        assertEquals(DesktopSettings(), SettingsStore(File("/nonexistent/ufuq/settings.properties")).load())
        val p = Properties().apply {
            setProperty("city", "Atlantis")
            setProperty("method", "NOPE")
            setProperty("sessionBudget", "-5")
            setProperty("claudeDirs.count", "oops")
        }
        assertEquals(DesktopSettings(), SettingsStore.fromProperties(p))
    }

    @Test fun storeLivesInAppDataOnWindows() {
        val store = SettingsStore.default(env = mapOf("APPDATA" to "/tmp/appdata"), home = "/home/x")
        val path = SettingsStore::class.java.getDeclaredField("file").also { it.isAccessible = true }.get(store) as File
        assertEquals(File("/tmp/appdata/Ufuq/settings.properties"), path)
    }
}
