package app.ufuq.desktop.island

import app.ufuq.core.prayer.FIVE_PRAYERS
import app.ufuq.core.prayer.PrayerModule
import app.ufuq.core.prayer.PrayerSnapshot
import app.ufuq.core.prayer.PrayerTimeSlot
import app.ufuq.core.prayer.displayName
import app.ufuq.core.prayer.prayer
import java.time.Duration
import java.time.Instant

// TODO: duplicated from :app (app.ufuq.android.prayer.PrayerProgress); extract to a KMP :island-ui module later.

/** The maths behind the slider: where [now] sits between two moments. */
object SliderMath {
    /** 0..1; 0 when the span is empty or [now] is before [start], 1 once [end] has passed. */
    fun fraction(now: Instant, start: Instant, end: Instant): Float {
        val span = Duration.between(start, end).toMillis()
        if (span <= 0) return 0f
        return (Duration.between(start, now).toMillis().toFloat() / span).coerceIn(0f, 1f)
    }
}

/** "1:12" from 10 minutes up; "04:32" under 10 minutes. */
object Countdown {
    fun format(remaining: Duration): String {
        val seconds = (remaining.seconds + if (remaining.nano > 0) 1 else 0).coerceAtLeast(0)
        if (seconds < 600) return "%02d:%02d".format(seconds / 60, seconds % 60)
        val minutes = (seconds + 59) / 60
        return "%d:%02d".format(minutes / 60, minutes % 60)
    }
}

/** The next prayer and the stretch since the previous one, for the slider. */
data class PrayerProgress(
    val name: String,
    val previous: Instant,
    val next: Instant,
    val now: Instant,
    val location: String = "",
) {
    val fraction: Float get() = SliderMath.fraction(now, previous, next)
    val percent: Int get() = (fraction * 100).toInt()
    val remaining: Duration get() = Duration.between(now, next).let { if (it.isNegative) Duration.ZERO else it }
    val countdown: String get() = Countdown.format(remaining)

    companion object {
        fun at(now: Instant, module: PrayerModule): PrayerProgress? {
            val snap = module.snapshot(now) ?: return null
            return from(now, snap, previousOf = { module.snapshot(now.minus(Duration.ofDays(1))) })
        }

        /** [previousOf] gives yesterday's snapshot, only asked for before today's Fajr. */
        fun from(now: Instant, snap: PrayerSnapshot, previousOf: () -> PrayerSnapshot?): PrayerProgress {
            val next = snap.next
            val todayFive = snap.today.filter { it.slot.prayer in FIVE_PRAYERS }.map { it.time }
            val previous = todayFive.filter { !it.isAfter(now) && it.isBefore(next.time) }.maxOrNull()
                ?: previousOf()?.today?.firstOrNull { it.slot == PrayerTimeSlot.ISHA }?.time
                ?: next.time.minus(Duration.ofHours(5))
            return PrayerProgress(next.displayName, previous, next.time, now, snap.locationName)
        }
    }
}
