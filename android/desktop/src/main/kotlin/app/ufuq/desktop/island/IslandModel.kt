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
// Settings (no adhan audio on desktop yet), Claude shown as tokens used (no %), a proportional slider.

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
    /** "Resets in 1:12", the caption under a usage slider. */
    fun resetsIn(time: String): String

    /** "4.2M tokens" for a label. */
    fun tokens(compact: String): String
    val expand: String
    val close: String
    val dismiss: String

    /** "Page 2 of 3" for the screen reader. */

    /** "82%" for a label. */
    fun percent(value: Int): String

    /** "82 percent" for the screen reader. */
    fun percentSpoken(value: Int): String
    fun prayerDescription(name: String, spoken: String, percent: Int): String
    fun usageDescription(provider: String, window: String?, percent: Int, resetsSpoken: String?): String

    /** "Claude 5-hour session, 4.2 million tokens used, resets in 3 hours" for the screen reader. */
    fun tokenDescription(provider: String, window: String?, tokensSpoken: String, resetsSpoken: String?): String
}

/**
 * One slider: [fraction] 0..1 puts the handle at fraction x the full width, [label] and [secondary]
 * sit inside the track, [trailing] is a second secondary text at the end and [endIcon] a small icon.
 * The amber and red [level] always come with the percent in [stateText] and [description].
 * [meter] false draws a plain track with no fill or handle: a count with no known limit.
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
    val meter: Boolean = true,
)

data class IslandPageModel(
    val id: IslandPageId,
    val key: String,
    val slider: SliderModel,
    val buttonIcon: IslandIcon,
    val buttonLabel: String,
    val buttonAction: ButtonAction,
    /** A message row (no data yet): the hint leads, the message follows, no value or line. */
    val message: Boolean = false,
)

/** One account's worst limit window for page B. */
data class AiUsageSample(
    val provider: String,
    val fraction: Double,
    val resetsIn: Duration? = null,
    /** "5h", "week", or a model group; null when unknown. */
    val window: String? = null,
    /**
     * Tokens used in the window, for a source whose limit is unknown (Claude until its live limit is
     * verified). When set, [fraction] is meaningless: no %, no amber/red, no alerts.
     */
    val tokens: Long? = null,
) {
    val isTokenCount: Boolean get() = tokens != null
}

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
                    message = true,
                ),
            )
        }
        return samples.mapIndexed { index, sample ->
            val label = listOfNotNull(sample.provider, sample.window).joinToString(" ")
            val resetsSpoken = sample.resetsIn?.let { PrayerFormat.spoken(it) }
            val tokens = sample.tokens
            if (tokens != null) {
                return@mapIndexed IslandPageModel(
                    id = IslandPageId.AI_USAGE,
                    key = "ai.$index.${sample.provider}",
                    slider = SliderModel(
                        fraction = 0f,
                        label = label,
                        secondary = s.tokens(TokenFormat.compact(tokens)),
                        trailing = sample.resetsIn?.let { s.resetsIn(ResetTime.hoursMinutes(it)) },
                        description = s.tokenDescription(sample.provider, sample.window, TokenFormat.spoken(tokens), resetsSpoken),
                        stateText = TokenFormat.spoken(tokens),
                        meter = false,
                    ),
                    buttonIcon = IslandIcon.REFRESH,
                    buttonLabel = s.refreshUsage,
                    buttonAction = ButtonAction.REFRESH,
                )
            }
            val fraction = sample.fraction.coerceIn(0.0, 1.0)
            val percent = (fraction * 100).toInt()
            IslandPageModel(
                id = IslandPageId.AI_USAGE,
                key = "ai.$index.${sample.provider}",
                slider = SliderModel(
                    fraction = fraction.toFloat(),
                    label = label,
                    secondary = s.percent(percent),
                    trailing = sample.resetsIn?.let { s.resetsIn(ResetTime.hoursMinutes(it)) },
                    level = thresholds.level(fraction),
                    description = s.usageDescription(sample.provider, sample.window, percent, resetsSpoken),
                    stateText = s.percentSpoken(percent),
                ),
                buttonIcon = IslandIcon.REFRESH,
                buttonLabel = s.refreshUsage,
                buttonAction = ButtonAction.REFRESH,
            )
        }
    }
}

/** Token counts: "4.2M" on screen, "4.2 million tokens" for the screen reader. */
object TokenFormat {
    private fun scaled(n: Long): Pair<String, Int> {
        val v = n.coerceAtLeast(0)
        return when {
            v >= 1_000_000_000 -> one(v / 1e9) to 3
            v >= 1_000_000 -> one(v / 1e6) to 2
            v >= 1_000 -> one(v / 1e3) to 1
            else -> v.toString() to 0
        }
    }

    /** One decimal below 100 ("4.2", "12.5"), none from 100 ("250"); a trailing ".0" is dropped. */
    private fun one(x: Double): String {
        val text = if (x < 100) java.lang.String.format(java.util.Locale.ROOT, "%.1f", x) else java.lang.String.format(java.util.Locale.ROOT, "%.0f", x)
        return text.removeSuffix(".0")
    }

    fun compact(n: Long): String {
        val (num, scale) = scaled(n)
        return num + when (scale) { 3 -> "B"; 2 -> "M"; 1 -> "K"; else -> "" }
    }

    fun spoken(n: Long): String {
        val (num, scale) = scaled(n)
        return when (scale) {
            3 -> "$num billion tokens"
            2 -> "$num million tokens"
            1 -> "$num thousand tokens"
            else -> if (num == "1") "1 token" else "$num tokens"
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
