package app.ufuq.desktop.usage

import app.ufuq.core.UsageProvider
import app.ufuq.core.UsageResult
import app.ufuq.core.usage.ClaudeLogParser
import app.ufuq.core.usage.ClaudeUsageReport
import app.ufuq.core.usage.CodexParser
import app.ufuq.core.usage.FileSource
import app.ufuq.core.usage.LocalFileSource
import app.ufuq.desktop.island.AiUsageSample
import app.ufuq.desktop.settings.DesktopSettings
import java.time.Duration
import java.time.Instant
import kotlin.coroutines.cancellation.CancellationException

/**
 * Reads the local logs. Claude (every configured folder, `%USERPROFILE%\.claude` by default): tokens
 * used in the current 5-hour block, shown as a count with no % until Claude's live limit is
 * verified (owner decision, 27 Nov 2026). Codex (`%USERPROFILE%\.codex`): its real rate limits.
 * A source that fails is left out; it never throws.
 */
class UsageRepository(
    private val fileSource: FileSource = LocalFileSource(),
    private val codexSessionsDir: String = CodexParser.defaultSessionsDir(),
) {
    suspend fun load(settings: DesktopSettings, now: Instant = Instant.now()): List<AiUsageSample> =
        claudeSamples(settings, now) + UsageMapper.samples(listOf(readCodex(now)), now)

    /** One token-count sample per Claude folder that has logs; none for a missing or broken folder. */
    fun claudeSamples(settings: DesktopSettings, now: Instant): List<AiUsageSample> {
        val dirs = settings.claudeDirs.ifEmpty { listOf(ClaudeLogParser.defaultConfigDir()) }
        return dirs.mapNotNull { dir ->
            val report = try {
                (ClaudeLogParser.parse(dir, fileSource) as? UsageResult.Available)?.value
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                null
            } ?: return@mapNotNull null
            claudeSample(UsageMapper.claudeLabel(dir), report, now)
        }
    }

    suspend fun readCodex(now: Instant): AccountReadings {
        val codex = try {
            when (val parsed = CodexParser.parse(sessionsDir = codexSessionsDir, source = fileSource, now = now)) {
                is UsageResult.Available -> UsageResult.Available(parsed.value.readings)
                is UsageResult.Unavailable -> parsed
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            UsageResult.Unavailable("Codex usage failed: ${e.message}")
        }
        return AccountReadings("Codex", UsageProvider.CODEX, codex)
    }

    companion object {
        /** Tokens in the active 5-hour block (0 between blocks), with its reset time. */
        fun claudeSample(label: String, report: ClaudeUsageReport, now: Instant): AiUsageSample {
            val block = report.currentBlock(now)
            return AiUsageSample(
                provider = label,
                fraction = 0.0,
                resetsIn = block?.end?.let { Duration.between(now, it) }?.takeIf { !it.isNegative && !it.isZero },
                window = "5h",
                tokens = block?.tokens?.total ?: 0L,
            )
        }
    }
}
