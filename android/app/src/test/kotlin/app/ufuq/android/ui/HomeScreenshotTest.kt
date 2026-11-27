package app.ufuq.android.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.ufuq.android.capture
import app.ufuq.android.settings.AppSettings
import app.ufuq.android.silence.ExtrasActions
import app.ufuq.android.silence.ExtrasState
import app.ufuq.android.silence.Mosque
import app.ufuq.core.prayer.CalcMethod
import app.ufuq.core.prayer.PrayerLocation
import app.ufuq.core.prayer.PrayerModule
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

// Thursday 26 Nov 2026, 15:00 in Jakarta: Ashar is next.
private val NOW: Instant = Instant.parse("2026-11-26T08:00:00Z")
private val today get() = assertNotNull(TodayState.at(NOW, PrayerModule(PrayerLocation.JAKARTA, clock = { NOW })))

/** Home (the settings) and its sub-pages. Linux renders; CI's runner is the reference. */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h1500dp-xhdpi")
class HomeScreenshotTest {
    private fun shot(name: String, height: Dp, fontScale: Float = 1f, content: @androidx.compose.runtime.Composable () -> Unit) = capture(name) {
        val density = LocalDensity.current
        CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
            Box(Modifier.width(360.dp).height(height)) { content() }
        }
    }

    @Test fun nextPrayerLine() {
        assertEquals("Ashar", today.nextName)
        assertEquals("Jakarta", today.location)
        assertEquals(Regex("\\d\\d:\\d\\d").matches(today.nextTime), true)
    }

    @Test fun homeDefault() = shot("home-01-default", 1400.dp) {
        HomeScreen(AppSettings(), SettingsActions(), overlayPermissionGranted = false, today = today, versionName = "0.1.3")
    }

    @Test fun homeIslandOnMacPaired() = shot("home-02-island-on-mac-paired", 1400.dp) {
        HomeScreen(
            AppSettings(overlayEnabled = true, otherAppsEnabled = true, silenceEnabled = true, silenceMinutes = 20, ramadanManual = true),
            SettingsActions(),
            overlayPermissionGranted = true,
            today = today,
            mediaAccessGranted = true,
            dndGranted = true,
            macName = "Mac mini",
            versionName = "0.1.3",
        )
    }

    @Test fun location() = shot("home-03-location", 1000.dp) {
        LocationScreen(AppSettings(), SettingsActions(), locationMessage = null)
    }

    @Test fun method() = shot("home-04-method", 480.dp) {
        MethodScreen(AppSettings(method = CalcMethod.KEMENAG), SettingsActions())
    }

    @Test fun silence() = shot("home-05-silence", 1100.dp) {
        SilencePage(
            AppSettings(silenceEnabled = true, silenceMinutes = 20),
            ExtrasState(
                dndGranted = true,
                mosques = listOf(Mosque(1, "Masjid Istiqlal", -6.17, 106.83), Mosque(2, "Masjid At-Tin", -6.30, 106.89)),
                fineLocationGranted = true,
            ),
            ExtrasActions(),
            onBack = {},
        )
    }

    @Config(qualifiers = "w360dp-h3400dp-xhdpi")
    @Test fun homeFont200() = shot("home-06-font200", 3300.dp, fontScale = 2f) {
        HomeScreen(AppSettings(), SettingsActions(), overlayPermissionGranted = false, today = today, macName = "Mac mini", versionName = "0.1.3")
    }

    @Test fun lead() = shot("home-07-lead", 560.dp) { LeadScreen(AppSettings(), SettingsActions()) }

    @Test fun otherApps() = shot("home-08-other-apps", 560.dp) {
        OtherAppsPage(AppSettings(), SettingsActions(), accessGranted = false, apps = emptyList())
    }

    @Test fun mac() = shot("home-09-mac", 400.dp) { MacPage("Mac mini", SettingsActions()) }

    @Test fun overlayExplanation() = capture("settings-02-overlay-explanation") {
        Box(Modifier.width(360.dp).height(700.dp)) { OverlayExplainScreen(onContinue = {}, onCancel = {}) }
    }
}

/** TalkBack contract of Home's rows. */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h800dp-xhdpi")
class HomeSemanticsTest {
    @get:Rule val compose = createComposeRule()

    @Test fun navigationRowsReadTitleAndValueAsOneButton() {
        var opened: SettingsPage? = null
        compose.setContent {
            UfuqTheme { HomeScreen(AppSettings(), SettingsActions(onOpen = { opened = it }), overlayPermissionGranted = false, today = today) }
        }
        val row = compose.onNodeWithContentDescription("Location, Jakarta")
        row.performScrollTo().assertHasClickAction().assertHeightIsAtLeast(48.dp)
        assertEquals(Role.Button, row.fetchSemanticsNode().config[SemanticsProperties.Role])
        row.performClick()
        assertEquals(SettingsPage.LOCATION, opened)
    }

    @Test fun switchRowsAreOneSwitch() {
        var overlay: Boolean? = null
        compose.setContent {
            UfuqTheme { HomeScreen(AppSettings(), SettingsActions(onOverlay = { overlay = it }), overlayPermissionGranted = false) }
        }
        val row = compose.onNodeWithText("Island overlay", useUnmergedTree = false)
        assertEquals(Role.Switch, row.fetchSemanticsNode().config[SemanticsProperties.Role])
        row.assertHeightIsAtLeast(48.dp).performClick()
        assertEquals(true, overlay)
    }

    @Test fun statusCardShowsNextPrayerAndOnlyAttentionItems() {
        compose.setContent {
            UfuqTheme {
                HomeScreen(AppSettings(overlayEnabled = true), SettingsActions(), overlayPermissionGranted = false, today = today, macName = "Mac mini")
            }
        }
        compose.onNodeWithContentDescription("Next:", substring = true).assertExists()
        compose.onNodeWithContentDescription("Island needs permission", substring = true).assertExists()
        compose.onNodeWithContentDescription("Mac, Paired with Mac mini").assertDoesNotExist()
    }
}
