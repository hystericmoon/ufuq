package app.ufuq.android

import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import app.ufuq.android.ui.UfuqTheme
import com.github.takahirom.roborazzi.captureRoboImage

/** A 360 dp "phone wall" with the 12 dp island inset, so a shot reads like the mockup. */
@Composable
fun PhoneWall(fontScale: Float = 1f, content: @Composable () -> Unit) {
    val density = LocalDensity.current
    CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
        Box(Modifier.width(360.dp).background(Color(0xFF9AA09B)).padding(horizontal = 12.dp, vertical = 12.dp)) { content() }
    }
}

/** Captures [content] as `src/test/screenshots/<name>.png` (a Linux render; CI's runner is the reference). */
fun capture(name: String, content: @Composable () -> Unit) {
    val context = ApplicationProvider.getApplicationContext<android.content.Context>()
    Settings.System.putString(context.contentResolver, Settings.System.TIME_12_24, "24")
    captureRoboImage("$name.png") { UfuqTheme { content() } }
}
