package app.ufuq.android.media

import app.ufuq.core.ActivitySource
import app.ufuq.core.LiveActivity
import app.ufuq.core.ModuleStatus
import app.ufuq.core.UfuqModule
import java.time.Instant

/**
 * Now Playing as a module: while something plays it is a [ActivitySource.NOW_PLAYING] activity,
 * which the arbiter ranks below prayer-soon, AI-high and agent work, so it only takes the rotating
 * slot (or an empty wing) when nothing more important is up.
 */
class MediaModule(private val media: MediaRepository) : UfuqModule {
    override val id = ID
    override val title = "Media"
    override var isEnabled = true
    override val status: ModuleStatus get() = ModuleStatus.Ok

    override fun collapsedActivity(now: Instant): LiveActivity? {
        val s = media.state.value?.takeIf { it.playing } ?: return null
        return LiveActivity(
            id = "media.now-playing",
            moduleId = ID,
            source = ActivitySource.NOW_PLAYING,
            text = MediaFormat.wing(s.title),
            accessibilityLabel = "Now playing: " + listOfNotNull(s.title, s.artist).joinToString(", "),
        )
    }

    override fun accessibilitySummary(): String =
        media.state.value?.let { (if (it.playing) "Playing: " else "Paused: ") + it.title } ?: "Nothing is playing."

    companion object {
        const val ID = "media"
    }
}
