package app.ufuq.android.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.ufuq.android.Fixtures
import app.ufuq.android.capture
import app.ufuq.android.live.LiveUpdateContent
import app.ufuq.android.live.LiveUpdate
import app.ufuq.android.ramadan.RamadanLiveCard
import app.ufuq.android.ramadan.RamadanSection
import app.ufuq.android.settings.AppSettings
import app.ufuq.android.silence.ExtrasActions
import app.ufuq.android.silence.ExtrasState
import app.ufuq.android.silence.Mosque
import app.ufuq.android.silence.MosquesSection
import app.ufuq.android.silence.SilenceExplainScreen
import app.ufuq.android.silence.SilenceSection
import app.ufuq.android.travel.TravelSection
import app.ufuq.android.prayer.PrayerProgress
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.Instant
import java.time.ZoneId
import kotlin.test.assertEquals

@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h800dp-xhdpi")
class PrayerExtrasScreenshotTest {
    private val actions = ExtrasActions()
    private val state = ExtrasState(
        dndGranted = true,
        mosques = listOf(Mosque(1, "Masjid Istiqlal", -6.17, 106.83), Mosque(2, "Masjid At-Tin", -6.30, 106.89)),
        fineLocationGranted = true,
        exactAlarmsAllowed = false,
    )
    private val on = AppSettings(silenceEnabled = true, silenceMinutes = 20, ramadanManual = true, followLocation = true)

    @Test fun settingsSectionsOn() = capture("settings-a4-sections-on") {
        Column(
            Modifier.width(360.dp).background(Tokens.Bg).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SilenceSection(on, state, actions)
            MosquesSection(state, actions)
            RamadanSection(on, actions)
            TravelSection(on, actions)
        }
    }

    @Test fun settingsSectionsOff() = capture("settings-a4-sections-off") {
        Column(
            Modifier.width(360.dp).background(Tokens.Bg).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SilenceSection(AppSettings(), ExtrasState(), actions)
            MosquesSection(ExtrasState(), actions)
            RamadanSection(AppSettings(), actions)
            TravelSection(AppSettings(), actions)
        }
    }

    @Test fun silenceNeedsAccess() = capture("settings-a4-silence-needs-access") {
        Column(Modifier.width(360.dp).background(Tokens.Bg).padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            SilenceSection(on, ExtrasState(dndGranted = false), actions)
        }
    }

    @Test fun silenceExplanation() = capture("settings-a4-silence-explanation") {
        Box(Modifier.width(360.dp).height(640.dp)) { SilenceExplainScreen(onContinue = {}, onCancel = {}) }
    }

    // Friday-free Thursday in Jakarta: Subuh 04:21 and Maghrib 17:58 are the mockup's values.
    private val subuh = Instant.parse("2026-02-25T21:21:00Z") // 04:21 WIB
    private val maghrib = Instant.parse("2026-02-26T10:58:00Z") // 17:58 WIB
    private val zone = ZoneId.of("Asia/Jakarta")

    @Test fun liveUpdateIftar() {
        val content = LiveUpdateContent(PrayerProgress("Iftar", subuh, maghrib, subuh.plusSeconds(9 * 3600), "Jakarta"), zone)
        assertEquals("Iftar 17:58", content.title)
        capture("liveupdate-a4-ramadan-iftar") { Box(Modifier.width(360.dp).padding(12.dp)) { RamadanLiveCard(content) } }
    }

    @Test fun liveUpdateImsak() {
        val yesterdayMaghrib = Instant.parse("2026-02-25T10:58:00Z")
        val content = LiveUpdateContent(PrayerProgress("Sahur", yesterdayMaghrib, subuh, subuh.minusSeconds(45 * 60), "Jakarta"), zone)
        assertEquals("Sahur 04:21", content.title)
        capture("liveupdate-a4-ramadan-imsak") { Box(Modifier.width(360.dp).padding(12.dp)) { RamadanLiveCard(content) } }
    }
}
