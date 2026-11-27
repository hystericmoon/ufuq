package app.ufuq.android

import app.ufuq.android.island.IslandStrings
import app.ufuq.android.prayer.PrayerProgress
import java.time.Duration
import java.time.Instant

/** English strings for the pure mapping tests (the app's are resources). */
object TestStrings : IslandStrings {
    override val muteAdhan = "Mute adhan"
    override val unmuteAdhan = "Unmute adhan"
    override val openApp = "Open Ufuq"
    override val refreshUsage = "Refresh usage"
    override val pairTitle = "Pair with your Mac"
    override val pairHint = "AI usage"
    override val pairDescription = "AI usage. Pair with your Mac to see your limits here."
    override val mediaTitle = "Media"
    override val mediaEmpty = "Play something to control it here"
    override val mediaEmptyDescription = "Media. Play something to control it here."
    override val allowAccess = "Allow access"
    override val play = "Play"
    override val pause = "Pause"
    override fun mediaSeekDescription(title: String, artist: String?) = "Seek, $title" + (artist?.let { " by $it" } ?: "")
    override fun mediaPositionSpoken(position: String, duration: String) = "$position of $duration"
    override fun percent(value: Int) = "$value%"
    override fun percentSpoken(value: Int) = "$value percent"
    override fun prayerDescription(name: String, spoken: String, percent: Int) =
        "$name in $spoken, $percent percent of the time since the previous prayer"
    override fun resetsIn(time: String) = "Resets in $time"
    override fun usageDescription(provider: String, percent: Int, resetsSpoken: String?) =
        "$provider, $percent percent of the limit used" + (resetsSpoken?.let { ", resets in $it" } ?: "")
}

/** Dzuhur 11:46 to Ashar 15:12 (Jakarta), as in the mockup. */
object Fixtures {
    val dzuhur: Instant = Instant.parse("2026-11-26T04:46:00Z")
    val ashar: Instant = Instant.parse("2026-11-26T08:12:00Z")

    /** "Ashar 1:12". */
    val oneHourTwelve = PrayerProgress("Ashar", dzuhur, ashar, ashar.minus(Duration.ofMinutes(72)), "Jakarta")

    /** "Ashar 04:32". */
    val underTen = PrayerProgress("Ashar", dzuhur, ashar, ashar.minus(Duration.ofMinutes(4)).minusSeconds(32), "Jakarta")
}
