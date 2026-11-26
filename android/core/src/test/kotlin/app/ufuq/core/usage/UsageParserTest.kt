package app.ufuq.core.usage

import app.ufuq.core.UsageAccount
import app.ufuq.core.UsageProvider
import app.ufuq.core.UsageResult
import app.ufuq.core.UsageSnapshot
import app.ufuq.core.UsageSummary
import app.ufuq.core.UsageWindowKind
import app.ufuq.core.UsageWindowReading
import java.io.File
import java.nio.file.Path
import java.time.Instant
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

internal fun fixture(path: String): String {
    val url = checkNotNull(ClaudeLogParserTest::class.java.getResource("/fixtures")) { "fixtures missing" }
    return File(url.toURI()).toPath().resolve(path).toString()
}

internal fun utc(s: String): Instant = Instant.parse(s)

internal fun <T> UsageResult<T>.unavailableReason(): String =
    (this as? UsageResult.Unavailable)?.reason ?: fail("expected unavailable")

internal fun <T> UsageResult<T>.value(): T = valueOrNull ?: fail("expected available, got $this")

class ClaudeLogParserTest {
    @Test
    fun normalFixtureDedupesSkipsAndBlocks() {
        val report = ClaudeLogParser.parse(fixture("claude/normal")).value()
        assertEquals(2, report.filesRead)
        assertEquals(5, report.entries.size)
        assertEquals(2, report.duplicatesDropped)
        assertEquals(2, report.skippedLines) // garbage line + bad timestamp
        assertEquals(4, report.blocks.size)

        val block = assertNotNull(report.currentBlock(utc("2026-11-26T12:00:00Z")))
        assertEquals(utc("2026-11-26T10:00:00Z"), block.start)
        assertEquals(utc("2026-11-26T15:00:00Z"), block.end)
        assertEquals(2, block.messageCount)
        // msg_1 keeps the fullest streamed copy (10+50+100), msg_2 is 20+30+1000.
        assertEquals(TokenCounts(input = 30, output = 80, cacheCreation = 100, cacheRead = 1000), block.tokens)
        assertNull(report.currentBlock(utc("2026-11-26T15:30:00Z")))
        assertEquals(10L, report.currentBlock(utc("2026-11-26T17:00:00Z"))?.tokens?.total)
    }

    @Test
    fun weeklyWindowIsRolling() {
        val report = ClaudeLogParser.parse(fixture("claude/normal")).value()
        // 11-20 entry is inside the 7 days, 11-10 is not.
        assertEquals(1000L + 1210 + 10, report.weeklyTokens(utc("2026-11-26T17:00:00Z")).total)
        // A day later, 11-20 09:00 has aged out.
        assertEquals(1210L + 10, report.weeklyTokens(utc("2026-11-27T10:00:00Z")).total)
    }

    @Test
    fun missingDirIsUnavailable() {
        val result = ClaudeLogParser.parse(fixture("claude/does-not-exist"))
        assertFalse(result.unavailableReason().isEmpty())
        assertFalse(result.status.isAvailable)
    }

    @Test
    fun emptyFileIsAvailableWithNoData() {
        val report = ClaudeLogParser.parse(fixture("claude/empty")).value()
        assertTrue(report.entries.isEmpty())
        assertTrue(report.blocks.isEmpty())
        assertNull(report.currentBlock(Instant.now()))
    }

    @Test
    fun binaryGarbageIsUnavailableNotACrash() {
        ClaudeLogParser.parse(fixture("claude/garbage")).unavailableReason()
    }

    @Test
    fun gapOverFiveHoursStartsNewBlockEvenInsideWindow() {
        val a = """{"type":"assistant","timestamp":"2026-11-26T10:00:00Z","requestId":"a","message":{"id":"1","usage":{"input_tokens":1}}}"""
        val b = """{"type":"assistant","timestamp":"2026-11-26T14:59:00Z","requestId":"b","message":{"id":"2","usage":{"input_tokens":1}}}"""
        val c = """{"type":"assistant","timestamp":"2026-11-26T15:01:00Z","requestId":"c","message":{"id":"3","usage":{"input_tokens":1}}}"""
        val report = ClaudeLogParser.parse(listOf(listOf(a, b, c).joinToString("\n").toByteArray())).value()
        assertEquals(listOf(2, 1), report.blocks.map { it.messageCount })
    }

