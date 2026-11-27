package app.ufuq.android.island

import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.ufuq.android.Fixtures
import app.ufuq.android.PhoneWall
import app.ufuq.android.TestStrings
import app.ufuq.core.PeekEvent
import app.ufuq.core.UsageLevel
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** TalkBack contract: one node per slider with progress semantics, a labelled 48 dp button, order pill -> page -> button. */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h640dp-xhdpi")
class IslandSemanticsTest {
    @get:Rule val compose = createComposeRule()

    private val pages = IslandPages.all(Fixtures.oneHourTwelve, false, null, TestStrings)

    @Test fun sliderIsOneNodeWithProgressValueAndLabel() {
        compose.setContent { PhoneWall { ExpandedIsland(pages, onAction = {}, onDismiss = {}) } }
        val slider = compose.onNode(hasContentDescription("Ashar in 1 hour 12 minutes", substring = true))
        slider.assertExists()
        val config = slider.fetchSemanticsNode().config
        val range = config[SemanticsProperties.ProgressBarRangeInfo]
        assertEquals(0.65f, range.current, 0.01f)
        assertEquals(0f..1f, range.range)
        val state = config[SemanticsProperties.StateDescription]
        assertTrue("65 percent" in state, state)
        assertTrue("Page 1 of 3" in state, state)
        // The label text inside the track is not a second node.
        compose.onNodeWithText("Ashar", substring = true).assertDoesNotExist()
        compose.onNodeWithText("1:12", substring = true).assertDoesNotExist()
    }

    @Test fun buttonIsLabelledClickableAndAtLeast48dp() {
        var action: ButtonAction? = null
        compose.setContent { PhoneWall { ExpandedIsland(pages, onAction = { action = it }, onDismiss = {}) } }
        val button = compose.onNodeWithContentDescription("Mute adhan")
        button.assertHasClickAction().assertWidthIsAtLeast(48.dp).assertHeightIsAtLeast(48.dp)
        button.performClick()
        assertEquals(ButtonAction.TOGGLE_MUTE, action)
    }

    @Test fun everyPageHasASliderAndALabelledButton() {
        compose.setContent {
            PhoneWall {
                androidx.compose.foundation.layout.Column {
                    for (page in pages) ExpandedIsland(listOf(page), onAction = {}, onDismiss = {})
                }
            }
        }
        for ((label, count) in pages.groupingBy { it.buttonLabel }.eachCount()) {
            compose.onAllNodes(hasContentDescription(label)).assertCountEquals(count)
        }
        for (page in pages) compose.onNode(hasContentDescription(page.slider.description)).assertExists()
    }

    @Test fun usageSliderSaysThePercentSoColourIsNeverAlone() {
        val usage = IslandPages.aiUsage(AiUsageSample("Claude", 0.82), TestStrings)
        compose.setContent { PhoneWall { ExpandedIsland(listOf(usage), onAction = {}, onDismiss = {}) } }
        val config = compose.onNode(hasContentDescription("Claude, 82 percent", substring = true)).fetchSemanticsNode().config
        assertEquals(UsageLevel.WARNING, usage.slider.level)
        assertTrue("82 percent" in config[SemanticsProperties.StateDescription])
    }

    @Test fun longLabelAtLargeFontStaysInTheDescription() {
        val long = IslandPages.prayer(Fixtures.oneHourTwelve.copy(name = "Maghrib dan Isya sangat panjang"), false, TestStrings)
        compose.setContent { PhoneWall(fontScale = 2f) { ExpandedIsland(listOf(long), onAction = {}, onDismiss = {}) } }
        compose.onNode(hasContentDescription("Maghrib dan Isya sangat panjang in 1 hour 12 minutes", substring = true)).assertExists()
    }

