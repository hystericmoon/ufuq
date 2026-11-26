package app.ufuq.android.activities

import app.ufuq.core.ActivitySource
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class OngoingMapperTest {
    private val own = "app.ufuq.android"
    private val s = TestActivityStrings

    @Test fun everyQualifyingCategoryIsIncluded() {
        for (c in listOf("navigation", "transport", "progress", "stopwatch", "workout", "location_sharing")) {
            assertTrue(OngoingMapper.qualifies(ongoing(category = c), own), c)
        }
    }

    @Test fun otherCategoriesAndPlainOngoingAreNotIncluded() {
        for (c in listOf(null, "msg", "email", "service", "social", "reminder")) {
            assertFalse(OngoingMapper.qualifies(ongoing(category = c), own), c.toString())
        }
    }

    @Test fun mustBeOngoing() {
        assertFalse(OngoingMapper.qualifies(ongoing(category = "navigation", ongoing = false), own))
    }

    @Test fun promotedProgressStyleAndDeterminateBarQualifyWithoutCategory() {
        assertTrue(OngoingMapper.qualifies(ongoing { it.copy(isPromoted = true) }, own))
        assertTrue(OngoingMapper.qualifies(ongoing { it.copy(hasProgressStyle = true) }, own))
        assertTrue(OngoingMapper.qualifies(ongoing { it.copy(progressMax = 100, progress = 40) }, own))
    }

    @Test fun indeterminateBarAloneDoesNotQualify() {
        assertFalse(OngoingMapper.qualifies(ongoing { it.copy(progressMax = 0, progressIndeterminate = true) }, own))
        assertFalse(OngoingMapper.qualifies(ongoing { it.copy(progressMax = 100, progressIndeterminate = true) }, own))
    }

    @Test fun mediaUfuqAndCallsAreExcluded() {
        assertFalse(OngoingMapper.qualifies(ongoing(category = "transport") { it.copy(isMedia = true) }, own))
        assertFalse(OngoingMapper.qualifies(ongoing(pkg = own, category = "progress"), own))
        assertFalse(OngoingMapper.qualifies(ongoing(category = "call") { it.copy(isCall = true, isPromoted = true) }, own))
    }

    @Test fun progressMaths() {
        fun f(max: Int, cur: Int, ind: Boolean = false) = OngoingMapper.progressFraction(ongoing { it.copy(progressMax = max, progress = cur, progressIndeterminate = ind) })
        assertEquals(0.25, f(200, 50))
        assertEquals(1.0, f(10, 12)) // over max clamps
        assertEquals(0.0, f(10, -3)) // negative clamps
        assertNull(f(0, 0))
        assertNull(f(100, 50, ind = true))
    }

    @Test fun countdownChronometerGivesMinutesLeftRoundedUp() {
        val n = ongoing(category = "transport") { it.copy(usesChronometer = true, chronometerCountDown = true, whenMillis = NOW.toEpochMilli() + 5 * 60_000 + 1_000) }
        val a = OngoingMapper.toActivity(n, NOW, s)
        assertEquals("Ride app · 6 min", a.text)
        assertEquals("Ride app, 6 minutes left", a.accessibilityLabel)
        assertEquals(ActivitySource.OTHER, a.source)
        assertEquals("other:k1", a.id)
        assertFalse(a.isAlert)
    }

    @Test fun countUpChronometerGivesMinutesElapsed() {
        val n = ongoing(category = "stopwatch") { it.copy(usesChronometer = true, whenMillis = NOW.toEpochMilli() - 12 * 60_000 - 30_000) }
        val a = OngoingMapper.toActivity(n, NOW, s)
        assertEquals("Ride app · 12 min", a.text)
        assertEquals("Ride app, 12 minutes elapsed", a.accessibilityLabel)
    }

    @Test fun determinateProgressGivesPercent() {
        val a = OngoingMapper.toActivity(ongoing { it.copy(progressMax = 8, progress = 3) }, NOW, s)
        assertEquals("Ride app · 37%", a.text)
        assertEquals("Ride app, 37 percent", a.accessibilityLabel)
    }

    @Test fun titleIsTheLastResortAndIsShortened() {
        val a = OngoingMapper.toActivity(ongoing(category = "navigation") { it.copy(title = "Turn left on Main Street now") }, NOW, s)
        assertEquals("Ride app · Turn left on Main S…", a.text)
        assertEquals("Ride app, Turn left on Main Street now", a.accessibilityLabel)
        assertEquals("Ride app", OngoingMapper.toActivity(ongoing(category = "navigation"), NOW, s).text)
    }

    @Test fun expiredCountdownFallsBackToNextDetail() {
        val n = ongoing { it.copy(usesChronometer = true, chronometerCountDown = true, whenMillis = NOW.toEpochMilli() - 1000, progressMax = 10, progress = 5) }
        assertEquals("Ride app · 50%", OngoingMapper.toActivity(n, NOW, s).text)
    }

    @Test fun allowListIsOffByDefault() {
        val list = listOf(ongoing(category = "navigation"))
        assertTrue(ActivityAllowList.filter(list, enabled = true, allowed = emptySet(), ownPackage = own).isEmpty())
        assertTrue(ActivityAllowList.filter(list, enabled = false, allowed = setOf("com.example.ride"), ownPackage = own).isEmpty())
    }

    @Test fun allowListKeepsOnlyChosenQualifyingAppsNewestFirst() {
        val a = ongoing("a", "com.a", "A", "navigation") { it.copy(postTimeMillis = 10) }
        val b = ongoing("b", "com.b", "B", "progress") { it.copy(postTimeMillis = 20) }
        val c = ongoing("c", "com.c", "C", "navigation")
        val plain = ongoing("d", "com.a", "A", "msg")
        val out = ActivityAllowList.filter(listOf(a, b, c, plain), true, setOf("com.a", "com.b"), own)
        assertEquals(listOf("b", "a"), out.map { it.key })
    }

    @Test fun settingsListUnionsSeenAndAllowedSortedByLabel() {
        val seen = listOf(SeenApp("com.z", "Zed"), SeenApp("com.b", "Bee"))
        val listed = ActivityAllowList.listed(seen, setOf("com.b", "com.gone"))
        assertEquals(listOf("Bee", "com.gone", "Zed"), listed.map { it.label })
    }

    @Test fun moduleShowsNothingUntilEnabledAndAllowed() {
        val module = OtherAppsModule(s, own)
        val n = ongoing(category = "navigation") { it.copy(title = "Go") }
        module.update(listOf(n), enabled = true, allowed = emptySet())
        assertNull(module.collapsedActivity(NOW))
        module.update(listOf(n), enabled = true, allowed = setOf("com.example.ride"))
        assertNotNull(module.collapsedActivity(NOW))
        assertTrue(module.isEnabled)
        module.update(listOf(n), enabled = false, allowed = setOf("com.example.ride"))
        assertFalse(module.isEnabled)
        assertNull(module.page(NOW))
    }

    @Test fun pageOpensTheSourceAppWithItsName() {
        var opened = false
        val module = OtherAppsModule(s, own)
        module.update(listOf(ongoing(label = "Gojek", category = "transport") { it.copy(open = { opened = true }) }), true, setOf("com.example.ride"))
        assertEquals("Open Gojek", module.page(NOW)!!.buttonLabel)
        module.openCurrent()
        assertTrue(opened)
    }

    @Test fun determinatePageFillsAndIndeterminatePageIsLabelOnly() {
        val det = ActivityPages.page(ongoing(label = "Delivery app") { it.copy(progressMax = 4, progress = 3) }, NOW, s)
        assertEquals(0.75f, det.slider.fraction)
        assertEquals("75 percent", det.slider.stateText)
        val ind = ActivityPages.page(ongoing(label = "Ride app", category = "transport") { it.copy(progressIndeterminate = true, title = "Driver arriving") }, NOW, s)
        assertEquals(0f, ind.slider.fraction)
        assertEquals("Driver arriving", ind.slider.secondary)
        assertEquals("Ride app, Driver arriving", ind.slider.description)
    }
}
