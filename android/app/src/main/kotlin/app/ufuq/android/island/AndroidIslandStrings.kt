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
    override val mediaEmpty get() = context.getString(R.string.island_media_empty)
    override val mediaEmptyDescription get() = context.getString(R.string.island_media_empty_description)
    override val allowAccess get() = context.getString(R.string.island_allow_access)
    override val play get() = context.getString(R.string.island_play)
    override val pause get() = context.getString(R.string.island_pause)
    override fun mediaSeekDescription(title: String, artist: String?) =
        if (artist == null) context.getString(R.string.island_media_seek, title) else context.getString(R.string.island_media_seek_artist, title, artist)
    override fun mediaPositionSpoken(position: String, duration: String) = context.getString(R.string.island_media_position, position, duration)
    override fun percent(value: Int) = context.getString(R.string.island_percent, value)
    override fun percentSpoken(value: Int) = context.getString(R.string.island_percent_spoken, value)
    override fun prayerDescription(name: String, spoken: String, percent: Int) =
        context.getString(R.string.island_prayer_description, name, spoken, percent)
    override fun resetsIn(time: String) = context.getString(R.string.island_resets_in, time)
    override fun then(list: String) = context.getString(R.string.island_then, list)
    override fun usageDescription(provider: String, percent: Int, resetsSpoken: String?) =
        if (resetsSpoken == null) {
            context.getString(R.string.island_usage_description, provider, percent)
        } else {
            context.getString(R.string.island_usage_description_resets, provider, percent, resetsSpoken)
        }
}
