package app.ufuq.android.activities

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.ufuq.android.PhoneWall
import app.ufuq.android.capture
import app.ufuq.android.island.ButtonAction
import app.ufuq.android.island.ExpandedIsland
import app.ufuq.android.ui.OtherAppsExplainScreen
import app.ufuq.android.ui.OtherAppsSection
import app.ufuq.android.ui.Tokens
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import kotlin.test.assertEquals
import kotlin.test.assertTrue

private val apps = listOf(SeenApp("com.example.ride", "Ride app"), SeenApp("com.example.food", "Delivery app"))

private val ridePage = ActivityPages.page(
    ongoing(label = "Ride app", category = "transport") {
        it.copy(usesChronometer = true, chronometerCountDown = true, whenMillis = NOW.toEpochMilli() + 6 * 60_000 - 1000, progressMax = 100, progress = 60)
    },
    NOW, TestActivityStrings,
)

@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h640dp-xhdpi")
class OtherAppsScreenshotTest {
    private fun section(enabled: Boolean, granted: Boolean, list: List<SeenApp>, allowed: Set<String>) = @androidx.compose.runtime.Composable {
        Column(Modifier.width(360.dp).background(Tokens.Bg).padding(16.dp)) {
            OtherAppsSection(enabled, granted, list, allowed, {}, { _, _ -> }, {}, {})
        }
    }

    @Test fun settingsSectionOff() = capture("other-01-settings-off", section(false, false, emptyList(), emptySet()))

    @Test fun settingsSectionOn() = capture("other-02-settings-on", section(true, true, apps, setOf("com.example.ride")))

    @Test fun explanationScreen() = capture("other-03-explain") {
        Column(Modifier.width(360.dp)) { OtherAppsExplainScreen(accessGranted = false, onContinue = {}, onCancel = {}) }
    }

    @Test fun expandedPage() = capture("other-04-expanded-page") {
        PhoneWall { ExpandedIsland(listOf(ridePage), onAction = {}, onDismiss = {}) }
    }

    @Test fun expandedPageIndeterminate() = capture("other-05-expanded-page-indeterminate") {
        val page = ActivityPages.page(ongoing(label = "Delivery app", category = "transport") { it.copy(title = "Courier on the way", progressIndeterminate = true) }, NOW, TestActivityStrings)
        PhoneWall { ExpandedIsland(listOf(page), onAction = {}, onDismiss = {}) }
    }
}

/** TalkBack contract of the new page and settings rows. */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h640dp-xhdpi")
class OtherAppsSemanticsTest {
    @get:Rule val compose = createComposeRule()

    @Test fun pageIsOneSliderNodeAndALabelledOpenButton() {
        var action: ButtonAction? = null
        compose.setContent { PhoneWall { ExpandedIsland(listOf(ridePage), onAction = { action = it }, onDismiss = {}) } }
        val slider = compose.onNode(hasContentDescription("Ride app, 6 min", substring = true))
        slider.assertExists()
        val config = slider.fetchSemanticsNode().config
        assertEquals(0.6f, config[SemanticsProperties.ProgressBarRangeInfo].current, 0.01f)
        assertTrue("60 percent" in config[SemanticsProperties.StateDescription])
        val button = compose.onNodeWithContentDescription("Open Ride app")
        button.assertHasClickAction().assertHeightIsAtLeast(48.dp)
        button.performClick()
        assertEquals(ButtonAction.OPEN_SOURCE, action)
    }

    @Test fun appRowsAreCheckboxesAndTogglingReportsThePackage() {
        var toggled: Pair<String, Boolean>? = null
        compose.setContent {
            OtherAppsSection(true, true, apps, emptySet(), {}, { p, on -> toggled = p to on }, {}, {})
        }
        compose.onNodeWithText("Ride app").performClick()
        assertEquals("com.example.ride" to true, toggled)
    }
}
