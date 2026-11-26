package app.ufuq.android.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/** Spec "Visual tokens": black notch/background, card.bg, text.primary/secondary/muted, accent.prayer. */
object Tokens {
    val Bg = Color(0xFF000000)
    val Card = Color(0xFF141416)
    val Control = Color(0xFF1C1C1F)
    val Track = Color(0xFF2A2A2E)
    val Primary = Color(0xFFFFFFFF)
    val Secondary = Color(0xFFA1A1A6)
    val Muted = Color(0xFF8E8E93)
    val AccentPrayer = Color(0xFF4FD1A5)
    val Warning = Color(0xFFFFB340)
    val Critical = Color(0xFFFF6B5E)
}

private val Scheme = darkColorScheme(
    primary = Tokens.AccentPrayer,
    onPrimary = Color.Black,
    background = Tokens.Bg,
    onBackground = Tokens.Primary,
    surface = Tokens.Card,
    onSurface = Tokens.Primary,
    surfaceVariant = Tokens.Control,
    onSurfaceVariant = Tokens.Secondary,
    surfaceContainer = Tokens.Card,
    surfaceContainerHigh = Tokens.Control,
    outline = Tokens.Muted,
    outlineVariant = Tokens.Track,
    secondaryContainer = Tokens.Track,
    onSecondaryContainer = Tokens.Primary,
    error = Tokens.Critical,
)

/** Always dark, like the island: the app follows the notch, not the system theme. */
@Composable
fun UfuqTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = Scheme, content = content)
}
