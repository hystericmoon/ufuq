package app.ufuq.core

import java.time.Duration
import java.time.Instant

/**
 * Wing priority, lowest first, so the natural order is the priority order:
 * active alert > prayer under 10 min > AI at 80% or more > agent task running > Now Playing > other.
 */
enum class WingPriority { OTHER, NOW_PLAYING, AGENT_RUNNING, AI_USAGE_HIGH, PRAYER_SOON, ALERT }

/** What the collapsed notch shows. */
data class WingLayout(
    val left: LiveActivity? = null,
    val right: LiveActivity? = null,
    /** The third activity, rotated every 8 s (or pinned while an alert is active). */
    val rotating: LiveActivity? = null,
)

/**
 * Chooses what goes in each wing and rotates a third activity.
 *
 * - Prayer always takes the left wing and AI usage the right (fixed positions build habit).
 *   An empty home wing is filled with the highest-priority remaining activity.
 * - The rest form the rotation pool, ordered by priority. Each shows for [rotationInterval].
 * - While an alert is in the pool it is pinned to the rotating slot; no rotation.
 */
class ActivityArbiter(
    var rotationInterval: Duration = DEFAULT_ROTATION_INTERVAL,
    var thresholds: UsageThresholds = UsageThresholds.DEFAULT,
) {
    private var rotatingId: String? = null
    private var shownSince: Instant? = null

    fun priority(activity: LiveActivity, now: Instant): WingPriority {
        if (activity.isAlert) return WingPriority.ALERT
        return when (activity.source) {
            ActivitySource.PRAYER -> {
                val remaining = activity.deadline?.let { Duration.between(now, it) }
                if (remaining != null && !remaining.isNegative && remaining < PRAYER_SOON_WINDOW) {
                    WingPriority.PRAYER_SOON
                } else {
                    WingPriority.OTHER
                }
            }
            ActivitySource.AI_USAGE -> {
                val fraction = activity.usageFraction
                if (fraction != null && thresholds.level(fraction) >= UsageLevel.WARNING) {
                    WingPriority.AI_USAGE_HIGH
                } else {
                    WingPriority.OTHER
                }
            }
            ActivitySource.AGENT -> WingPriority.AGENT_RUNNING
            ActivitySource.NOW_PLAYING -> WingPriority.NOW_PLAYING
            ActivitySource.OTHER -> WingPriority.OTHER
        }
    }

    /** Activities sorted by priority, highest first; ties keep input order. */
    fun ranked(activities: List<LiveActivity>, now: Instant): List<LiveActivity> =
        activities.sortedByDescending { priority(it, now) } // sortedBy is stable

    /** Computes the layout for [now]. Call on every tick; it advances the rotation when due. */
    fun layout(activities: List<LiveActivity>, now: Instant): WingLayout {
        val pool = ranked(activities, now).toMutableList()

        fun takeFirst(source: ActivitySource): LiveActivity? {
            val index = pool.indexOfFirst { it.source == source }
            return if (index >= 0) pool.removeAt(index) else null
        }

        // An alert never fills an empty home wing: it belongs in the rotating slot, pinned.
        fun takeNonAlert(): LiveActivity? {
            val index = pool.indexOfFirst { !it.isAlert }
            return if (index >= 0) pool.removeAt(index) else null
        }

        val left = takeFirst(ActivitySource.PRAYER) ?: takeNonAlert()
        val right = takeFirst(ActivitySource.AI_USAGE) ?: takeNonAlert()
        return WingLayout(left, right, nextRotating(pool, now))
    }

    private fun nextRotating(pool: List<LiveActivity>, now: Instant): LiveActivity? {
        if (pool.isEmpty()) {
            rotatingId = null
            shownSince = null
            return null
        }

        pool.firstOrNull { it.isAlert }?.let { return show(it, now, keepTimer = it.id == rotatingId) }

        val currentIndex = pool.indexOfFirst { it.id == rotatingId }
        val since = shownSince
        if (currentIndex < 0 || since == null) return show(pool[0], now, keepTimer = false)

        if (Duration.between(since, now) >= rotationInterval) {
            return show(pool[(currentIndex + 1) % pool.size], now, keepTimer = false)
        }
        return pool[currentIndex]
    }

    private fun show(activity: LiveActivity, now: Instant, keepTimer: Boolean): LiveActivity {
        if (!keepTimer || shownSince == null) shownSince = now
        rotatingId = activity.id
        return activity
    }

    companion object {
        val DEFAULT_ROTATION_INTERVAL: Duration = Duration.ofSeconds(8)
        val PRAYER_SOON_WINDOW: Duration = Duration.ofMinutes(10)
    }
}
