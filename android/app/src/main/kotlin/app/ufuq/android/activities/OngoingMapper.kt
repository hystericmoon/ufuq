package app.ufuq.android.activities

import app.ufuq.core.ActivitySource
import app.ufuq.core.LiveActivity
import java.time.Instant
import kotlin.math.ceil

/** Texts for the mapper, so it stays free of Android resources. */
interface ActivityStrings {
    /** "6 min". */
    fun minutes(value: Int): String

    /** "6 minutes left". */
    fun minutesLeftSpoken(value: Int): String

    /** "12 minutes elapsed". */
    fun minutesElapsedSpoken(value: Int): String

    /** "42%". */
    fun percent(value: Int): String

    /** "42 percent". */
    fun percentSpoken(value: Int): String

    /** "Open Gojek". */
    fun open(app: String): String
}

/** A short wing text and its spoken form, e.g. "6 min" / "6 minutes left". */
data class ActivityDetail(val short: String, val spoken: String)

object OngoingMapper {
    const val MODULE_ID = "other-apps"
    const val MAX_TITLE = 20

    /** Notification categories that mark a live, glanceable activity. */
    val QUALIFYING_CATEGORIES = setOf("navigation", "transport", "progress", "stopwatch", "workout", "location_sharing")

    /**
     * Ongoing AND (a live-activity category, or promoted / ProgressStyle, or a determinate progress
     * bar). Media (A3), Ufuq itself and calls are never included.
     */
    fun qualifies(n: OngoingNotification, ownPackage: String): Boolean {
        if (n.packageName == ownPackage || n.isMedia || n.isCall) return false
        if (!n.isOngoing) return false
        return n.category in QUALIFYING_CATEGORIES || n.isPromoted || n.hasProgressStyle || hasDeterminateProgress(n)
    }

    fun hasDeterminateProgress(n: OngoingNotification) = n.progressMax > 0 && !n.progressIndeterminate

    /** current / max in 0..1, or null for an indeterminate or missing bar. */
    fun progressFraction(n: OngoingNotification): Double? =
        if (hasDeterminateProgress(n)) (n.progress.toDouble() / n.progressMax).coerceIn(0.0, 1.0) else null

    /**
     * The one detail worth showing: time left (countdown chronometer), else the percent, else time
     * elapsed (count-up chronometer), else a short title.
     */
    fun detail(n: OngoingNotification, now: Instant, s: ActivityStrings): ActivityDetail? {
        val whenMs = n.whenMillis
        if (n.usesChronometer && n.chronometerCountDown && whenMs != null && whenMs > now.toEpochMilli()) {
            val left = ceil((whenMs - now.toEpochMilli()) / 60_000.0).toInt().coerceAtLeast(1)
            return ActivityDetail(s.minutes(left), s.minutesLeftSpoken(left))
        }
        progressFraction(n)?.let { f ->
            val p = (f * 100).toInt()
            return ActivityDetail(s.percent(p), s.percentSpoken(p))
        }
        if (n.usesChronometer && !n.chronometerCountDown && whenMs != null) {
            val elapsed = ((now.toEpochMilli() - whenMs) / 60_000).toInt().coerceAtLeast(0)
            return ActivityDetail(s.minutes(elapsed), s.minutesElapsedSpoken(elapsed))
        }
        val title = n.title?.trim().orEmpty()
        if (title.isNotEmpty()) {
            val short = if (title.length > MAX_TITLE) title.take(MAX_TITLE - 1).trimEnd() + "…" else title
            return ActivityDetail(short, title)
        }
        return null
    }

    /** "Gojek · 6 min" for the wing; one spoken sentence for TalkBack. */
    fun toActivity(n: OngoingNotification, now: Instant, s: ActivityStrings): LiveActivity {
        val d = detail(n, now, s)
        return LiveActivity(
            id = "other:${n.key}",
            moduleId = MODULE_ID,
            source = ActivitySource.OTHER,
            text = if (d == null) n.appLabel else "${n.appLabel} · ${d.short}",
            accessibilityLabel = if (d == null) n.appLabel else "${n.appLabel}, ${d.spoken}",
        )
    }
}

/** The per-app allow list: off for everything until the user picks apps. */
object ActivityAllowList {
    /** Qualifying, allowed notifications, newest first. Empty when the feature is off. */
    fun filter(
        all: List<OngoingNotification>,
        enabled: Boolean,
        allowed: Set<String>,
        ownPackage: String,
    ): List<OngoingNotification> {
        if (!enabled || allowed.isEmpty()) return emptyList()
        return all
            .filter { it.packageName in allowed && OngoingMapper.qualifies(it, ownPackage) }
            .sortedByDescending { it.postTimeMillis }
    }

    /** Apps to list in settings: seen this session plus anything already allowed, by label. */
    fun listed(seen: List<SeenApp>, allowed: Set<String>): List<SeenApp> {
        val known = seen.map { it.packageName }.toSet()
        return (seen + (allowed - known).map { SeenApp(it, it) }).sortedBy { it.label.lowercase() }
    }
}
