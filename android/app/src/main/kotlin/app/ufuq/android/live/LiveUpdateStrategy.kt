package app.ufuq.android.live

import app.ufuq.android.prayer.PrayerProgress
import app.ufuq.android.settings.AppSettings
import app.ufuq.core.prayer.PrayerSnapshot
import java.time.Instant

/**
 * A hook for the Live Update: a strategy may replace the "next prayer" progress (name, span, next
 * moment) for a moment; the first one that answers wins, and null falls through to the default.
 * The builder itself is unchanged, so the chip, countdown and progress bar all follow.
 */
fun interface LiveUpdateStrategy {
    fun progress(now: Instant, settings: AppSettings, snapshot: PrayerSnapshot): PrayerProgress?
}
