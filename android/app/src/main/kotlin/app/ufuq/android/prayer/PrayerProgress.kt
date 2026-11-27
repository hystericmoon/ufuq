package app.ufuq.android.prayer

import app.ufuq.core.prayer.FIVE_PRAYERS
import app.ufuq.core.prayer.PrayerModule
import app.ufuq.core.prayer.PrayerSnapshot
import app.ufuq.core.prayer.PrayerTimeSlot
import app.ufuq.core.prayer.displayName
import app.ufuq.core.prayer.prayer
import java.time.Duration
import java.time.Instant

/** The maths behind the slider: where [now] sits between two moments. */
object SliderMath {
    /** 0..1; 0 when the span is empty or [now] is before [start], 1 once [end] has passed. */
    fun fraction(now: Instant, start: Instant, end: Instant): Float {
        val span = Duration.between(start, end).toMillis()
        if (span <= 0) return 0f
        return (Duration.between(start, now).toMillis().toFloat() / span).coerceIn(0f, 1f)
    }

    /**
     * Slider geometry, linear in [fraction] over the whole row. The row is
     * `active, 6 gap, 4 handle, 6 gap, inactive`; the handle's left edge sits at
     * `fraction x (total - 4)`, so 0 puts it at the start, 1 at the end and 0.82 at 82% of its travel.
     * The row never reserves room for the label: the label is drawn over both parts.
     */
    fun handleLeftDp(fraction: Float, totalDp: Float): Float =
        fraction.coerceIn(0f, 1f) * (totalDp - HANDLE_DP).coerceAtLeast(0f)

    /** Width of the filled track left of the handle's gap; 0 near the start (the handle alone). */
    fun activeWidthDp(fraction: Float, totalDp: Float): Float =
        (handleLeftDp(fraction, totalDp) - GAP_DP).coerceAtLeast(0f)

    /** Where the inactive track starts (after the handle and its gap); equals [totalDp] when full. */
    fun inactiveStartDp(fraction: Float, totalDp: Float): Float =
        minOf(totalDp, handleLeftDp(fraction, totalDp) + HANDLE_DP + GAP_DP)

    /** The inverse, for dragging: a touch at [xDp] centres the handle there. */
    fun fractionAt(xDp: Float, totalDp: Float): Float {
        val travel = totalDp - HANDLE_DP
        if (travel <= 0f) return 0f
        return ((xDp - HANDLE_DP / 2) / travel).coerceIn(0f, 1f)
    }

    const val GAP_DP = 6f
    const val HANDLE_DP = 4f
}

/** "1:12" from 10 minutes up; "04:32" under 10 minutes. */
object Countdown {
    fun format(remaining: Duration): String {
        val seconds = (remaining.seconds + if (remaining.nano > 0) 1 else 0).coerceAtLeast(0)
        if (seconds < 600) return "%02d:%02d".format(seconds / 60, seconds % 60)
        val minutes = (seconds + 59) / 60
        return "%d:%02d".format(minutes / 60, minutes % 60)
    }

    /** Short words for the QS tile subtitle: "1h 12m", "45m", "4m 32s". */
    fun short(remaining: Duration): String {
        val seconds = (remaining.seconds + if (remaining.nano > 0) 1 else 0).coerceAtLeast(0)
        if (seconds < 600) return "%dm %02ds".format(seconds / 60, seconds % 60)
        val minutes = (seconds + 59) / 60
        return if (minutes >= 60) "%dh %02dm".format(minutes / 60, minutes % 60) else "%dm".format(minutes)
    }

    fun isUnderTenMinutes(remaining: Duration): Boolean = remaining < Duration.ofMinutes(10)
}

/** The next prayer and the stretch since the previous one, for the slider and the Live Update. */
data class PrayerProgress(
    val name: String,
    val previous: Instant,
    val next: Instant,
    val now: Instant,
    val location: String = "",
    /** The place's time zone, for "15:08"; null in tests that do not need it. */
    val zone: java.time.ZoneId? = null,
    /** Up to two prayers after [next], today only: ("Maghrib", 17:58). */
    val later: List<Pair<String, Instant>> = emptyList(),
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
            val later = snap.today
                .filter { it.slot.prayer in FIVE_PRAYERS && it.time.isAfter(next.time) }
                .take(2)
                .mapNotNull { t -> t.slot.prayer?.let { it.displayName to t.time } }
            return PrayerProgress(next.displayName, previous, next.time, now, snap.locationName, snap.zone, later)
        }
    }
}
