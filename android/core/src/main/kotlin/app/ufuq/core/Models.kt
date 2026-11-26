package app.ufuq.core

import java.time.Duration
import java.time.Instant

/** Health of a module's data source. A broken source shows "unavailable"; it never crashes the app. */
sealed interface ModuleStatus {
    data object Ok : ModuleStatus

    /** Last good data is older than expected; still shown, marked stale. */
    data class Stale(val since: Instant) : ModuleStatus

    data class Unavailable(val reason: String) : ModuleStatus

    val isAvailable: Boolean get() = this !is Unavailable
}

/** Where an activity comes from. Drives wing placement and priority. */
enum class ActivitySource { PRAYER, AI_USAGE, AGENT, NOW_PLAYING, OTHER }

/** Notch wing. Prayer's home is the left wing, AI usage's home is the right. */
enum class Wing { LEFT, RIGHT }

/** A UI-free description of what a module wants to show in the collapsed notch. */
data class LiveActivity(
    val id: String,
    val moduleId: String,
    val source: ActivitySource,
    /** Short text for the wing, e.g. "Ashar 12:04" or "82%". */
    val text: String,
    /** One spoken summary, e.g. "Claude Work, 82 percent of session, resets in 1 hour 12 minutes". */
    val accessibilityLabel: String,
    /** An active alert (e.g. adhan now, 95% reached). Highest wing priority. */
    val isAlert: Boolean = false,
    /** The moment the activity counts down to (next prayer, reset). Used for "prayer under 10 min". */
    val deadline: Instant? = null,
    /** Usage fraction 0..1 for AI activities (worst across providers). Used for "AI at 80% or more". */
    val usageFraction: Double? = null,
)

/** A peek alert. One shows at a time; critical ones jump the queue. */
data class PeekEvent(
    val id: String,
    val moduleId: String,
    val title: String,
    val message: String,
    val priority: Priority = Priority.NORMAL,
    val duration: Duration = DEFAULT_DURATION,
    /** Text posted as an accessibility announcement when the peek appears. */
    val announcement: String = "$title. $message",
) {
    /** Declared lowest first, so the natural order is the priority order. */
    enum class Priority {
        NORMAL,

        /** 95% limits and adhan. Jump the queue and get a high-priority announcement. */
        CRITICAL,
    }

    companion object {
        val DEFAULT_DURATION: Duration = Duration.ofSeconds(6)
    }
}
