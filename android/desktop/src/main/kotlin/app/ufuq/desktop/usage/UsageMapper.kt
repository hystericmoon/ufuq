package app.ufuq.desktop.usage

import app.ufuq.core.ActivitySource
import app.ufuq.core.LiveActivity
import app.ufuq.core.UsageProvider
import app.ufuq.core.UsageResult
import app.ufuq.core.UsageSummary
import app.ufuq.core.UsageWindowKind
import app.ufuq.core.UsageWindowReading
import app.ufuq.desktop.island.AiUsageSample
import app.ufuq.desktop.island.IslandStrings
import java.time.Duration
import java.time.Instant

/** What one account's parser returned. */
data class AccountReadings(
    val label: String,
    val provider: UsageProvider,
    val result: UsageResult<List<UsageWindowReading>>,
)

/** Pure mapping from parser output to what page B and the collapsed pill show. */
object UsageMapper {
    /** One sample per available account: its worst window. Unavailable accounts and empty ones are left out. */
    fun samples(accounts: List<AccountReadings>, now: Instant): List<AiUsageSample> = accounts.mapNotNull { account ->
        val readings = account.result.valueOrNull.orEmpty()
        val worst = UsageSummary.worst(readings) ?: return@mapNotNull null
        AiUsageSample(
            provider = account.label,
            fraction = worst.snapshot.fraction.coerceIn(0.0, 1.0),
            resetsIn = worst.snapshot.resetsAt?.let { Duration.between(now, it) }?.takeIf { !it.isNegative && !it.isZero },
            window = windowLabel(worst.kind),
            estimated = worst.isEstimated,
        )
    }

    fun windowLabel(kind: UsageWindowKind): String = when (kind) {
        UsageWindowKind.Session5h -> "5h"
        UsageWindowKind.Weekly -> "week"
        is UsageWindowKind.ModelGroup -> kind.name
    }

    /** "Claude" for `.claude`, "Claude work" for `.claude-work`, "Claude <name>" for any other folder name. */
    fun claudeLabel(configDir: String): String {
        val name = configDir.trimEnd('/', '\\').substringAfterLast('/').substringAfterLast('\\')
        val bare = name.removePrefix(".")
        if (bare.startsWith("claude", ignoreCase = true)) {
            val rest = bare.drop("claude".length).trimStart('-', '_', '.')
            return if (rest.isEmpty()) "Claude" else "Claude $rest"
        }
        return if (name.isEmpty()) "Claude" else "Claude $name"
    }

    /** The collapsed pill's right wing: the worst sample as "Claude 82%". Null when there is none. */
    fun activity(samples: List<AiUsageSample>, strings: IslandStrings): LiveActivity? {
        val worst = samples.maxByOrNull { it.fraction } ?: return null
        val percent = (worst.fraction * 100).toInt()
        val name = worst.provider.substringBefore(' ')
        return LiveActivity(
            id = "ai.usage",
            moduleId = "ai",
            source = ActivitySource.AI_USAGE,
            text = "$name ${strings.percent(percent)}",
            accessibilityLabel = strings.usageDescription(worst.provider, worst.window, percent, worst.estimated, null),
            usageFraction = worst.fraction,
        )
    }
}
