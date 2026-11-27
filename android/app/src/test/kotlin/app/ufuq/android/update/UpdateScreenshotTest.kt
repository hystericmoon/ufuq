package app.ufuq.android.update

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.ufuq.android.capture
import app.ufuq.android.ui.Tokens
import app.ufuq.core.update.AvailableDownload
import app.ufuq.core.update.ReleaseAsset
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h800dp-xhdpi")
class UpdateScreenshotTest {
    private val now = 1_764_000_000_000L
    private val update = AvailableDownload(
        "0.2.0",
        "• Faster island on Android 16\n• Prayer silence keeps your ringer setting\n• Fixes for TalkBack on the media page",
        ReleaseAsset("ufuq-0.2.0.apk", "https://github.com/x/ufuq-0.2.0.apk", 12_000_000, null),
    )
    private val base = UpdateUiState(enabled = true, lastCheckMillis = now - 3 * 60 * 60 * 1000)

    private fun shot(name: String, state: UpdateUiState) = capture(name) {
        UpdateScreen(state, UpdateActions(), nowMillis = now, versionName = "0.1.0")
    }

    @Test fun upToDate() = shot("update-up-to-date", base.copy(status = UpdateStatus.UpToDate))
    @Test fun available() = shot("update-available", base.copy(status = UpdateStatus.Available(update), betaChannel = true))
    @Test fun downloading() = shot("update-downloading", base.copy(status = UpdateStatus.Downloading(update, 0.42f)))
    @Test fun ready() = shot("update-ready", base.copy(status = UpdateStatus.Ready(update, File("x.apk"))))
    @Test fun failed() = shot("update-failed", base.copy(status = UpdateStatus.Failed(update)))
    @Test fun devBuild() = shot("update-dev-build", UpdateUiState(enabled = false))

    @Test fun prompt() = capture("update-prompt") {
        Box(Modifier.fillMaxSize().background(Tokens.Bg)) {
            UpdatePromptDialog(base.copy(status = UpdateStatus.Available(update), prompt = true), UpdateActions(), onDismiss = {})
        }
    }
}
