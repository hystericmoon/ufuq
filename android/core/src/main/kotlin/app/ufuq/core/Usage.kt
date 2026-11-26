package app.ufuq.core

import java.time.Duration
import java.time.Instant
import kotlin.math.max

/** Usage level for a limit window. Color always comes with the % in the UI. */
enum class UsageLevel {
    NORMAL,

    /** Amber, from 80%. */
    WARNING,

    /** Red, from 95%. */
    CRITICAL,
}

/** Amber at 80%, red at 95%. Also the two peek-alert points. */
data class UsageThresholds(val warning: Double, val critical: Double) {
    init {
        require(warning < critical) { "warning must be below critical" }
    }

    /** [fraction] is 0..1 (values outside are clamped). */
    fun level(fraction: Double): UsageLevel {
        val value = if (fraction.isFinite()) fraction.coerceIn(0.0, 1.0) else 0.0
        return when {
            value >= critical -> UsageLevel.CRITICAL
            value >= warning -> UsageLevel.WARNING
            else -> UsageLevel.NORMAL
        }
    }

    /**
     * The alert to peek when usage moves from [previous] to [current], or null.
     *
     * Fires once when crossing up into amber or red, and once on a window reset
     * (`resetsAt` moved forward).
     */
    fun alert(previous: UsageSnapshot?, current: UsageSnapshot): UsageAlert? {
        if (previous == null) return null
        val old = previous.resetsAt
        val new = current.resetsAt
        if (old != null && new != null && new.isAfter(old)) return UsageAlert.RESET
        val before = level(previous.fraction)
        val after = level(current.fraction)
        if (after <= before) return null
        return if (after == UsageLevel.CRITICAL) UsageAlert.REACHED_CRITICAL else UsageAlert.REACHED_WARNING
    }

    companion object {
        val DEFAULT = UsageThresholds(warning = 0.80, critical = 0.95)
    }
}

enum class UsageAlert {
    REACHED_WARNING,

    /** 95%: a critical peek that jumps the queue. */
    REACHED_CRITICAL,
    RESET,
    ;

    val peekPriority: PeekEvent.Priority
        get() = if (this == REACHED_CRITICAL) PeekEvent.Priority.CRITICAL else PeekEvent.Priority.NORMAL
}

/** One reading of a limit window (e.g. Claude 5-hour session). */
data class UsageSnapshot(
    /** 0..1 of the limit used. */
    val fraction: Double,
    val capturedAt: Instant,
    /** When the window resets, if known. */
    val resetsAt: Instant? = null,
)

/** "At this pace: session limit in 38 min." */
data class BurnRateEstimate(
    /** Fraction of the limit used per hour. */
    val fractionPerHour: Double,
    /** Time from the latest sample until 100%, or null when usage isn't rising. */
    val timeToLimit: Duration?,
    /** True when the limit is hit before the window resets (or no reset time is known). */
    val hitsLimitBeforeReset: Boolean,
)

object BurnRate {
    /** Minimum span of samples before an estimate is shown; avoids wild numbers from noise. */
    val MINIMUM_SPAN: Duration = Duration.ofMinutes(5)

    /** Only samples this recent count, so the estimate follows the current pace. */
    val LOOKBACK: Duration = Duration.ofHours(1)

    /**
     * Least-squares slope over recent samples of the current window.
     *
     * Samples before the latest reset (a drop in usage or a later `resetsAt`) are ignored.
     * Returns null with fewer than two samples or a span shorter than [minimumSpan].
     */
    fun estimate(
        samples: List<UsageSnapshot>,
        minimumSpan: Duration = MINIMUM_SPAN,
        lookback: Duration = LOOKBACK,
    ): BurnRateEstimate? {
        val sorted = samples.filter { it.fraction.isFinite() }.sortedBy { it.capturedAt }
        val latest = sorted.lastOrNull() ?: return null

        // Keep only the current window: everything after the last reset.
        var windowStart = 0
        for (i in 1 until sorted.size) {
            val prev = sorted[i - 1]
            val cur = sorted[i]
            val resetMoved = prev.resetsAt != null && cur.resetsAt != null && cur.resetsAt.isAfter(prev.resetsAt)
            if (cur.fraction < prev.fraction || resetMoved) windowStart = i
        }
        val cutoff = latest.capturedAt.minus(lookback)
        val window = sorted.subList(windowStart, sorted.size).filter { !it.capturedAt.isBefore(cutoff) }

        val first = window.firstOrNull() ?: return null
        if (window.size < 2 || Duration.between(first.capturedAt, latest.capturedAt) < minimumSpan) return null

        val xs = window.map { Duration.between(first.capturedAt, it.capturedAt).toMillis() / 1000.0 }
        val ys = window.map { it.fraction }
        val n = window.size.toDouble()
        val meanX = xs.sum() / n
        val meanY = ys.sum() / n
        var sxy = 0.0
        var sxx = 0.0
        for (i in xs.indices) {
            sxy += (xs[i] - meanX) * (ys[i] - meanY)
            sxx += (xs[i] - meanX) * (xs[i] - meanX)
        }
        if (sxx <= 0) return null
        val perSecond = sxy / sxx

        if (perSecond <= 0) {
            return BurnRateEstimate(max(perSecond, 0.0) * 3600, timeToLimit = null, hitsLimitBeforeReset = false)
        }

        val secondsToLimit = max(0.0, 1 - latest.fraction) / perSecond
        val timeToLimit = Duration.ofNanos((secondsToLimit * 1e9).toLong())
        val resetsAt = latest.resetsAt
        val hitsBeforeReset = resetsAt?.let { latest.capturedAt.plus(timeToLimit).isBefore(it) } ?: true
        return BurnRateEstimate(perSecond * 3600, timeToLimit, hitsBeforeReset)
    }
}
