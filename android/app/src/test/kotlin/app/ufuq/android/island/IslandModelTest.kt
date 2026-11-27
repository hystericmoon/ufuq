package app.ufuq.android.island

import app.ufuq.android.Fixtures
import app.ufuq.android.TestStrings
import app.ufuq.android.prayer.Countdown
import app.ufuq.android.prayer.PrayerProgress
import app.ufuq.android.prayer.SliderMath
import app.ufuq.core.ActivitySource
import app.ufuq.core.LiveActivity
import app.ufuq.core.UsageLevel
import app.ufuq.core.WingLayout
import app.ufuq.core.prayer.PrayerLocation
import app.ufuq.core.prayer.PrayerModule
import java.time.Duration
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class IslandModelTest {
    private val now = Fixtures.ashar.minus(Duration.ofMinutes(72))

    private fun prayerActivity(text: String = "Ashar 15:12", alert: Boolean = false) = LiveActivity(
        id = "prayer.next", moduleId = "prayer", source = ActivitySource.PRAYER, text = text,
        accessibilityLabel = "Ashar in 1 hour 12 minutes", isAlert = alert, deadline = Fixtures.ashar,
    )

    private fun aiActivity(fraction: Double) = LiveActivity(
        id = "ai", moduleId = "ai", source = ActivitySource.AI_USAGE, text = "${(fraction * 100).toInt()}%",
        accessibilityLabel = "Claude Work, ${(fraction * 100).toInt()} percent", usageFraction = fraction,
    )

    // --- slider maths ---

    @Test fun fractionIsElapsedShareBetweenPreviousAndNext() {
        assertEquals(0.5f, SliderMath.fraction(Instant.ofEpochSecond(50), Instant.ofEpochSecond(0), Instant.ofEpochSecond(100)))
        assertEquals(0f, SliderMath.fraction(Instant.ofEpochSecond(-5), Instant.ofEpochSecond(0), Instant.ofEpochSecond(100)))
        assertEquals(1f, SliderMath.fraction(Instant.ofEpochSecond(500), Instant.ofEpochSecond(0), Instant.ofEpochSecond(100)))
        assertEquals(0f, SliderMath.fraction(Instant.ofEpochSecond(5), Instant.ofEpochSecond(10), Instant.ofEpochSecond(10)))
    }

    @Test fun mockupPrayerFractionIs65Percent() {
        // Dzuhur 11:46 to Ashar 15:12 is 206 min; 72 min are left, so 134 min have passed.
        assertEquals(65, Fixtures.oneHourTwelve.percent)
    }

    @Test fun sliderShowsItsTrueValue() {
        val total = 280f
        val travel = total - 4f
        assertEquals(0f, SliderMath.handleLeftDp(0f, total))
        assertEquals(0f, SliderMath.activeWidthDp(0f, total))
        assertEquals(0.82f * travel, SliderMath.handleLeftDp(0.82f, total), 0.001f) // 82% of the travel
        assertEquals(0.82f * travel - 6f, SliderMath.activeWidthDp(0.82f, total), 0.001f)
        assertEquals(travel, SliderMath.handleLeftDp(1f, total)) // the handle stays inside the row
        assertEquals(total, SliderMath.inactiveStartDp(1f, total))
        assertEquals(0f, SliderMath.activeWidthDp(0.01f, total)) // handle within the first gap: no sliver
        assertEquals(travel, SliderMath.handleLeftDp(7f, total)) // clamped
        // Active + gap + handle + gap + inactive always add up to the row.
        for (f in listOf(0f, 0.3f, 0.82f, 0.96f, 1f)) {
            val start = SliderMath.inactiveStartDp(f, total)
            assertTrue(start <= total && SliderMath.handleLeftDp(f, total) + 4f <= total)
        }
    }

    @Test fun draggingMapsBackToTheFraction() {
        val total = 280f
        for (f in listOf(0f, 0.25f, 0.82f, 1f)) {
            val x = SliderMath.handleLeftDp(f, total) + 2f // the handle's centre
            assertEquals(f, SliderMath.fractionAt(x, total), 0.001f)
        }
        assertEquals(0f, SliderMath.fractionAt(-50f, total))
        assertEquals(1f, SliderMath.fractionAt(900f, total))
    }

    @Test fun countdownIsHoursMinutesFromTenMinutesAndMinutesSecondsBelow() {
        assertEquals("1:12", Countdown.format(Duration.ofMinutes(72)))
        assertEquals("0:45", Countdown.format(Duration.ofMinutes(45)))
        assertEquals("0:10", Countdown.format(Duration.ofMinutes(10)))
        assertEquals("09:59", Countdown.format(Duration.ofSeconds(599)))
        assertEquals("04:32", Countdown.format(Duration.ofSeconds(272)))
        assertEquals("00:00", Countdown.format(Duration.ZERO))
        assertEquals("1:12", Countdown.format(Duration.ofMinutes(71).plusSeconds(30))) // rounds up
        assertEquals("1h 12m", Countdown.short(Duration.ofMinutes(72)))
        assertEquals("4m 32s", Countdown.short(Duration.ofSeconds(272)))
    }

    @Test fun progressBeforeFajrUsesYesterdaysIsha() {
        val module = PrayerModule(PrayerLocation.JAKARTA)
        val now = Instant.parse("2026-11-26T20:00:00Z") // 03:00 in Jakarta, before Subuh
        val progress = assertNotNull(PrayerProgress.at(now, module))
        assertEquals("Subuh", progress.name)
        assertTrue(progress.previous.isBefore(now), "previous prayer is yesterday's Isya")
        assertTrue(progress.fraction in 0f..1f)
    }

    // --- pages ---

    @Test fun prayerPageMapsLabelCountdownAndMuteButton() {
        val page = IslandPages.prayer(Fixtures.oneHourTwelve, muted = false, TestStrings)
        assertEquals(IslandPageId.PRAYER, page.id)
        assertEquals("Ashar", page.slider.label)
        assertEquals("1:12", page.slider.secondary)
        assertEquals(IslandIcon.SUN, page.slider.endIcon)
        assertEquals(UsageLevel.NORMAL, page.slider.level)
        assertEquals("65 percent", page.slider.stateText)
        assertTrue("1 hour 12 minutes" in page.slider.description)
        assertEquals("Mute adhan", page.buttonLabel)
        assertEquals(IslandIcon.BELL, page.buttonIcon)
        assertEquals(ButtonAction.TOGGLE_MUTE, page.buttonAction)
    }

    @Test fun prayerPageUnderTenMinutesShowsMinutesAndSeconds() {
        val page = IslandPages.prayer(Fixtures.underTen, muted = false, TestStrings)
        assertEquals("04:32", page.slider.secondary)
    }

    @Test fun mutedPageOffersUnmute() {
        val page = IslandPages.prayer(Fixtures.oneHourTwelve, muted = true, TestStrings)
        assertEquals("Unmute adhan", page.buttonLabel)
        assertEquals(IslandIcon.BELL_OFF, page.buttonIcon)
    }

    @Test fun usagePageIsAmberFrom80AndRedFrom95WithAPercentAlways() {
        fun level(f: Double) = IslandPages.aiUsage(AiUsageSample("Claude", f), TestStrings).slider
        assertEquals(UsageLevel.NORMAL, level(0.79).level)
        assertEquals(UsageLevel.WARNING, level(0.80).level)
        assertEquals(UsageLevel.WARNING, level(0.82).level)
        assertEquals(UsageLevel.CRITICAL, level(0.95).level)
        val s = IslandPages.aiUsage(AiUsageSample("Claude", 0.82, Duration.ofMinutes(72)), TestStrings).slider
        assertEquals("82%", s.secondary)
        assertEquals("Resets in 1:12", s.trailing)
        assertEquals("82 percent", s.stateText) // never colour alone
        assertTrue("82 percent" in s.description && "resets in 1 hour 12 minutes" in s.description)
    }

    @Test fun usagePageWithoutDataIsThePairingEmptyState() {
        val page = IslandPages.aiUsage(null, TestStrings)
        assertEquals(0f, page.slider.fraction)
        assertEquals("Pair with your Mac", page.slider.label)
        assertEquals(ButtonAction.OPEN_APP, page.buttonAction)
    }

    @Test fun allPagesAreInTheFixedOrderAndPrayerIsMissingWithoutTimes() {
        val ids = IslandPages.all(Fixtures.oneHourTwelve, false, null, TestStrings).map { it.id }
        assertEquals(listOf(IslandPageId.PRAYER, IslandPageId.AI_USAGE, IslandPageId.MEDIA), ids)
        assertEquals(listOf(IslandPageId.AI_USAGE, IslandPageId.MEDIA), IslandPages.all(null, false, null, TestStrings).map { it.id })
    }

    // --- pill ---

    @Test fun pillShowsOnlyTheCountdownWhenThereIsNoAi() {
        val pill = assertNotNull(PillMapper.from(WingLayout(left = prayerActivity()), now))
        assertEquals("1:12", pill.left) // countdown only (owner, 27 Nov)
        assertEquals("", pill.right)
        assertEquals(UsageLevel.NORMAL, pill.rightLevel)
        assertEquals("Ashar in 1 hour 12 minutes", pill.description)
    }

    @Test fun pillRightWingIsAiUsageWithItsLevel() {
        val pill = assertNotNull(PillMapper.from(WingLayout(left = prayerActivity(), right = aiActivity(0.82)), now))
        assertEquals("82%", pill.right)
        assertEquals(UsageLevel.WARNING, pill.rightLevel)
        assertTrue("Claude Work, 82 percent" in pill.description)
    }

    @Test fun pillFallsBackToTheRotatingActivityAndFlagsAlerts() {
        val rotating = LiveActivity("np", "media", ActivitySource.NOW_PLAYING, "Mishary", "Playing Mishary")
        val pill = assertNotNull(PillMapper.from(WingLayout(left = prayerActivity("Ashar now", alert = true), rotating = rotating), now))
        assertEquals("Mishary", pill.right)
        assertTrue(pill.isAlert)
    }

    @Test fun pillIsNullWhenNothingToShow() {
        assertNull(PillMapper.from(WingLayout(), now))
    }

    @Test fun cameraGapFollowsTheCutout() {
        assertEquals(0, IslandGeometry.gapDp(null, 3f))
        assertEquals(0, IslandGeometry.gapDp(0, 3f))
        assertEquals(46, IslandGeometry.gapDp(102, 3f)) // 34 dp + 2 x 6
    }

    @Test fun pillHugsTheCameraHole() {
        // An 18 dp hole from 12 dp to 30 dp (3x density): 26 dp pill centred on its middle (21 dp).
        assertEquals(IslandGeometry.Placement(topDp = 8, heightDp = 26), IslandGeometry.placement(36, 90, 3f))
        // Tiny or huge holes clamp to 24..30 dp.
        assertEquals(24, IslandGeometry.placement(30, 45, 3f).heightDp)
        assertEquals(30, IslandGeometry.placement(0, 120, 3f).heightDp)
        // No cutout: 26 dp, 4 dp from the top.
        assertEquals(IslandGeometry.Placement(4, 26), IslandGeometry.placement(null, null, 3f))
    }

    @Test fun onlyLiveRowsAreVisible() {
        val pages = IslandPages.all(Fixtures.oneHourTwelve, false, null, TestStrings)
        assertEquals(listOf(IslandPageId.PRAYER), IslandPages.visible(pages, unpaired = true).map { it.id })
        assertEquals(listOf(IslandPageId.PRAYER, IslandPageId.AI_USAGE), IslandPages.visible(pages, unpaired = false).map { it.id })
        val playing = app.ufuq.android.media.MediaState("Mishary", durationMs = 210_000, playing = true)
        val withMedia = IslandPages.all(Fixtures.oneHourTwelve, false, null, TestStrings, mediaState = playing, mediaAccess = true)
        assertEquals(listOf(IslandPageId.PRAYER, IslandPageId.MEDIA), IslandPages.visible(withMedia, unpaired = true).map { it.id })
        // Nothing live (no location yet): everything shows rather than an empty card.
        val none = IslandPages.all(null, false, null, TestStrings)
        assertEquals(none, IslandPages.visible(none, unpaired = true))
    }

    @Test fun prayerRowHasTimePlaceAndTheRestOfToday() {
        val page = IslandPages.prayer(Fixtures.oneHourTwelveFull, false, TestStrings)
        assertEquals("15:12 · Jakarta", page.slider.trailing)
        assertEquals("Then Maghrib 17:58 · Isya 19:12", page.footnote)
        assertTrue(page.slider.description.endsWith("Then Maghrib 17:58 · Isya 19:12"), page.slider.description)
    }
}
