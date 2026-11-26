package app.ufuq.android.ramadan

import app.ufuq.android.settings.AppSettings
import app.ufuq.core.prayer.PrayerLocation
import app.ufuq.core.prayer.PrayerSnapshot
import app.ufuq.core.prayer.PrayerSnapshots
import app.ufuq.core.prayer.PrayerTimeSlot
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class RamadanClockTest {
    private val jakarta = PrayerLocation.JAKARTA

    // Ramadan 1448 is expected to start around 18 Feb 2026 (Umm al-Qura); 1447 in 2026-02-18. Compute, do not hard-code.
    private val firstOfRamadan: LocalDate = generateSequence(LocalDate.of(2026, 1, 1)) { it.plusDays(1) }
        .first { RamadanClock.ramadanDay(it) == 1 }

    private fun snap(now: Instant) = assertNotNull(PrayerSnapshots.at(now, jakarta))
    private fun at(date: LocalDate, slot: PrayerTimeSlot, offsetMinutes: Long = 0): Instant =
        snap(date.atTime(12, 0).atZone(jakarta.zone).toInstant()).today.first { it.slot == slot }.time.plus(Duration.ofMinutes(offsetMinutes))

    @Test fun ramadanIsHijriMonthNineAndOnlyThen() {
        assertEquals(1, RamadanClock.ramadanDay(firstOfRamadan))
        assertNull(RamadanClock.ramadanDay(firstOfRamadan.minusDays(1)))
        assertEquals(29, (0..29).count { RamadanClock.ramadanDay(firstOfRamadan.plusDays(it.toLong())) != null }.let { it - 1 })
        assertNull(RamadanClock.ramadanDay(firstOfRamadan.plusDays(31)))
    }

    @Test fun manualModeWorksOutsideRamadan() {
        val outside = firstOfRamadan.minusDays(40)
        assertFalse(RamadanClock.isActive(outside, manual = false))
        assertTrue(RamadanClock.isActive(outside, manual = true))
    }

    @Test fun beforeSubuhItCountsDownToImsakFromYesterdaysMaghrib() {
        val d = firstOfRamadan.plusDays(3)
        val now = at(d, PrayerTimeSlot.FAJR, -30)
        val yesterdayMaghrib = at(d.minusDays(1), PrayerTimeSlot.MAGHRIB)
        val phase = assertNotNull(RamadanClock.phaseAt(now, snap(now), manual = false, yesterdayMaghrib = { yesterdayMaghrib }))
        assertEquals(RamadanKind.IMSAK, phase.kind)
        assertEquals(at(d, PrayerTimeSlot.FAJR), phase.next)
        assertEquals(yesterdayMaghrib, phase.previous)
        assertEquals(4, phase.day)
    }

    @Test fun fromSubuhToMaghribItCountsDownToIftarWithAnImsakToIftarBar() {
        val d = firstOfRamadan.plusDays(3)
        val subuh = at(d, PrayerTimeSlot.FAJR)
        val maghrib = at(d, PrayerTimeSlot.MAGHRIB)
        for (now in listOf(subuh, subuh.plusSeconds(1), maghrib.minusSeconds(1))) {
            val phase = assertNotNull(RamadanClock.phaseAt(now, snap(now), manual = false))
            assertEquals(RamadanKind.IFTAR, phase.kind)
            assertEquals(subuh, phase.previous)
            assertEquals(maghrib, phase.next)
        }
    }

    @Test fun afterMaghribTheNormalNextPrayerShowsAgain() {
        val d = firstOfRamadan.plusDays(3)
        val now = at(d, PrayerTimeSlot.MAGHRIB)
        assertNull(RamadanClock.phaseAt(now, snap(now), manual = false))
        val later = at(d, PrayerTimeSlot.ISHA)
        assertNull(RamadanClock.phaseAt(later, snap(later), manual = false))
    }

    @Test fun outsideRamadanThereIsNoPhaseUnlessManual() {
        val d = firstOfRamadan.minusDays(40)
        val now = at(d, PrayerTimeSlot.DHUHR)
        assertNull(RamadanClock.phaseAt(now, snap(now), manual = false))
        assertEquals(RamadanKind.IFTAR, RamadanClock.phaseAt(now, snap(now), manual = true)?.kind)
        assertNull(RamadanClock.phaseAt(now, snap(now), manual = true)?.day)
    }

    @Test fun adwamShowsNoSeparateImsakSoImsakIsSubuh() {
        val now = at(firstOfRamadan, PrayerTimeSlot.DHUHR)
        assertEquals(at(firstOfRamadan, PrayerTimeSlot.FAJR), RamadanClock.imsak(snap(now)))
    }

    @Test fun liveUpdateStrategyNamesTheNextMomentWithItsClock() {
        val d = firstOfRamadan.plusDays(1)
        val now = at(d, PrayerTimeSlot.DHUHR)
        val strategy = RamadanLiveStrategy { snap(it) }
        val p = assertNotNull(strategy.progress(now, AppSettings(), snap(now)))
        assertEquals("Iftar", p.name)
        assertEquals("Jakarta", p.location)
        assertTrue(p.fraction in 0.1f..0.9f)
        val before = at(d, PrayerTimeSlot.FAJR, -20)
        assertEquals("Imsak", strategy.progress(before, AppSettings(), snap(before))?.name)
        val after = at(d, PrayerTimeSlot.ISHA)
        assertNull(strategy.progress(after, AppSettings(), snap(after)))
    }
}
