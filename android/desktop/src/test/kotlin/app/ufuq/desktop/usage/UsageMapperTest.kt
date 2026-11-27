package app.ufuq.desktop.usage

import app.ufuq.core.UsageProvider
import app.ufuq.core.UsageResult
import app.ufuq.core.UsageSnapshot
import app.ufuq.core.UsageWindowKind
import app.ufuq.core.UsageWindowReading
import app.ufuq.core.usage.InMemoryFileSource
import app.ufuq.desktop.island.AiUsageSample
import app.ufuq.desktop.island.EnglishIslandStrings
import app.ufuq.desktop.island.TokenFormat
import app.ufuq.desktop.settings.DesktopSettings
import kotlinx.coroutines.runBlocking
import java.nio.file.Files
import java.time.Duration
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class UsageMapperTest {
    private val now = Instant.parse("2026-11-26T12:00:00Z")

    private fun claudeLine(ts: String, id: String, tokens: Long) =
        """{"type":"assistant","timestamp":"$ts","requestId":"r_$id","message":{"id":"m_$id","model":"claude-sonnet-5-5","usage":{"input_tokens":$tokens,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"""

    private val codexLine =
        """{"timestamp":"2026-11-26T11:50:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":12.5,"window_minutes":300,"resets_in_seconds":1000},"secondary":{"used_percent":8.0,"window_minutes":10080,"resets_in_seconds":500000}}}}"""

    private val files = InMemoryFileSource.ofStrings(
        mapOf(
            "/u/.claude/projects/p/a.jsonl" to listOf(claudeLine("2026-11-26T10:20:00.000Z", "1", 6_000_000), claudeLine("2026-11-26T11:00:00.000Z", "2", 3_000_000)).joinToString("\n"),
            "/u/.claude-work/projects/p/b.jsonl" to claudeLine("2026-11-26T11:00:00.000Z", "3", 1_000_000),
            "/u/.codex/sessions/2026/11/26/rollout-2026-11-26T09-00-00-a.jsonl" to codexLine,
        ),
    )

    @Test fun claudeIsATokenCountWithAResetTime() {
        val claude = UsageRepository(files, "/u/.codex/sessions").claudeSamples(DesktopSettings(claudeDirs = listOf("/u/.claude")), now).single()
        assertEquals("Claude", claude.provider)
        assertEquals("5h", claude.window)
        assertEquals(9_000_000L, claude.tokens) // the 10:00-15:00 block
        assertTrue(claude.isTokenCount)
        assertEquals(Duration.ofHours(3), claude.resetsIn)
    }

    @Test fun claudeBetweenBlocksIsZeroWithNoReset() {
        val later = Instant.parse("2026-11-26T16:00:00Z")
        val claude = UsageRepository(files, "/u/.codex/sessions").claudeSamples(DesktopSettings(claudeDirs = listOf("/u/.claude")), later).single()
        assertEquals(0L, claude.tokens)
        assertNull(claude.resetsIn)
    }

    @Test fun codexRateLimitsArePercentages() = runBlocking {
        val codex = UsageMapper.samples(listOf(UsageRepository(files, "/u/.codex/sessions").readCodex(now)), now)
        // The worst of the two windows is the 5h one at 12.5%.
        assertEquals(1, codex.size)
        assertEquals("Codex", codex[0].provider)
        assertEquals(0.125, codex[0].fraction, 1e-9)
        assertEquals(false, codex[0].isTokenCount)
        assertEquals(Duration.ofSeconds(400), codex[0].resetsIn) // captured 11:50 + 1000 s = 12:06:40
    }

    @Test fun twoClaudeAccountsGetTheirOwnLabels() = runBlocking {
        val settings = DesktopSettings(claudeDirs = listOf("/u/.claude", "/u/.claude-work"))
        val samples = UsageRepository(files, "/u/.codex/sessions").load(settings, now)
        assertEquals(listOf("Claude", "Claude work", "Codex"), samples.map { it.provider })
    }

    @Test fun aMissingFolderIsLeftOutNotFatal() = runBlocking {
        val settings = DesktopSettings(claudeDirs = listOf("/nowhere/.claude"))
        val samples = UsageRepository(InMemoryFileSource(), "/nowhere/.codex").load(settings, now)
        assertTrue(samples.isEmpty())
    }

    @Test fun realFilesOnDiskAreRead() = runBlocking {
        val dir = Files.createTempDirectory("ufuq-claude")
        try {
            val log = dir.resolve("projects/p").also { Files.createDirectories(it) }.resolve("a.jsonl")
            Files.writeString(log, claudeLine("2026-11-26T10:20:00.000Z", "1", 15_000_000))
            val samples = UsageRepository(codexSessionsDir = dir.resolve("no-codex").toString()).load(DesktopSettings(claudeDirs = listOf(dir.toString())), now)
            assertEquals(15_000_000L, samples.first { it.isTokenCount }.tokens)
        } finally {
            dir.toFile().deleteRecursively()
        }
    }

    @Test fun worstWindowWinsAndPastResetsAreDropped() {
        val readings = listOf(
            UsageWindowReading(UsageWindowKind.Session5h, UsageSnapshot(0.4, now, now.minusSeconds(5))),
            UsageWindowReading(UsageWindowKind.Weekly, UsageSnapshot(0.9, now, now.plusSeconds(3600))),
        )
        val s = UsageMapper.samples(listOf(AccountReadings("Claude", UsageProvider.CLAUDE, UsageResult.Available(readings))), now).single()
        assertEquals("week", s.window)
        assertEquals(0.9, s.fraction, 1e-9)
        assertEquals(Duration.ofHours(1), s.resetsIn)
    }

    @Test fun unavailableAndEmptyAccountsAreSkipped() {
        val out = UsageMapper.samples(
            listOf(
                AccountReadings("Claude", UsageProvider.CLAUDE, UsageResult.Unavailable("no logs")),
                AccountReadings("Codex", UsageProvider.CODEX, UsageResult.Available(emptyList())),
            ),
            now,
        )
        assertTrue(out.isEmpty())
    }

    @Test fun labelsFromFolderNames() {
        assertEquals("Claude", UsageMapper.claudeLabel("C:\\Users\\me\\.claude"))
        assertEquals("Claude", UsageMapper.claudeLabel("/home/me/.claude/"))
        assertEquals("Claude work", UsageMapper.claudeLabel("C:\\Users\\me\\.claude-work"))
        assertEquals("Claude personal", UsageMapper.claudeLabel("/x/.claude_personal"))
        assertEquals("Claude acme", UsageMapper.claudeLabel("D:\\acme"))
    }

    @Test fun pillActivityShowsTheWorstAccountAndKeepsTheFractionForTheArbiter() {
        val a = UsageMapper.activity(
            listOf(AiUsageSample("Claude", 0.0, window = "5h", tokens = 990_000_000), AiUsageSample("Codex work", 0.82, window = "5h")),
            EnglishIslandStrings,
        )
        assertNotNull(a)
        assertEquals("Codex 82%", a.text)
        assertEquals(0.82, a.usageFraction)
        assertEquals("Codex work 5-hour session, 82 percent used", a.accessibilityLabel)
        assertNull(UsageMapper.activity(emptyList(), EnglishIslandStrings))
    }

    @Test fun pillWithOnlyTokenCountsShowsTokensAndNoFraction() {
        val a = assertNotNull(UsageMapper.activity(listOf(AiUsageSample("Claude work", 0.0, window = "5h", tokens = 4_213_000)), EnglishIslandStrings))
        assertEquals("Claude 4.2M", a.text)
        assertNull(a.usageFraction)
        assertEquals("Claude work 5-hour session, 4.2 million tokens used", a.accessibilityLabel)
    }

    @Test fun tokenFormat() {
        assertEquals("0", TokenFormat.compact(0))
        assertEquals("999", TokenFormat.compact(999))
        assertEquals("1K", TokenFormat.compact(1_000))
        assertEquals("4.2M", TokenFormat.compact(4_213_000))
        assertEquals("12.5M", TokenFormat.compact(12_500_000))
        assertEquals("250M", TokenFormat.compact(250_000_000))
        assertEquals("1.1B", TokenFormat.compact(1_100_000_000))
        assertEquals("4.2 million tokens", TokenFormat.spoken(4_213_000))
        assertEquals("1 token", TokenFormat.spoken(1))
    }
}
