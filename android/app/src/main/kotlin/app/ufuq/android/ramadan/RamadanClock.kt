package app.ufuq.android.ramadan

import app.ufuq.android.live.LiveUpdateStrategy
import app.ufuq.android.prayer.PrayerProgress
import app.ufuq.android.settings.AppSettings
import app.ufuq.core.prayer.HijriCalendar
import app.ufuq.core.prayer.PrayerSnapshot
import app.ufuq.core.prayer.PrayerTimeSlot
import java.time.Duration
import java.time.Instant
import java.time.LocalDate

enum class RamadanKind(val label: String) { IMSAK("Sahur"), IFTAR("Iftar") }

/** The fasting stretch now: where it started, where it ends, and which Ramadan day it is (when known). */
data class RamadanPhase(val kind: RamadanKind, val previous: Instant, val next: Instant, val day: Int?)

/**
 * Ramadan window maths. The rules are Adwam's (`domain/fasting` and `feature/today/TodayState.kt`
 * `ramadanCard`): Ramadan is Hijri month 9 (Umm al-Qura, with the same -1/0/+1 adjustment); suhur
 * ends at Subuh and Adwam deliberately shows no separate Imsak time (Kemenag's Imsak is Subuh − 10 min, so labelling Subuh "Imsak" would mislead), so [IMSAK_BEFORE_SUBUH_MINUTES]
 * is 0 and the label is "Sahur": the moment the fast begins, at Subuh; the fast is broken at Maghrib.
 */
object RamadanClock {
    const val IMSAK_BEFORE_SUBUH_MINUTES = 0L

    fun ramadanDay(date: LocalDate, hijriAdjustment: Int = 0): Int? =
        HijriCalendar.of(date, hijriAdjustment).takeIf { it.month == 9 }?.day

    fun isActive(date: LocalDate, manual: Boolean, hijriAdjustment: Int = 0): Boolean =
        manual || ramadanDay(date, hijriAdjustment) != null

    fun imsak(today: PrayerSnapshot): Instant? = today.time(PrayerTimeSlot.FAJR)?.minus(Duration.ofMinutes(IMSAK_BEFORE_SUBUH_MINUTES))
    fun iftar(today: PrayerSnapshot): Instant? = today.time(PrayerTimeSlot.MAGHRIB)

    /**
     * Before Subuh: counting down to Imsak (the stretch runs from yesterday's Maghrib). From Subuh to
     * Maghrib: counting down to Iftar, the bar running Imsak to Iftar. After Maghrib: null, and the
     * normal next-prayer content (Isya) shows. [yesterdayMaghrib] is asked only before Subuh.
     */
    fun phaseAt(
        now: Instant,
        today: PrayerSnapshot,
        manual: Boolean,
        hijriAdjustment: Int = 0,
        yesterdayMaghrib: () -> Instant? = { null },
    ): RamadanPhase? {
        if (!isActive(today.date, manual, hijriAdjustment)) return null
        val imsak = imsak(today) ?: return null
        val iftar = iftar(today) ?: return null
        val day = ramadanDay(today.date, hijriAdjustment)
        return when {
            now.isBefore(imsak) -> RamadanPhase(RamadanKind.IMSAK, yesterdayMaghrib() ?: imsak.minus(Duration.ofHours(8)), imsak, day)
            now.isBefore(iftar) -> RamadanPhase(RamadanKind.IFTAR, imsak, iftar, day)
            else -> null
        }
    }
}

private fun PrayerSnapshot.time(slot: PrayerTimeSlot): Instant? = today.firstOrNull { it.slot == slot }?.time

/** Plugs Ramadan into the Live Update: "Sahur 04:21" (sahur ends at Subuh) before Subuh, "Iftar 17:58" until Maghrib. */
class RamadanLiveStrategy(private val yesterday: (Instant) -> PrayerSnapshot?) : LiveUpdateStrategy {
    override fun progress(now: Instant, settings: AppSettings, snapshot: PrayerSnapshot): PrayerProgress? {
        val phase = RamadanClock.phaseAt(
            now, snapshot, settings.ramadanManual,
            yesterdayMaghrib = { yesterday(now.minus(Duration.ofDays(1)))?.time(PrayerTimeSlot.MAGHRIB) },
        ) ?: return null
        return PrayerProgress(phase.kind.label, phase.previous, phase.next, now, snapshot.locationName, snapshot.zone)
    }
}
