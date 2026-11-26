package app.ufuq.core.prayer

import org.junit.Test
import java.time.LocalDate
import kotlin.test.assertEquals

class HijriCalendarTest {
    @Test
    fun `adjustment shifts by one day and is clamped`() {
        val date = LocalDate.of(2026, 10, 21)
        val base = HijriCalendar.of(date, 0)
        val plus = HijriCalendar.of(date, 1)
        assertEquals(HijriCalendar.of(date.plusDays(1), 0), plus)
        assertEquals(HijriCalendar.of(date, 5), plus)
        assertEquals(HijriCalendar.of(date.minusDays(1), 0), HijriCalendar.of(date, -1))
        assert(base.year > 1440)
    }

    @Test
    fun `known Umm al-Qura date`() {
        // 1 Muharram 1447 AH (Umm al-Qura) fell on 2025-06-26.
        assertEquals(HijriDate(1, 1, 1447), HijriCalendar.of(LocalDate.of(2025, 6, 26), 0))
        assertEquals(12, HijriCalendar.of(LocalDate.of(2025, 6, 25), 0).month)
    }
}
