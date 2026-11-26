package app.ufuq.core.prayer

import app.ufuq.core.LiveActivity
import app.ufuq.core.ActivitySource
import app.ufuq.core.ModuleStatus
import app.ufuq.core.PeekEvent
import app.ufuq.core.UfuqModule
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** No times can be calculated for the place (e.g. polar regions). */
class PrayerTimesUnavailableException : Exception("Prayer times unavailable for this location")

/** Text helpers for the next-prayer countdown. */
object PrayerFormat {
    private val CLOCK = DateTimeFormatter.ofPattern("HH:mm")

    /** "15:12" in the given zone (24-hour, locale independent). */
    fun clock(time: Instant, zone: ZoneId): String = CLOCK.format(time.atZone(zone))

    /** "1 hour 12 minutes", "45 minutes", "2 hours", "less than a minute". Rounds up to the minute. */
    fun spoken(interval: Duration): String {
        val seconds = interval.seconds + if (interval.nano > 0) 1 else 0
        val minutes = (maxOf(0L, seconds) + 59) / 60
        if (minutes == 0L) return "less than a minute"
        val h = minutes / 60
        val m = minutes % 60
        val parts = mutableListOf<String>()
        if (h > 0) parts += "$h ${if (h == 1L) "hour" else "hours"}"
        if (m > 0) parts += "$m ${if (m == 1L) "minute" else "minutes"}"
        return parts.joinToString(" ")
    }
}

/** Peek alerts around the adhan: a normal one shortly before, a critical one at the adhan time. */
object PrayerPeeks {
    val DEFAULT_LEAD: Duration = Duration.ofMinutes(10)

    /** How long after the adhan time the critical alert still counts as due. */
    val ADHAN_WINDOW: Duration = Duration.ofSeconds(60)

    /** "Ashar in 10 minutes", normal priority. */
    fun preAdhan(
        prayer: NextPrayer,
        zone: ZoneId,
        date: LocalDate,
        now: Instant,
        lead: Duration = DEFAULT_LEAD,
    ): PeekEvent? {
        val remaining = Duration.between(now, prayer.time)
        if (remaining.isZero || remaining.isNegative || remaining > lead) return null
        val name = prayer.displayName
        val whenText = PrayerFormat.clock(prayer.time, zone)
        return PeekEvent(
            id = "prayer.pre.${prayer.prayer.key}.$date",
            moduleId = "prayer",
            title = name,
            message = "in ${PrayerFormat.spoken(remaining)}, at $whenText",
            priority = PeekEvent.Priority.NORMAL,
            announcement = "$name in ${PrayerFormat.spoken(remaining)}",
        )
    }

    /** "Ashar now", critical priority. */
    fun adhan(prayer: Prayer, isJumuah: Boolean, time: Instant, zone: ZoneId, date: LocalDate): PeekEvent {
        val name = if (isJumuah) Prayer.JUMUAH.displayName else prayer.displayName
        return PeekEvent(
            id = "prayer.adhan.${prayer.key}.$date",
            moduleId = "prayer",
            title = name,
            message = "Time for $name, ${PrayerFormat.clock(time, zone)}",
            priority = PeekEvent.Priority.CRITICAL,
            announcement = "Time for $name",
        )
    }
}

private val Prayer.key: String get() = name.lowercase()

/**
 * The prayer module: left wing, next prayer with a countdown deadline, peeks around the adhan.
 * Everything is calculated locally, so it works offline.
 */
class PrayerModule(
    var location: PrayerLocation = PrayerLocation.JAKARTA,
    var settings: CalculationSettings = CalculationSettings(),
    var preAdhanLead: Duration = PrayerPeeks.DEFAULT_LEAD,
    private val calculator: PrayerCalculator = PrayerCalculator(),
    private val clock: () -> Instant = Instant::now,
    private val pollInterval: Duration = Duration.ofSeconds(15),
) : UfuqModule {
    override val id = "prayer"
    override val title = "Prayer"
    override var isEnabled = true

    override val status: ModuleStatus
        get() = if (snapshot(clock()) == null) {
            ModuleStatus.Unavailable(PrayerTimesUnavailableException().message!!)
        } else {
            ModuleStatus.Ok
        }

    fun snapshot(now: Instant): PrayerSnapshot? = PrayerSnapshots.at(now, location, settings, calculator)

    override fun collapsedActivity(now: Instant): LiveActivity? {
        val snap = snapshot(now) ?: throw PrayerTimesUnavailableException()
        // Right at the adhan the activity is an alert for the prayer that just began.
        justStarted(snap, now)?.let { due ->
            val name = if (due.isJumuah) Prayer.JUMUAH.displayName else due.prayer.displayName
            return LiveActivity(
                id = "prayer.next", moduleId = id, source = ActivitySource.PRAYER,
                text = "$name now",
                accessibilityLabel = "$name now",
                isAlert = true, deadline = due.time,
            )
        }
        val next = snap.next
        return LiveActivity(
            id = "prayer.next", moduleId = id, source = ActivitySource.PRAYER,
            text = "${next.displayName} ${PrayerFormat.clock(next.time, location.zone)}",
            accessibilityLabel = "${next.displayName} in ${PrayerFormat.spoken(next.remaining(now))}",
            deadline = next.time,
        )
    }

    override fun accessibilitySummary(): String {
        val now = clock()
        val snap = snapshot(now) ?: return "Prayer times unavailable"
        val n = snap.next
        return "Next prayer ${n.displayName} at ${PrayerFormat.clock(n.time, location.zone)}, in ${PrayerFormat.spoken(n.remaining(now))}"
    }

    /**
     * The peek that is due at [now], if any: critical at the adhan (within the adhan window),
     * otherwise the pre-adhan peek once the next prayer is within [preAdhanLead].
     */
    fun duePeek(now: Instant): PeekEvent? {
        val snap = snapshot(now) ?: return null
        justStarted(snap, now)?.let { due ->
            return PrayerPeeks.adhan(due.prayer, due.isJumuah, due.time, location.zone, snap.date)
        }
        return PrayerPeeks.preAdhan(snap.next, location.zone, snap.date, now, preAdhanLead)
    }

    /** Emits each due peek once, polling every 15 seconds. Ends when the collector stops. */
    override fun peekEvents(): Flow<PeekEvent> = flow {
        val seen = mutableSetOf<String>()
        while (true) {
            duePeek(clock())?.let { if (seen.add(it.id)) emit(it) }
            delay(pollInterval.toMillis())
        }
    }

    private data class Started(val prayer: Prayer, val time: Instant, val isJumuah: Boolean)

    private fun justStarted(snap: PrayerSnapshot, now: Instant): Started? {
        for (slot in snap.today) {
            val prayer = slot.slot.prayer ?: continue
            val elapsed = Duration.between(slot.time, now)
            if (!elapsed.isNegative && elapsed < PrayerPeeks.ADHAN_WINDOW) {
                return Started(prayer, slot.time, prayer == Prayer.DHUHR && snap.date.dayOfWeek == java.time.DayOfWeek.FRIDAY)
            }
        }
        return null
    }
}
