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

    @Test fun activeTrackLeavesRoomForTheLabel() {
        // 232 dp row: 16 chrome + 136 minimum track leaves 80 dp for the active part.
        assertEquals(0f, SliderMath.activeWidthDp(0f, 232f))
        assertEquals(40f, SliderMath.activeWidthDp(0.5f, 232f))
        assertEquals(80f, SliderMath.activeWidthDp(1f, 232f))
        assertEquals(12f, SliderMath.activeWidthDp(0.01f, 232f)) // visible, not a sliver
        assertEquals(0f, SliderMath.activeWidthDp(0.5f, 140f)) // no room at all
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
        assertEquals("1:12", s.trailing)
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

    @Test fun pillShowsPrayerLeftAndCountdownRightWhenThereIsNoAi() {
        val pill = assertNotNull(PillMapper.from(WingLayout(left = prayerActivity()), now))
        assertEquals("Ashar 15:12", pill.left)
        assertEquals("1:12", pill.right)
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
}
