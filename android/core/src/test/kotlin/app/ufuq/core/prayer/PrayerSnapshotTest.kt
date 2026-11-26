package app.ufuq.core.prayer

import org.junit.Test
import java.time.Duration
import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.test.assertEquals
import kotlin.test.assertNull

class PrayerSnapshotTest {
    private val zone = ZoneId.of("Asia/Jakarta")
    private val calculator = PrayerCalculator()
    private fun at(d: Int, h: Int, m: Int) = LocalDateTime.of(2026, 10, d, h, m).atZone(zone).toInstant()

    @Test
    fun `next prayer at noon is Asr, with today's six times`() {
        val s = PrayerSnapshots.at(at(21, 12, 0), PrayerLocation.JAKARTA, calculator = calculator)!!
        assertEquals(Prayer.ASR, s.next.prayer)
        assertEquals(PrayerTimeSlot.ASR, s.nextSlot)
        assertEquals(PrayerTimeSlot.entries, s.today.map { it.slot })
    }

    @Test
    fun `Dhuhr on Friday is Jumuah`() {
        val s = PrayerSnapshots.at(at(23, 9, 0), PrayerLocation.JAKARTA, calculator = calculator)!!
        assertEquals(Prayer.JUMUAH, s.next.prayer)
    }

    @Test
    fun `after Isha the next prayer is tomorrow's Fajr, not one of today's slots`() {
        val s = PrayerSnapshots.at(at(21, 23, 0), PrayerLocation.JAKARTA, calculator = calculator)!!
        assertEquals(Prayer.FAJR, s.next.prayer)
        assertEquals(22, s.next.time.atZone(zone).dayOfMonth)
        assertNull(s.nextSlot)
    }

    @Test
    fun `refresh after Isha is midnight`() {
        val now = at(21, 23, 0)
        val s = PrayerSnapshots.at(now, PrayerLocation.JAKARTA, calculator = calculator)!!
        assertEquals(LocalDateTime.of(2026, 10, 22, 0, 0), PrayerSnapshots.nextRefresh(now, s).atZone(zone).toLocalDateTime())
    }

    @Test
    fun `no snapshot without a location`() {
        assertNull(PrayerSnapshots.at(at(21, 12, 0), null, calculator = calculator))
    }

    @Test
    fun `Dhuhr on Friday is named Jumat, Subuh and Ashar keep their names`() {
        val friday = PrayerSnapshots.at(at(23, 9, 0), PrayerLocation.JAKARTA, calculator = calculator)!!
        assertEquals("Jumat", friday.next.displayName)
        assertEquals("Ashar", PrayerSnapshots.at(at(21, 12, 0), PrayerLocation.JAKARTA, calculator = calculator)!!.next.displayName)
    }

    @Test
    fun `terbit is never the next prayer`() {
        val s = PrayerSnapshots.at(at(21, 4, 30), PrayerLocation.JAKARTA, calculator = calculator)!!
        assertEquals(Prayer.DHUHR, s.next.prayer)
    }

    @Test
    fun `refresh before Isha is the next time`() {
        val now = at(21, 12, 0)
        val s = PrayerSnapshots.at(now, PrayerLocation.JAKARTA, calculator = calculator)!!
        assertEquals(s.next.time, PrayerSnapshots.nextRefresh(now, s))
    }

    @Test
    fun `countdown remaining is never negative`() {
        val now = at(21, 12, 0)
        val s = PrayerSnapshots.at(now, PrayerLocation.JAKARTA, calculator = calculator)!!
        assertEquals(Duration.between(now, s.next.time), s.next.remaining(now))
        assertEquals(Duration.ZERO, s.next.remaining(s.next.time.plusSeconds(5)))
    }

    @Test
    fun `no snapshot in the polar night`() {
        val pole = PrayerLocation("Pole", 85.0, 0.0, ZoneId.of("UTC"))
        val now = LocalDateTime.of(2026, 6, 21, 12, 0).atZone(pole.zone).toInstant()
        assertNull(PrayerSnapshots.at(now, pole, CalculationSettings(method = CalcMethod.MWL)))
    }
}