    @Test
    fun inMemorySourceAndUnreadableFiles() {
        val line = """{"type":"assistant","timestamp":"2026-11-26T10:00:00Z","requestId":"a","message":{"id":"1","usage":{"output_tokens":7}}}"""
        // The parser joins with the platform separator, so key the in-memory files the same way.
        val dir = Path.of("/c").toString()
        fun key(name: String) = Path.of(dir, "projects", "p", name).toString()
        val ok = InMemoryFileSource(files = mapOf(key("a.jsonl") to line.toByteArray()), unreadable = setOf(key("b.jsonl")))
        val okReport = ClaudeLogParser.parse(dir, ok).value()
        assertEquals(1, okReport.filesFailed)
        assertEquals(7L, okReport.entries.first().tokens.output)

        ClaudeLogParser.parse(dir, InMemoryFileSource(unreadable = setOf(key("b.jsonl")))).unavailableReason()
        ClaudeLogParser.parse("/nowhere", InMemoryFileSource()).unavailableReason()
    }

    @Test
    fun defaultConfigDir() {
        assertEquals("/x", ClaudeLogParser.defaultConfigDir(mapOf("CLAUDE_CONFIG_DIR" to "/x"), "/h"))
        assertEquals(Path.of("/h", ".claude").toString(), ClaudeLogParser.defaultConfigDir(emptyMap(), "/h"))
        assertEquals(Path.of("/h", ".claude").toString(), ClaudeLogParser.defaultConfigDir(mapOf("CLAUDE_CONFIG_DIR" to ""), "/h"))
    }

    @Test
    fun windowsStylePathsAreNotUnixOnly() {
        val home = "C:\\Users\\me"
        val cfg = ClaudeLogParser.defaultConfigDir(emptyMap(), home)
        assertEquals(Path.of(home, ".claude").toString(), cfg)
        assertTrue(cfg.startsWith("C:\\Users\\me"))
        assertEquals(Path.of(home, ".codex", "sessions").toString(), CodexParser.defaultSessionsDir(home))
        assertEquals(Path.of(home, ".claude").toString(), expandTilde("~\\.claude", home))

        // Keys built the way the parser builds them (Path.of / resolve), whatever the OS separator is.
        val line = """{"type":"assistant","timestamp":"2026-11-26T10:00:00Z","requestId":"a","message":{"id":"1","usage":{"output_tokens":3}}}"""
        val key = Path.of(cfg, "projects", "p", "a.jsonl").toString()
        val report = ClaudeLogParser.parse(cfg, InMemoryFileSource.ofStrings(mapOf(key to line))).value()
        assertEquals(3L, report.entries.single().tokens.output)

        // Explicit backslash-separated keys also match a backslash-terminated or plain directory.
        val src = InMemoryFileSource.ofStrings(mapOf("C:\\s\\2026\\rollout-a.jsonl" to "{}"))
        assertEquals(listOf("C:\\s\\2026\\rollout-a.jsonl"), src.files("C:\\s", ".jsonl"))
        assertEquals(listOf("C:\\s\\2026\\rollout-a.jsonl"), src.files("C:\\s\\", ".jsonl"))
    }
}

