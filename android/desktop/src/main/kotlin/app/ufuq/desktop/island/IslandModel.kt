package app.ufuq.desktop.island

import app.ufuq.core.ActivitySource
import app.ufuq.core.UsageLevel
import app.ufuq.core.UsageThresholds
import app.ufuq.core.WingLayout
import app.ufuq.core.prayer.PrayerFormat
import java.time.Duration
import java.time.Instant
import kotlin.math.ceil

// TODO: duplicated from :app (app.ufuq.android.island); extract to a KMP :island-ui module later.
// Differences: media page hidden on desktop, one AI page per account, the prayer button opens
// Settings (no adhan audio on desktop yet), "estimated" labels, a proportional slider.

enum class IslandIcon { SUN, BELL, REFRESH, SETTINGS, PLAY, PAUSE }

enum class IslandPageId { PRAYER, AI_USAGE, MEDIA }

/** What a page's round button does; the controller decides how. */
enum class ButtonAction { OPEN_SETTINGS, REFRESH }

/** Texts the models need, so the mapping stays free of resources and is unit-testable. */
interface IslandStrings {
    val openSettings: String
    val refreshUsage: String
    val noUsageTitle: String
    val noUsageHint: String
    val noUsageDescription: String
    val estimated: String
    val expand: String
    val close: String
    val dismiss: String

    /** "Page 2 of 3" for the screen reader. */
    fun pageOf(index: Int, count: Int): String

    /** "82%" for a label. */
    fun percent(value: Int): String

    /** "82 percent" for the screen reader. */
    fun percentSpoken(value: Int): String
    fun prayerDescription(name: String, spoken: String, percent: Int): String
    fun usageDescription(provider: String, window: String?, percent: Int, estimated: Boolean, resetsSpoken: String?): String
}

/**
 * One slider: [fraction] 0..1 puts the handle at fraction x the full width, [label] and [secondary]
 * sit inside the track, [trailing] is a second secondary text at the end and [endIcon] a small icon.
 * The amber and red [level] always come with the percent in [stateText] and [description].
 */
data class SliderModel(
    val fraction: Float,
    val label: String,
    val secondary: String? = null,
    val trailing: String? = null,
    val endIcon: IslandIcon? = null,
    val level: UsageLevel = UsageLevel.NORMAL,
    /** The whole slider is one accessibility node: this is its spoken label. */
    val description: String,
    /** Its spoken value, e.g. "62 percent". */
    val stateText: String,
)

data class IslandPageModel(
    val id: IslandPageId,
    val key: String,
    val slider: SliderModel,
    val buttonIcon: IslandIcon,
    val buttonLabel: String,
    val buttonAction: ButtonAction,
)

/** One account's worst limit window for page B. */
data class AiUsageSample(
    val provider: String,
    val fraction: Double,
    val resetsIn: Duration? = null,
    /** "5h", "week", or a model group; null when unknown. */
    val window: String? = null,
    /** Computed locally from token counts against an assumed budget, not read from the provider. */
    val estimated: Boolean = false,
)

object IslandPages {
    fun all(
        progress: PrayerProgress?,
        usage: List<AiUsageSample>,
        strings: IslandStrings,
        thresholds: UsageThresholds = UsageThresholds.DEFAULT,
    ): List<IslandPageModel> = listOfNotNull(progress?.let { prayer(it, strings) }) + aiUsage(usage, strings, thresholds)

    /** Page A: track = time since the previous prayer, label = next prayer + countdown, button = settings. */
    fun prayer(progress: PrayerProgress, s: IslandStrings): IslandPageModel = IslandPageModel(
        id = IslandPageId.PRAYER,
        key = "prayer",
        slider = SliderModel(
            fraction = progress.fraction,
            label = progress.name,
            secondary = progress.countdown,
            endIcon = IslandIcon.SUN,
            description = s.prayerDescription(progress.name, PrayerFormat.spoken(progress.remaining), progress.percent),
            stateText = s.percentSpoken(progress.percent),
        ),
        buttonIcon = IslandIcon.SETTINGS,
        buttonLabel = s.openSettings,
        buttonAction = ButtonAction.OPEN_SETTINGS,
    )

    /** Page B: one usage slider per account (amber from 80%, red from 95%), or an empty state with no data. */
    fun aiUsage(samples: List<AiUsageSample>, s: IslandStrings, thresholds: UsageThresholds = UsageThresholds.DEFAULT): List<IslandPageModel> {
        if (samples.isEmpty()) {
            return listOf(
                IslandPageModel(
                    id = IslandPageId.AI_USAGE,
                    key = "ai.none",
                    slider = SliderModel(0f, s.noUsageTitle, s.noUsageHint, description = s.noUsageDescription, stateText = s.noUsageHint),
                    buttonIcon = IslandIcon.SETTINGS,
                    buttonLabel = s.openSettings,
                    buttonAction = ButtonAction.OPEN_SETTINGS,
                ),
            )
        }
        return samples.mapIndexed { index, sample ->
            val fraction = sample.fraction.coerceIn(0.0, 1.0)
            val percent = (fraction * 100).toInt()
            IslandPageModel(
                id = IslandPageId.AI_USAGE,
                key = "ai.$index.${sample.provider}",
                slider = SliderModel(
                    fraction = fraction.toFloat(),
                    label = listOfNotNull(sample.provider, sample.window).joinToString(" "),
                    secondary = if (sample.estimated) "${s.percent(percent)} ${s.estimated}" else s.percent(percent),
                    trailing = sample.resetsIn?.let { ResetTime.hoursMinutes(it) },
                    level = thresholds.level(fraction),
                    description = s.usageDescription(sample.provider, sample.window, percent, sample.estimated, sample.resetsIn?.let { PrayerFormat.spoken(it) }),
                    stateText = s.percentSpoken(percent),
                ),
                buttonIcon = IslandIcon.REFRESH,
                buttonLabel = s.refreshUsage,
                buttonAction = ButtonAction.REFRESH,
            )
        }
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

/** The collapsed pill: left wing, right wing and what the screen reader says. */
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
            ?.let { Countdown.format(Duration.between(now, it)) }
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

/**
 * The proportional slider: the handle sits at `fraction x (width - handle)`, the active track ends
 * a gap before it and the inactive track starts a gap after it. All in dp. The label overlays the
 * whole track and is drawn once per segment, clipped to it, so each part has its own text colour.
 */
data class SliderGeometry(val handleX: Float, val activeWidth: Float, val inactiveStart: Float, val inactiveWidth: Float) {
    companion object {
        const val HANDLE_DP = 4f
        const val GAP_DP = 6f

        fun of(fraction: Float, totalDp: Float): SliderGeometry {
            val f = if (fraction.isFinite()) fraction.coerceIn(0f, 1f) else 0f
            val total = totalDp.coerceAtLeast(HANDLE_DP)
            val handleX = f * (total - HANDLE_DP)
            val active = (handleX - GAP_DP).coerceAtLeast(0f)
            val inactiveStart = handleX + HANDLE_DP + GAP_DP
            return SliderGeometry(handleX, active, inactiveStart, (total - inactiveStart).coerceAtLeast(0f))
        }
    }
}