    @Test fun pillIsOneButtonAtLeast48dpTall() {
        var clicked = false
        compose.setContent {
            PhoneWall { IslandPill(PillModel("Ashar 15:12", "1:12", UsageLevel.NORMAL, false, "Ashar in 1 hour 12 minutes"), 46, { clicked = true }) }
        }
        val pill = compose.onNodeWithContentDescription("Ashar in 1 hour 12 minutes")
        pill.assertHasClickAction().assertHeightIsAtLeast(48.dp)
        pill.performClick()
        assertTrue(clicked)
    }

    @Test fun expandedIslandOffersCloseAsACustomAction() {
        var closed = false
        compose.setContent { PhoneWall { ExpandedIsland(pages, onAction = {}, onDismiss = { closed = true }) } }
        val node = compose.onNode(androidx.compose.ui.test.SemanticsMatcher.keyIsDefined(SemanticsActions.CustomActions))
        val action = node.fetchSemanticsNode().config[SemanticsActions.CustomActions].first()
        assertEquals("Close island", action.label)
        action.action()
        assertTrue(closed)
    }

    @Test fun peekIsALiveRegionAndDismissesOnClick() {
        var dismissed = false
        val event = PeekEvent("a", "prayer", "Ashar", "now", PeekEvent.Priority.CRITICAL, announcement = "Time for Ashar")
        compose.setContent { PhoneWall { IslandPeek(event, onDismiss = { dismissed = true }, onHold = {}) } }
        val node = compose.onNodeWithContentDescription("Time for Ashar")
        node.assertExists()
        val config = node.fetchSemanticsNode().config
        assertEquals(androidx.compose.ui.semantics.LiveRegionMode.Assertive, config[SemanticsProperties.LiveRegion])
        node.performSemanticsAction(SemanticsActions.OnClick)
        assertTrue(dismissed)
    }

    @Test fun seekSliderIsAdjustableWithTenSecondSteps() {
        val state = app.ufuq.android.media.MediaState("Mishary", durationMs = 210_000, positionMs = 84_000, updatedAtElapsedMs = 0, playing = true)
        val page = IslandPages.media(state, true, TestStrings, 0)
        var seeked: Float? = null
        compose.setContent { PhoneWall { ExpandedIsland(listOf(page), onAction = {}, onDismiss = {}, onSeek = { seeked = it }) } }
        val node = compose.onNode(hasContentDescription("Seek, Mishary", substring = true))
        val config = node.fetchSemanticsNode().config
        assertTrue(SemanticsActions.SetProgress in config) // the adjustable-slider contract
        val range = config[SemanticsProperties.ProgressBarRangeInfo]
        assertEquals(0.4f, range.current, 0.01f)
        assertEquals(20, range.steps) // TalkBack increment/decrement = 210 s / 21 = 10 s
        assertTrue("1 minute 24 seconds of 3 minutes 30 seconds" in config[SemanticsProperties.StateDescription])
        node.performSemanticsAction(SemanticsActions.SetProgress) { it(0.5f) }
        assertEquals(0.5f, seeked)
    }

    @Test fun usageSliderIsNotInteractive() {
        val usage = IslandPages.aiUsage(AiUsageSample("Claude", 0.82), TestStrings)
        compose.setContent { PhoneWall { ExpandedIsland(listOf(usage), onAction = {}, onDismiss = {}) } }
        val config = compose.onNode(hasContentDescription("Claude, 82 percent", substring = true)).fetchSemanticsNode().config
        assertTrue(SemanticsActions.SetProgress !in config)
    }

    @Test fun mediaButtonIsLabelledPlayPause() {
        var action: ButtonAction? = null
        val state = app.ufuq.android.media.MediaState("Mishary", durationMs = 210_000, playing = true)
        compose.setContent { PhoneWall { ExpandedIsland(listOf(IslandPages.media(state, true, TestStrings, 0)), onAction = { action = it }, onDismiss = {}) } }
        compose.onNodeWithContentDescription("Pause").assertHasClickAction().assertWidthIsAtLeast(48.dp).performClick()
        assertEquals(ButtonAction.PLAY_PAUSE, action)
    }
}
