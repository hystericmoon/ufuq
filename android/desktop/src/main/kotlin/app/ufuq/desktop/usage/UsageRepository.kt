package app.ufuq.desktop.usage

import app.ufuq.core.UsageAccount
import app.ufuq.core.UsageProvider
import app.ufuq.core.UsageResult
import app.ufuq.core.usage.ClaudeLogParser
import app.ufuq.core.usage.ClaudeUsageResolver
import app.ufuq.core.usage.CodexParser
import app.ufuq.core.usage.FileSource
import app.ufuq.core.usage.LocalFileSource
import app.ufuq.core.usage.UsageEstimate
import app.ufuq.desktop.island.AiUsageSample
import app.ufuq.desktop.settings.DesktopSettings
import java.time.Instant

/**
 * Reads the local logs: every configured Claude folder (`%USERPROFILE%\.claude` by default) through
 * [ClaudeLogParser] with the [UsageEstimate] fallback (labelled "estimated"), and Codex sessions
 * (`%USERPROFILE%\.codex`) through [CodexParser], whose rate limits are the real ones.
 * A source that fails is left out; it never throws.
 */
class UsageRepository(
    private val fileSource: FileSource = LocalFileSource(),
    private val codexSessionsDir: String = CodexParser.defaultSessionsDir(),
) {
    suspend fun load(settings: DesktopSettings, now: Instant = Instant.now()): List<AiUsageSample> =
        UsageMapper.samples(readAccounts(settings, now), now)

    suspend fun readAccounts(settings: DesktopSettings, now: Instant): List<AccountReadings> {
        val estimate = UsageEstimate(settings.sessionBudgetTokens, settings.weeklyBudgetTokens)
        val dirs = settings.claudeDirs.ifEmpty { listOf(ClaudeLogParser.defaultConfigDir()) }
        val out = mutableListOf<AccountReadings>()
        for (dir in dirs) {
            val account = UsageAccount(id = "claude:$dir", provider = UsageProvider.CLAUDE, displayName = UsageMapper.claudeLabel(dir), configDir = dir)
            val result = try {
                ClaudeUsageResolver.readings(account, live = null, estimate = estimate, fileSource = fileSource, now = now)
            } catch (e: kotlin.coroutines.cancellation.CancellationException) {
                throw e
            } catch (e: Exception) {
                UsageResult.Unavailable("Claude usage failed: ${e.message}")
            }
            out += AccountReadings(account.displayName, UsageProvider.CLAUDE, result)
        }
        val codex = try {
            when (val parsed = CodexParser.parse(sessionsDir = codexSessionsDir, source = fileSource, now = now)) {
                is UsageResult.Available -> UsageResult.Available(parsed.value.readings)
                is UsageResult.Unavailable -> parsed
            }
        } catch (e: kotlin.coroutines.cancellation.CancellationException) {
            throw e
        } catch (e: Exception) {
            UsageResult.Unavailable("Codex usage failed: ${e.message}")
        }
        out += AccountReadings("Codex", UsageProvider.CODEX, codex)
        return out
    }
}