class CodexParserTest {
    @Test
    fun latestSnapshotAcrossFiles() {
        val limits = CodexParser.parse(fixture("codex/normal")).value()
        assertEquals(utc("2026-11-26T10:30:00Z"), limits.capturedAt)
        val session = limits.readings.first { it.kind == UsageWindowKind.Session5h }
        assertEquals(0.42, session.snapshot.fraction, 1e-9)
        assertEquals(utc("2026-11-26T10:30:00Z").plusSeconds(1234), session.snapshot.resetsAt)
        assertFalse(session.isEstimated)
        val weekly = limits.readings.first { it.kind == UsageWindowKind.Weekly }
        assertEquals(0.10, weekly.snapshot.fraction, 1e-9)
        assertEquals(42, UsageSummary.worstPercent(limits.readings))
    }

    @Test
    fun resetsAtEpochAndMissingWindowMinutes() {
        val limits = CodexParser.parse(fixture("codex/alt")).value()
        assertEquals(2, limits.readings.size)
        assertEquals(Instant.ofEpochSecond(1_796_000_000), limits.readings[0].snapshot.resetsAt)
        assertEquals(UsageWindowKind.Weekly, limits.readings[1].kind) // falls back to secondary = weekly
        assertNull(limits.readings[1].snapshot.resetsAt)
    }

    @Test
    fun missingRateLimitsIsUnavailable() {
        assertTrue(CodexParser.parse(fixture("codex/norate")).unavailableReason().contains("rate-limit"))
    }

    @Test
    fun garbageAndMissingDirAreUnavailable() {
        CodexParser.parse(fixture("codex/garbage")).unavailableReason()
        CodexParser.parse(fixture("codex/nope")).unavailableReason()
    }

    @Test
    fun windowMinutesClassifyKind() {
        assertEquals(UsageWindowKind.Session5h, CodexParser.kind(300.0))
        assertEquals(UsageWindowKind.Weekly, CodexParser.kind(10080.0))
    }

    @Test
    fun nonRolloutFilesIgnoredAndEmptyDirUnavailable() {
        val src = InMemoryFileSource.ofStrings(mapOf("/s/2026/11/26/notes.jsonl" to "{}"))
        CodexParser.parse("/s", src).unavailableReason()
    }
}

class UsageModelParserTest {
    private fun reading(kind: UsageWindowKind, f: Double) =
        UsageWindowReading(kind, UsageSnapshot(f, Instant.EPOCH))

    @Test
    fun estimateIsLabelledEstimated() {
        val report = ClaudeLogParser.parse(fixture("claude/normal")).value()
        val est = UsageEstimate(sessionBudgetTokens = 2420, weeklyBudgetTokens = 4440)
        val readings = est.readings(report, utc("2026-11-26T12:00:00Z"))
        assertEquals(2, readings.size)
        assertTrue(readings.all { it.isEstimated })
        assertEquals(0.5, readings[0].snapshot.fraction, 1e-9)
        assertEquals(utc("2026-11-26T15:00:00Z"), readings[0].snapshot.resetsAt)
    }

    @Test
    fun resolverPrefersLiveThenEstimateThenUnavailable() = runBlocking {
        val account = UsageAccount("a", UsageProvider.CLAUDE, "Work", configDir = fixture("claude/normal"))
        val est = UsageEstimate(sessionBudgetTokens = 1000, weeklyBudgetTokens = 1000)
        val now = utc("2026-11-26T12:00:00Z")
        val liveReading = reading(UsageWindowKind.Session5h, 0.3)

        val live = ClaudeUsageResolver.readings(
            account, FakeClaudeLimitSource(Result.success(listOf(liveReading))), est, now = now,
        )
        assertEquals(listOf(liveReading), live.valueOrNull)

        val fallback = ClaudeUsageResolver.readings(
            account, FakeClaudeLimitSource(Result.failure(IllegalStateException("boom"))), est, now = now,
        )
        assertEquals(true, fallback.valueOrNull?.all { it.isEstimated })

        val broken = UsageAccount("b", UsageProvider.CLAUDE, "Gone", configDir = fixture("claude/nope"))
        val none = ClaudeUsageResolver.readings(broken, null, est, now = now)
        assertFalse(none.status.isAvailable)
        assertTrue(none.unavailableReason().startsWith("no live source; "))
    }
}
