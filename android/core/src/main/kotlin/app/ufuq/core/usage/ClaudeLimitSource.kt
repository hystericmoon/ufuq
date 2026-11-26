package app.ufuq.core.usage

import app.ufuq.core.UsageAccount
import app.ufuq.core.UsageResult
import app.ufuq.core.UsageSnapshot
import app.ufuq.core.UsageWindowKind
import app.ufuq.core.UsageWindowReading
import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException

/** Live Claude limits (the 5-hour and weekly %). The real endpoint is unverified, so the app implements this later. */
interface ClaudeLimitSource {
    suspend fun fetchLimits(account: UsageAccount): List<UsageWindowReading>
}

/** Test double: returns fixed readings or throws. */
class FakeClaudeLimitSource(private val result: Result<List<UsageWindowReading>>) : ClaudeLimitSource {
    override suspend fun fetchLimits(account: UsageAccount): List<UsageWindowReading> = result.getOrThrow()
}

/**
 * Fallback when the live source fails: local token counts against assumed budgets.
 * Every reading is labelled `isEstimated = true`.
 */
data class UsageEstimate(
    /** Tokens assumed to fill the 5-hour window / the week. Plan-dependent; user-configurable. */
    val sessionBudgetTokens: Long,
    val weeklyBudgetTokens: Long,
) {
    fun readings(report: ClaudeUsageReport, now: Instant): List<UsageWindowReading> {
        val out = mutableListOf<UsageWindowReading>()
        if (sessionBudgetTokens > 0) {
            val block = report.currentBlock(now)
            val used = block?.tokens?.total ?: 0L
            out += UsageWindowReading(
                UsageWindowKind.Session5h,
                UsageSnapshot(used.toDouble() / sessionBudgetTokens, now, block?.end),
                isEstimated = true,
            )
        }
        if (weeklyBudgetTokens > 0) {
            val used = report.weeklyTokens(now).total
            out += UsageWindowReading(
                UsageWindowKind.Weekly,
                UsageSnapshot(used.toDouble() / weeklyBudgetTokens, now),
                isEstimated = true,
            )
        }
        return out
    }
}

object ClaudeUsageResolver {
    /** Live readings when the source works, else the estimate from local logs, else unavailable. */
    suspend fun readings(
        account: UsageAccount,
        live: ClaudeLimitSource?,
        estimate: UsageEstimate,
        fileSource: FileSource = LocalFileSource(),
        now: Instant = Instant.now(),
    ): UsageResult<List<UsageWindowReading>> {
        var liveFailure = "no live source"
        if (live != null) {
            try {
                val readings = live.fetchLimits(account)
                if (readings.isNotEmpty()) return UsageResult.Available(readings)
                liveFailure = "live source returned no windows"
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                liveFailure = "live source failed: $e"
            }
        }
        val dir = account.configDir ?: ClaudeLogParser.defaultConfigDir()
        return when (val parsed = ClaudeLogParser.parse(dir, fileSource)) {
            is UsageResult.Available -> UsageResult.Available(estimate.readings(parsed.value, now))
            is UsageResult.Unavailable -> UsageResult.Unavailable("$liveFailure; ${parsed.reason}")
        }
    }
}
