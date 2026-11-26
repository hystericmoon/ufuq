package app.ufuq.android.sync

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.ufuq.android.PhoneWall
import app.ufuq.android.TestStrings
import app.ufuq.android.island.ButtonAction
import app.ufuq.android.island.ExpandedIsland
import app.ufuq.android.ui.UfuqTheme
import java.time.Duration
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** TalkBack contract of the pairing screen and of page B in every Mac-link state. */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h900dp-xhdpi")
class SyncScreensTest {
    @get:Rule val compose = createComposeRule()

    private fun pairing(state: PairingUiState = PairingUiState(), actions: PairingActions = PairingActions()) =
        compose.setContent { UfuqTheme { PairingScreen(state, actions) } }

    @Test fun pairingExplainsWhereTheQrIsAndOffersBothWays() {
        pairing()
        compose.onNodeWithText("Pair phone…", substring = true).assertExists()
        compose.onNodeWithText("Allow camera and scan").assertHasClickAction().assertHeightIsAtLeast(48.dp)
        compose.onNodeWithText("Pairing code").assertExists()
        compose.onNodeWithText("Paste from clipboard").assertHasClickAction().assertHeightIsAtLeast(48.dp)
    }

    @Test fun cameraRationaleIsShownBeforeAskingAndTheButtonAsks() {
        var scanned = false
        pairing(actions = PairingActions(onScan = { scanned = true }))
        compose.onNodeWithText("Ufuq uses the camera only on this screen", substring = true).assertExists()
        compose.onNodeWithText("Allow camera and scan").performClick()
        assertTrue(scanned)
    }

    @Test fun deniedCameraPointsToThePasteField() {
        pairing(PairingUiState(cameraDenied = true))
        compose.onNodeWithText("paste the pairing code below", substring = true).assertExists()
    }

    @Test fun pairButtonIsDisabledUntilThereIsText() {
        pairing(PairingUiState(code = ""))
        compose.onNodeWithText("Pair").assertIsNotEnabled()
    }

    @Test fun pairButtonSubmitsWhenThereIsText() {
        var submitted = false
        pairing(PairingUiState(code = "{}"), PairingActions(onSubmit = { submitted = true }))
        compose.onNodeWithText("Pair").assertIsEnabled().performScrollTo().performClick()
        assertTrue(submitted)
    }

    @Test fun errorIsAnnouncedAsALiveRegion() {
        pairing(PairingUiState(code = "x", error = PairingError.INVALID))
        val node = compose.onNodeWithText("That is not a Ufuq pairing code.").fetchSemanticsNode()
        assertTrue(SemanticsProperties.LiveRegion in node.config)
    }

    @Test fun scanningShowsThePreviewSlotAndAStopButton() {
        compose.setContent {
            UfuqTheme {
                PairingScreen(PairingUiState(cameraGranted = true, scanning = true), PairingActions(), camera = { androidx.compose.foundation.layout.Box(it) })
            }
        }
        compose.onNodeWithText("Stop scanning").assertHasClickAction()
    }

    @Test fun pairedCardHasADoneButton() {
        var done = false
        pairing(PairingUiState(pairedName = "Mac mini"), PairingActions(onDone = { done = true }))
        compose.onNodeWithText("Paired with Mac mini").assertExists()
        compose.onNodeWithText("Done").performClick()
        assertTrue(done)
    }

    @Test fun pageBPairAgainIsOneLabelledNodeWithAButton() {
        val page = SyncMapper.pageB(SyncState.PairAgain, SyncFixtures.NOW, TestStrings, TestSyncStrings)
        var action: ButtonAction? = null
        compose.setContent { PhoneWall { ExpandedIsland(listOf(page), onAction = { action = it }, onDismiss = {}) } }
        compose.onNode(hasContentDescription("Your Mac no longer recognises this phone", substring = true)).assertExists()
        compose.onNodeWithContentDescription("Pair again").assertHasClickAction().assertHeightIsAtLeast(48.dp).performClick()
        assertEquals(ButtonAction.PAIR_MAC, action)
    }

    @Test fun pageBStaleDescriptionSaysTheMacIsAwayAndHowOldTheNumberIs() {
        val state = SyncState.Unreachable(SyncFixtures.data(fetchedAt = SyncFixtures.NOW.minus(Duration.ofMinutes(5))))
        val page = SyncMapper.pageB(state, SyncFixtures.NOW, TestStrings, TestSyncStrings)
        compose.setContent { PhoneWall { ExpandedIsland(listOf(page), onAction = {}, onDismiss = {}) } }
        val node = compose.onNode(hasContentDescription("Mac not on this network. Updated 5 minutes ago.", substring = true))
        node.assertExists()
        assertTrue("82 percent" in node.fetchSemanticsNode().config[SemanticsProperties.StateDescription])
    }
}
