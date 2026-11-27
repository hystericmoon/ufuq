package app.ufuq.android.media

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import app.ufuq.android.TestStrings
import app.ufuq.android.island.ButtonAction
import app.ufuq.android.island.IslandColors
import app.ufuq.android.island.IslandIcon
import app.ufuq.android.island.IslandPageId
import app.ufuq.android.island.IslandPages
import app.ufuq.core.ActivitySource
import app.ufuq.core.UsageLevel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MediaPageTest {
    private val playing = MediaState(
        title = "Mishary", artist = "Alafasy", durationMs = 210_000, positionMs = 84_000,
        updatedAtElapsedMs = 1_000, playing = true, canSeek = true, packageName = "x.player",
    )

    @Test fun positionAdvancesWhilePlayingAndStaysWhenPaused() {
        assertEquals(84_000, playing.positionAt(1_000))
        assertEquals(94_000, playing.positionAt(11_000))
        assertEquals(84_000, playing.copy(playing = false).positionAt(11_000))
        assertEquals(210_000, playing.positionAt(10_000_000)) // never past the end
        assertEquals(168_000, playing.copy(speed = 2f).positionAt(43_000))
    }

    @Test fun fractionIsPositionOverDuration() {
        assertEquals(0.4f, playing.fractionAt(1_000), 0.001f)
        assertEquals(0f, playing.copy(durationMs = 0).fractionAt(1_000)) // a live stream has no fraction
    }

    @Test fun clockAndSpokenFormats() {
        assertEquals("1:24", MediaFormat.clock(84_000))
        assertEquals("0:05", MediaFormat.clock(5_400))
        assertEquals("1:02:03", MediaFormat.clock(3_723_000))
        assertEquals("1 minute 24 seconds", MediaFormat.spoken(84_000))
        assertEquals("3 minutes 30 seconds", MediaFormat.spoken(210_000))
        assertEquals("0 seconds", MediaFormat.spoken(0))
        assertEquals("♪ Short", MediaFormat.wing("Short"))
        assertEquals("\u266A Surah Al-Baqa\u2026", MediaFormat.wing("Surah Al-Baqarah verse 1"))
    }

    @Test fun playingPageMapsTitlePositionAndDuration() {
        val page = IslandPages.media(playing, true, TestStrings, 1_000)
        assertEquals(IslandPageId.MEDIA, page.id)
        val s = page.slider
        assertEquals(0.4f, s.fraction, 0.001f)
        assertEquals("Mishary", s.label)
        assertEquals("1:24", s.secondary)
        assertEquals("3:30", s.trailing)
        assertEquals("Seek, Mishary by Alafasy", s.description)
        assertEquals("1 minute 24 seconds of 3 minutes 30 seconds", s.stateText)
        assertEquals(UsageLevel.NORMAL, s.level)
        assertEquals(20, s.seek!!.steps) // 10 s steps: 21 stops over 3:30
        assertEquals(IslandIcon.PAUSE, page.buttonIcon)
        assertEquals("Pause", page.buttonLabel)
        assertEquals(ButtonAction.PLAY_PAUSE, page.buttonAction)
    }

    @Test fun pausedPageOffersPlay() {
        val page = IslandPages.media(playing.copy(playing = false), true, TestStrings, 99_000)
        assertEquals(IslandIcon.PLAY, page.buttonIcon)
        assertEquals("Play", page.buttonLabel)
        assertEquals("1:24", page.slider.secondary) // paused: the position holds
    }

    @Test fun playerThatCannotSeekOrHasNoLengthIsNotDraggable() {
        assertNull(IslandPages.media(playing.copy(canSeek = false), true, TestStrings, 1_000).slider.seek)
        val live = IslandPages.media(playing.copy(durationMs = 0), true, TestStrings, 1_000).slider
        assertNull(live.seek)
        assertNull(live.trailing)
    }

    @Test fun noSessionIsTheEmptyStateWithAllowAccessUntilGranted() {
        val denied = IslandPages.media(null, false, TestStrings, 0)
        assertEquals("Play something to control it here", denied.slider.label)
        assertEquals(0f, denied.slider.fraction)
        assertNull(denied.slider.seek)
        assertEquals("Allow access", denied.buttonLabel)
        assertEquals(ButtonAction.ALLOW_MEDIA_ACCESS, denied.buttonAction)
        val granted = IslandPages.media(null, true, TestStrings, 0)
        assertEquals(ButtonAction.OPEN_APP, granted.buttonAction)
    }

    @Test fun nowPlayingIsAnActivityOnlyWhilePlaying() {
        // The module reads the repository's state; the mapping it uses is the wing text and label.
        val activity = app.ufuq.core.LiveActivity(
            "media.now-playing", MediaModule.ID, ActivitySource.NOW_PLAYING, MediaFormat.wing(playing.title),
            "Now playing: Mishary, Alafasy",
        )
        assertEquals("♪ Mishary", activity.text)
        assertNotNull(app.ufuq.core.ActivityArbiter().ranked(listOf(activity), java.time.Instant.EPOCH).firstOrNull())
    }

    private fun contrast(a: Color, b: Color): Double {
        val (hi, lo) = listOf(a.luminance(), b.luminance()).sortedDescending()
        return (hi + 0.05) / (lo + 0.05)
    }

    @Test fun labelInkIsReadableOnEverySegment() {
        // Inactive track: primary and secondary ink on #26302A.
        assertTrue(contrast(IslandColors.Ink, IslandColors.Track) >= 4.5)
        assertTrue(contrast(IslandColors.Ink2, IslandColors.Track) >= 4.5)
        // Active track: the on-tone ink on mint, amber and red.
        for (level in UsageLevel.entries) {
            val c = contrast(IslandColors.onTone(level), IslandColors.tone(level))
            assertTrue(c >= 4.5, "$level $c")
        }
    }
}
