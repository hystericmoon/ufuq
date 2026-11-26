package app.ufuq.android.sync

import androidx.compose.foundation.layout.padding
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.ufuq.android.PhoneWall
import app.ufuq.android.TestStrings
import app.ufuq.android.capture
import app.ufuq.android.island.ExpandedIsland
import app.ufuq.android.island.IslandPageModel
import java.time.Duration
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Pairing screen and page B in each Mac-link state. Linux renders; CI's runner is the reference. */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h900dp-xhdpi")
class SyncScreenshotTest {
    private fun pageB(state: SyncState): IslandPageModel = SyncMapper.pageB(state, SyncFixtures.NOW, TestStrings, TestSyncStrings)

    private fun island(name: String, state: SyncState) =
        capture(name) { PhoneWall { ExpandedIsland(listOf(pageB(state)), onAction = {}, onDismiss = {}) } }

    @Test fun pairing() = capture("sync-01-pairing") { PairingScreen(PairingUiState(), PairingActions()) }

    @Test fun pairingCameraDeniedWithError() =
        capture("sync-02-pairing-denied-error") {
            PairingScreen(PairingUiState(cameraDenied = true, code = "not a code", error = PairingError.INVALID), PairingActions())
        }

    @Test fun pairingScanning() = capture("sync-03-pairing-scanning") {
        PairingScreen(
            PairingUiState(cameraGranted = true, scanning = true), PairingActions(),
            camera = { androidx.compose.foundation.layout.Box(it) },
        )
    }

    @Test fun pairingDone() = capture("sync-04-pairing-done") { PairingScreen(PairingUiState(pairedName = "Mac mini"), PairingActions()) }

    @Test fun pageBUnpaired() = island("sync-05-page-b-unpaired", SyncState.Unpaired)

    @Test fun pageBConnecting() = island("sync-06-page-b-connecting", SyncState.Connecting())

    @Test fun pageBData() = island("sync-07-page-b-data", SyncState.Live(SyncFixtures.data()))

    @Test fun pageBStale() = island(
        "sync-08-page-b-mac-unreachable",
        SyncState.Unreachable(SyncFixtures.data(fetchedAt = SyncFixtures.NOW.minus(Duration.ofMinutes(5)))),
    )

    @Test fun pageBPairAgain() = island("sync-09-page-b-pair-again", SyncState.PairAgain)

    @Test fun settingsMacSection() = capture("sync-10-settings-mac-section") {
        androidx.compose.foundation.layout.Column(androidx.compose.ui.Modifier.padding(16.dp)) {
            MacSyncSection(macName = null, onPair = {}, onForget = {})
            MacSyncSection(macName = "Mac mini", onPair = {}, onForget = {})
        }
    }
}
