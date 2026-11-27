package app.ufuq.android.island

import app.ufuq.android.media.MediaFormat
import app.ufuq.android.media.MediaState
import app.ufuq.android.prayer.PrayerProgress
import app.ufuq.core.ActivitySource
import app.ufuq.core.UsageLevel
import app.ufuq.core.UsageThresholds
import app.ufuq.core.WingLayout
import app.ufuq.core.prayer.PrayerFormat
import java.time.Duration
import java.time.Instant
import kotlin.math.ceil

enum class IslandIcon { SUN, BELL, BELL_OFF, REFRESH, PHONE, PLAY, PAUSE }

enum class IslandPageId { PRAYER, AI_USAGE, MEDIA, OTHER }

/** What a page's round button does; the service and the app decide how. */
enum class ButtonAction { TOGGLE_MUTE, OPEN_APP, REFRESH, PLAY_PAUSE, ALLOW_MEDIA_ACCESS, OPEN_SOURCE, PAIR_MAC }

/** Texts the models need, so the mapping stays free of Android resources and is unit-testable. */
interface IslandStrings {
    val muteAdhan: String
    val unmuteAdhan: String
    val openApp: String
    val refreshUsage: String
    val pairTitle: String
    val pairHint: String
    val pairDescription: String
    val mediaEmpty: String
    val mediaEmptyDescription: String
    val allowAccess: String
    val play: String
    val pause: String

    /** The seek slider's spoken label, e.g. "Seek, Mishary". */
    fun mediaSeekDescription(title: String, artist: String?): String

    /** Its spoken value, e.g. "1 minute 24 seconds of 3 minutes 30 seconds". */
    fun mediaPositionSpoken(position: String, duration: String): String
    /** "82%" for a label. */
    fun percent(value: Int): String

    /** "82 percent" for TalkBack. */
    fun percentSpoken(value: Int): String
    fun prayerDescription(name: String, spoken: String, percent: Int): String
    fun usageDescription(provider: String, percent: Int, resetsSpoken: String?): String
}

/**
 * One slider: [fraction] 0..1 drives the track, [label] and [secondary] sit inside it, [trailing]
 * is a second secondary text at the end and [endIcon] a small icon. The amber and red [level]
 * always come with the percent in [stateText] and [description] (color never carries meaning alone).
 */
data class SliderModel(
    val fraction: Float,
    val label: String,
    val secondary: String? = null,
    val trailing: String? = null,
    val endIcon: IslandIcon? = null,
    val level: UsageLevel = UsageLevel.NORMAL,
    /** The whole slider is one TalkBack node: this is its spoken label. */
    val description: String,
    /** Its spoken value, e.g. "62 percent". */
    val stateText: String,
    /** Set on the media page: the slider is draggable and steps by [SeekSpec.stepMs] for TalkBack. */
    val seek: SeekSpec? = null,
)

/** A draggable slider's range: TalkBack increment/decrement moves by [stepMs] (10 s). */
data class SeekSpec(val durationMs: Long, val stepMs: Long = 10_000) {
    /** Steps strictly between the ends, as Compose's progress range wants them. */
    val steps: Int get() = (durationMs / stepMs - 1).coerceIn(0, 10_000).toInt()
}

data class IslandPageModel(
    val id: IslandPageId,
    val slider: SliderModel,
    val buttonIcon: IslandIcon,
    val buttonLabel: String,
    val buttonAction: ButtonAction,
)

/** The AI usage that page B shows. The data arrives with the Mac sync (phase A6). */
data class AiUsageSample(val provider: String, val fraction: Double, val resetsIn: Duration? = null)

object IslandPages {
    fun all(
        progress: PrayerProgress?,
        muted: Boolean,
        usage: AiUsageSample?,
        strings: IslandStrings,
        thresholds: UsageThresholds = UsageThresholds.DEFAULT,
        mediaState: MediaState? = null,
        mediaAccess: Boolean = false,
        elapsedNowMs: Long = 0,
    ): List<IslandPageModel> = listOfNotNull(
        progress?.let { prayer(it, muted, strings) },
        aiUsage(usage, strings, thresholds),
        media(mediaState, mediaAccess, strings, elapsedNowMs),
    )

    /** Page A: track = time since the previous prayer, label = next prayer + countdown, button = mute adhan. */
    fun prayer(progress: PrayerProgress, muted: Boolean, s: IslandStrings): IslandPageModel = IslandPageModel(
        id = IslandPageId.PRAYER,
        slider = SliderModel(
            fraction = progress.fraction,
            label = progress.name,
            secondary = progress.countdown,
            endIcon = IslandIcon.SUN,
            description = s.prayerDescription(progress.name, PrayerFormat.spoken(progress.remaining), progress.percent),
            stateText = s.percentSpoken(progress.percent),
        ),
        buttonIcon = if (muted) IslandIcon.BELL_OFF else IslandIcon.BELL,
        buttonLabel = if (muted) s.unmuteAdhan else s.muteAdhan,
        buttonAction = ButtonAction.TOGGLE_MUTE,
    )

