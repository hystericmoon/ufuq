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
    val mediaTitle: String
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

    /** "Resets in 1:12", the caption under a usage slider. */
    fun resetsIn(time: String): String

    /** "Then Maghrib 17:58 · Isya 19:12", under the prayer row; [list] is already joined. */
    fun then(list: String): String
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
    /** False for a message row (no data yet): the island shows the message and no progress line. */
    val showBar: Boolean = true,
    /** A small line under the progress line ("Then Maghrib 17:58 · Isya 19:12"); also in the description. */
    val footnote: String? = null,
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

    /**
     * The prayer row: heading "Ashar · 15:08 · Bogor", value = countdown, line = time since the
     * previous prayer, footnote = the rest of today, button = mute adhan.
     */
    fun prayer(progress: PrayerProgress, muted: Boolean, s: IslandStrings): IslandPageModel {
        val zone = progress.zone
        val trailing = listOfNotNull(zone?.let { PrayerFormat.clock(progress.next, it) }, progress.location.ifBlank { null })
            .joinToString(" · ").ifBlank { null }
        val footnote = zone?.let { z ->
            progress.later.takeIf { it.isNotEmpty() }?.joinToString(" · ") { (name, time) -> "$name ${PrayerFormat.clock(time, z)}" }?.let(s::then)
        }
        val description = s.prayerDescription(progress.name, PrayerFormat.spoken(progress.remaining), progress.percent)
        return IslandPageModel(
            id = IslandPageId.PRAYER,
            slider = SliderModel(
                fraction = progress.fraction,
                label = progress.name,
                secondary = progress.countdown,
                trailing = trailing,
                endIcon = IslandIcon.SUN,
                description = footnote?.let { "$description. $it" } ?: description,
                stateText = s.percentSpoken(progress.percent),
            ),
            buttonIcon = if (muted) IslandIcon.BELL_OFF else IslandIcon.BELL,
            buttonLabel = if (muted) s.unmuteAdhan else s.muteAdhan,
            buttonAction = ButtonAction.TOGGLE_MUTE,
            footnote = footnote,
        )
    }

    /**
     * Only rows with something to show (owner, 27 Nov): media while a session exists, AI once a
     * Mac is paired (its connecting and offline states stay, they are news to a paired user).
     * Pairing lives in the app. If nothing is left (no location yet), everything shows.
     */
    fun visible(pages: List<IslandPageModel>, unpaired: Boolean): List<IslandPageModel> =
        pages.filterNot { (it.id == IslandPageId.MEDIA && !it.showBar) || (it.id == IslandPageId.AI_USAGE && unpaired) }
            .ifEmpty { pages }

    /** Page B: a usage slider (amber from 80%, red from 95%), or the pairing empty state when there is no data. */
    fun aiUsage(sample: AiUsageSample?, s: IslandStrings, thresholds: UsageThresholds = UsageThresholds.DEFAULT): IslandPageModel {
        if (sample == null) {
            return IslandPageModel(
                id = IslandPageId.AI_USAGE,
                slider = SliderModel(0f, s.pairTitle, s.pairHint, description = s.pairDescription, stateText = s.pairHint),
                buttonIcon = IslandIcon.PHONE,
                buttonLabel = s.openApp,
                buttonAction = ButtonAction.OPEN_APP,
                showBar = false,
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
                trailing = sample.resetsIn?.let { s.resetsIn(ResetTime.hoursMinutes(it)) },
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
                slider = SliderModel(0f, s.mediaEmpty, s.mediaTitle, description = s.mediaEmptyDescription, stateText = ""),
                buttonIcon = IslandIcon.PHONE,
                buttonLabel = if (accessGranted) s.openApp else s.allowAccess,
                buttonAction = if (accessGranted) ButtonAction.OPEN_APP else ButtonAction.ALLOW_MEDIA_ACCESS,
                showBar = false,
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
     * Left = the prayer countdown only ("0:27"; owner, 27 Nov: the time is not needed collapsed),
     * or the prayer's own text while it is an alert ("Ashar now"). Right = the AI wing, else the
     * rotating activity, else empty: the wings are drawn equally wide, so the pill stays centred
     * on the camera. The full sentence stays in [PillModel.description].
     */
    fun from(
        layout: WingLayout,
        now: Instant,
        thresholds: UsageThresholds = UsageThresholds.DEFAULT,
    ): PillModel? {
        val left = layout.left
        val right = layout.right ?: layout.rotating
        if (left == null && right == null) return null
        val countdown = left?.deadline?.takeIf { !left.isAlert }
            ?.let { app.ufuq.android.prayer.Countdown.format(Duration.between(now, it)) }
        val rightText = right?.text.orEmpty()
        val level = right?.takeIf { it.source == ActivitySource.AI_USAGE }?.usageFraction?.let(thresholds::level) ?: UsageLevel.NORMAL
        val description = listOfNotNull(left?.accessibilityLabel, right?.accessibilityLabel).joinToString(". ")
        return PillModel(
            left = countdown ?: left?.text.orEmpty(),
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

    /** The collapsed pill: the camera hole plus 4 dp above and below, 24 to 30 dp tall. */
    const val PILL_PADDING_DP = 4
    const val MIN_PILL_DP = 24
    const val MAX_PILL_DP = 30
    const val DEFAULT_PILL_DP = 26

    /** Where the pill sits: centred on the camera hole, or 4 dp from the top without one. */
    data class Placement(val topDp: Int, val heightDp: Int)

    fun placement(cutoutTopPx: Int?, cutoutBottomPx: Int?, density: Float): Placement {
        if (cutoutTopPx == null || cutoutBottomPx == null || cutoutBottomPx <= cutoutTopPx || density <= 0f) {
            return Placement(PILL_PADDING_DP, DEFAULT_PILL_DP)
        }
        val holeTop = cutoutTopPx / density
        val holeHeight = (cutoutBottomPx - cutoutTopPx) / density
        val height = (holeHeight + 2 * PILL_PADDING_DP).toInt().coerceIn(MIN_PILL_DP, MAX_PILL_DP)
        val centre = holeTop + holeHeight / 2
        return Placement((centre - height / 2f).toInt().coerceAtLeast(0), height)
    }
}
