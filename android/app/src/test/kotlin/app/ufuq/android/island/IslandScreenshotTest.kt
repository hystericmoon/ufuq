package app.ufuq.android.island

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.ufuq.android.Fixtures
import app.ufuq.android.PhoneWall
import app.ufuq.android.TestStrings
import app.ufuq.android.capture
import app.ufuq.core.UsageLevel
import app.ufuq.core.PeekEvent
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.Duration

/** The island as the overlay draws it, one shot per state in the plan's A2 "done when". Linux renders. */
@RunWith(AndroidJUnit4::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h640dp-xhdpi")
class IslandScreenshotTest {
    private val prayerPage get() = IslandPages.prayer(Fixtures.oneHourTwelve, muted = false, TestStrings)
    private val allPages get() = IslandPages.all(Fixtures.oneHourTwelve, false, null, TestStrings)

    private fun page(pages: List<IslandPageModel>, fontScale: Float = 1f, name: String) =
        capture(name) { PhoneWall(fontScale) { ExpandedIsland(pages, onAction = {}, onDismiss = {}) } }

    @Test fun collapsedPill() = capture("island-01-collapsed-pill") {
        PhoneWall {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
                IslandPill(PillModel("1:12", "", UsageLevel.NORMAL, false, "Ashar in 1 hour 12 minutes"), gapDp = 46, onClick = {}, placement = IslandGeometry.Placement(8, 26))
            }
        }
    }

    @Test fun collapsedPillWithAiAmber() = capture("island-02-collapsed-pill-ai") {
        PhoneWall {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
                IslandPill(PillModel("1:12", "82%", UsageLevel.WARNING, false, "Ashar in 1 hour 12 minutes. Claude 82 percent"), gapDp = 46, onClick = {}, placement = IslandGeometry.Placement(8, 26))
            }
        }
    }

    @Test fun expandedPrayerNormal() = page(allPages, name = "island-03-expanded-a-prayer")

    @Test fun expandedPrayerUnderTenMinutes() =
        page(listOf(IslandPages.prayer(Fixtures.underTen, false, TestStrings)), name = "island-04-expanded-a-under-10min")

    @Test fun expandedPrayerMuted() =
        page(listOf(IslandPages.prayer(Fixtures.oneHourTwelve, true, TestStrings)), name = "island-05-expanded-a-muted")

    @Test fun expandedPrayerFont200() = page(allPages, fontScale = 2f, name = "island-06-expanded-a-font200")

    @Test fun expandedUsageEmpty() = page(listOf(IslandPages.aiUsage(null, TestStrings)), name = "island-07-expanded-b-empty")

    @Test fun expandedUsage82() = page(listOf(IslandPages.aiUsage(AiUsageSample("Claude", 0.82, Duration.ofMinutes(72)), TestStrings)), name = "island-08-expanded-b-82",
    )

    @Test fun expandedUsage96() = page(listOf(IslandPages.aiUsage(AiUsageSample("Claude", 0.96, Duration.ofMinutes(25)), TestStrings)), name = "island-09-expanded-b-96-red",
    )

    private val track = app.ufuq.android.media.MediaState(
        "Mishary", "Alafasy", durationMs = 210_000, positionMs = 84_000, updatedAtElapsedMs = 0, playing = true,
    )

    private fun media(state: app.ufuq.android.media.MediaState?, access: Boolean = false) =
        listOf(IslandPages.media(state, access, TestStrings, 0))

    @Test fun expandedMediaPlaying() = page(media(track), name = "island-10-expanded-c-media-playing")

    @Test fun expandedMediaPaused() = page(media(track.copy(playing = false)), name = "island-13-expanded-c-media-paused")

    @Test fun expandedMediaEmpty() = page(media(null), name = "island-14-expanded-c-media-empty")

    @Test fun expandedMediaFont200() = page(media(track), fontScale = 2f, name = "island-15-expanded-c-media-font200")

    @Test fun expandedEverythingLive() = page(
        listOf(
            prayerPage,
            IslandPages.aiUsage(AiUsageSample("Claude", 0.82, Duration.ofMinutes(72)), TestStrings),
            IslandPages.media(track, true, TestStrings, 0),
        ),
        name = "island-16-expanded-all-live",
    )

    @Test fun peek() = capture("island-11-peek") {
        PhoneWall {
            Box(Modifier.padding(0.dp)) {
                IslandPeek(PeekEvent("p", "prayer", "Ashar", "in 10 minutes, at 15:12"), onDismiss = {}, onHold = {})
            }
        }
    }

    @Test fun reducedMotionRendersTheSame() = capture("island-12-expanded-reduced-motion") {
        PhoneWall {
            androidx.compose.runtime.CompositionLocalProvider(LocalReduceMotion provides true) {
                IslandContent(
                    mode = IslandMode.Expanded, pill = null, pages = allPages, gapDp = 0, onPillClick = {}, onAction = {},
                    onClose = {}, onPeekDismiss = {}, onPeekHold = {},
                )
            }
        }
    }
}