    /** Page B: a usage slider (amber from 80%, red from 95%), or the pairing empty state when there is no data. */
    fun aiUsage(sample: AiUsageSample?, s: IslandStrings, thresholds: UsageThresholds = UsageThresholds.DEFAULT): IslandPageModel {
        if (sample == null) {
            return IslandPageModel(
                id = IslandPageId.AI_USAGE,
                slider = SliderModel(0f, s.pairTitle, s.pairHint, description = s.pairDescription, stateText = s.pairHint),
                buttonIcon = IslandIcon.PHONE,
                buttonLabel = s.openApp,
                buttonAction = ButtonAction.OPEN_APP,
            )
        }
        val fraction = sample.fraction.coerceIn(0.0, 1.0)
        val percent = (fraction * 100).toInt()
        return IslandPageModel(
            id = IslandPageId.AI_USAGE,
            slider = SliderModel(
                fraction = fraction.toFloat(),
                label = sample.provider,
                secondary = s.percent(percent),
                trailing = sample.resetsIn?.let { ResetTime.hoursMinutes(it) },
                level = thresholds.level(fraction),
                description = s.usageDescription(sample.provider, percent, sample.resetsIn?.let { PrayerFormat.spoken(it) }),
                stateText = s.percentSpoken(percent),
            ),
            buttonIcon = IslandIcon.REFRESH,
            buttonLabel = s.refreshUsage,
            buttonAction = ButtonAction.REFRESH,
        )
    }

    /**
     * Page C: the seek slider (title, position, duration; draggable) and the play/pause button.
     * With no session the empty state offers "Allow access" until notification access is granted.
     */
    fun media(state: MediaState?, accessGranted: Boolean, s: IslandStrings, elapsedNowMs: Long): IslandPageModel {
        if (state == null) {
            return IslandPageModel(
                id = IslandPageId.MEDIA,
                slider = SliderModel(0f, s.mediaEmpty, description = s.mediaEmptyDescription, stateText = ""),
                buttonIcon = IslandIcon.PHONE,
                buttonLabel = if (accessGranted) s.openApp else s.allowAccess,
                buttonAction = if (accessGranted) ButtonAction.OPEN_APP else ButtonAction.ALLOW_MEDIA_ACCESS,
            )
        }
        val position = state.positionAt(elapsedNowMs)
        val seek = if (state.seekable) SeekSpec(state.durationMs) else null
        return IslandPageModel(
            id = IslandPageId.MEDIA,
            slider = SliderModel(
                fraction = state.fractionAt(elapsedNowMs),
                label = state.title,
                secondary = MediaFormat.clock(position),
                trailing = state.durationMs.takeIf { it > 0 }?.let(MediaFormat::clock),
                description = s.mediaSeekDescription(state.title, state.artist),
                stateText = if (state.durationMs > 0) {
                    s.mediaPositionSpoken(MediaFormat.spoken(position), MediaFormat.spoken(state.durationMs))
                } else {
                    MediaFormat.spoken(position)
                },
                seek = seek,
            ),
            buttonIcon = if (state.playing) IslandIcon.PAUSE else IslandIcon.PLAY,
            buttonLabel = if (state.playing) s.pause else s.play,
            buttonAction = ButtonAction.PLAY_PAUSE,
        )
    }
}

/** Small time formats shared with page B. */
object ResetTime {
    /** "1:12" for a reset in 1 h 12 min. */
    fun hoursMinutes(d: Duration): String {
        val minutes = ceil(d.seconds.coerceAtLeast(0) / 60.0).toLong()
        return "%d:%02d".format(minutes / 60, minutes % 60)
    }
}

/** The collapsed pill: left wing, right wing and what TalkBack says. */
data class PillModel(
    val left: String,
    val right: String,
    val rightLevel: UsageLevel,
    val isAlert: Boolean,
    val description: String,
)

object PillMapper {
    /**
     * Left = the prayer wing, right = the AI wing; with no AI activity the right wing shows the
     * rotating activity, and failing that the prayer countdown (so the pill is never lopsided).
     */
    fun from(
        layout: WingLayout,
        now: Instant,
        thresholds: UsageThresholds = UsageThresholds.DEFAULT,
    ): PillModel? {
        val left = layout.left
        val right = layout.right ?: layout.rotating
        if (left == null && right == null) return null
        val countdown = left?.deadline?.takeIf { right == null && !left.isAlert }
            ?.let { app.ufuq.android.prayer.Countdown.format(Duration.between(now, it)) }
        val rightText = right?.text ?: countdown.orEmpty()
        val level = right?.takeIf { it.source == ActivitySource.AI_USAGE }?.usageFraction?.let(thresholds::level) ?: UsageLevel.NORMAL
        val description = listOfNotNull(left?.accessibilityLabel, right?.accessibilityLabel).joinToString(". ")
        return PillModel(
            left = left?.text.orEmpty(),
            right = rightText,
            rightLevel = level,
            isAlert = left?.isAlert == true || right?.isAlert == true,
            description = description,
        )
    }
}

/** How wide the collapsed pill's camera gap is, from the cutout (null on a phone without one). */
object IslandGeometry {
    const val GAP_PADDING_DP = 6

    fun gapDp(cutoutWidthPx: Int?, density: Float): Int {
        if (cutoutWidthPx == null || cutoutWidthPx <= 0 || density <= 0f) return 0
        return Math.ceil((cutoutWidthPx / density).toDouble()).toInt() + 2 * GAP_PADDING_DP
    }
}
