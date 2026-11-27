package app.ufuq.android.ui

import app.ufuq.android.prayer.PrayerProgress
import app.ufuq.core.prayer.PrayerFormat
import app.ufuq.core.prayer.PrayerModule
import java.time.Instant

/** The home status card's prayer line: "Next: Ashar 15:08 · Jakarta". */
data class TodayState(
    val location: String,
    val nextName: String,
    val nextTime: String,
) {
    companion object {
        fun from(progress: PrayerProgress): TodayState? {
            val zone = progress.zone ?: return null
            return TodayState(progress.location, progress.name, PrayerFormat.clock(progress.next, zone))
        }

        fun at(now: Instant, module: PrayerModule): TodayState? = PrayerProgress.at(now, module)?.let(::from)
    }
}
