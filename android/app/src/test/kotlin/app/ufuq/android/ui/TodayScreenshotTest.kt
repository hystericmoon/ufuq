package app.ufuq.android.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.ufuq.android.capture
import app.ufuq.android.settings.AppSettings
import app.ufuq.core.prayer.PrayerLocation
import app.ufuq.core.prayer.PrayerModule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h800dp-xhdpi")
class TodayScreenshotTest {
    // Thursday 26 Nov 2026, 15:00 in Jakarta: Ashar is next.
    private val now = Instant.parse("2026-11-26T08:00:00Z")
    private val state get() = assertNotNull(TodayState.at(now, PrayerModule(PrayerLocation.JAKARTA, clock = { now })))

    @Test fun sixTimesWithTheNextOneMarked() {
        val rows = state.rows
        assertEquals(listOf("Subuh", "Terbit", "Dzuhur", "Ashar", "Maghrib", "Isya"), rows.map { it.name })
        assertEquals(listOf("Ashar"), rows.filter { it.isNext }.map { it.name })
        assertTrue(rows.all { Regex("\\d\\d:\\d\\d").matches(it.time) })
    }

    @Test fun today() = capture("today-01") {
        Box(Modifier.width(360.dp).height(760.dp)) { TodayScreen(state, onOpenSettings = {}) }
    }

    @Test fun settings() = capture("settings-01") {
        Box(Modifier.width(360.dp).height(1100.dp)) {
            SettingsScreen(AppSettings(), SettingsActions(), locationMessage = null, overlayPermissionGranted = false)
        }
    }

    @Test fun overlayExplanation() = capture("settings-02-overlay-explanation") {
        Box(Modifier.width(360.dp).height(700.dp)) { OverlayExplainScreen(onContinue = {}, onCancel = {}) }
    }
}
