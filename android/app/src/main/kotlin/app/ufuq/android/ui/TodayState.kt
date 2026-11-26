package app.ufuq.android.ui

import app.ufuq.android.prayer.Countdown
import app.ufuq.android.prayer.PrayerProgress
import app.ufuq.core.prayer.Prayer
import app.ufuq.core.prayer.PrayerFormat
import app.ufuq.core.prayer.PrayerModule
import app.ufuq.core.prayer.PrayerSnapshot
import app.ufuq.core.prayer.PrayerTimeSlot
import app.ufuq.core.prayer.displayName
import java.time.DayOfWeek
import java.time.Instant

data class TodayRow(val name: String, val time: String, val isNext: Boolean)

/** The Today screen's data: six times with the next one marked, plus the countdown. */
data class TodayState(
    val location: String,
    val rows: List<TodayRow>,
    val nextName: String,
    val countdown: String,
    val countdownSpoken: String,
    val underTenMinutes: Boolean,
) {
    companion object {
        fun from(now: Instant, snapshot: PrayerSnapshot, progress: PrayerProgress): TodayState {
            val nextSlot = snapshot.nextSlot
            val friday = snapshot.date.dayOfWeek == DayOfWeek.FRIDAY
            val rows = snapshot.today.map { st ->
                val name = when (st.slot) {
                    PrayerTimeSlot.SUNRISE -> "Terbit"
                    PrayerTimeSlot.DHUHR -> if (friday) Prayer.JUMUAH.displayName else Prayer.DHUHR.displayName
                    else -> nameOf(st.slot)
                }
                TodayRow(name, PrayerFormat.clock(st.time, snapshot.zone), isNext = st.slot == nextSlot)
            }
            return TodayState(
                location = snapshot.locationName,
                rows = rows,
                nextName = progress.name,
                countdown = progress.countdown,
                countdownSpoken = PrayerFormat.spoken(progress.remaining),
                underTenMinutes = Countdown.isUnderTenMinutes(progress.remaining),
            )
        }

        fun at(now: Instant, module: PrayerModule): TodayState? {
            val snapshot = module.snapshot(now) ?: return null
            val progress = PrayerProgress.at(now, module) ?: return null
            return from(now, snapshot, progress)
        }

        private fun nameOf(slot: PrayerTimeSlot): String = when (slot) {
            PrayerTimeSlot.FAJR -> Prayer.FAJR.displayName
            PrayerTimeSlot.ASR -> Prayer.ASR.displayName
            PrayerTimeSlot.MAGHRIB -> Prayer.MAGHRIB.displayName
            PrayerTimeSlot.ISHA -> Prayer.ISHA.displayName
            PrayerTimeSlot.DHUHR -> Prayer.DHUHR.displayName
            PrayerTimeSlot.SUNRISE -> "Terbit"
        }
    }
}
