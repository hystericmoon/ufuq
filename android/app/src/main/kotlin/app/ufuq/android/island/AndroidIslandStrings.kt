package app.ufuq.android.island

import android.content.Context
import app.ufuq.android.R

/** [IslandStrings] from Android resources. */
class AndroidIslandStrings(private val context: Context) : IslandStrings {
    override val muteAdhan get() = context.getString(R.string.island_mute_adhan)
    override val unmuteAdhan get() = context.getString(R.string.island_unmute_adhan)
    override val openApp get() = context.getString(R.string.island_open_app)
    override val refreshUsage get() = context.getString(R.string.island_refresh_usage)
    override val pairTitle get() = context.getString(R.string.island_pair_title)
    override val pairHint get() = context.getString(R.string.island_pair_hint)
    override val pairDescription get() = context.getString(R.string.island_pair_description)
    override val mediaTitle get() = context.getString(R.string.island_media_title)
    override val mediaHint get() = context.getString(R.string.island_media_hint)
    override val mediaDescription get() = context.getString(R.string.island_media_description)
    override fun percent(value: Int) = context.getString(R.string.island_percent, value)
    override fun percentSpoken(value: Int) = context.getString(R.string.island_percent_spoken, value)
    override fun prayerDescription(name: String, spoken: String, percent: Int) =
        context.getString(R.string.island_prayer_description, name, spoken, percent)
    override fun usageDescription(provider: String, percent: Int, resetsSpoken: String?) =
        if (resetsSpoken == null) {
            context.getString(R.string.island_usage_description, provider, percent)
        } else {
            context.getString(R.string.island_usage_description_resets, provider, percent, resetsSpoken)
        }
}
