package app.ufuq.core.usage

import app.ufuq.core.UsageSummary
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Rule
import org.junit.rules.TemporaryFolder
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class UsageHardeningTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private fun line(id: String, ts: String = "2026-11-26T10:00:00Z", out: String = "1", req: String? = null): String {
        val r = req?.let { """"requestId":"$it",""" } ?: ""
        return """{"type":"assistant","timestamp":"$ts",$r"message":{"id":"$id","usage":{"output_tokens":$out}}}"""
    }

    private fun rollout(ts: String, pct: Int) =
        """{"timestamp":"$ts","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":$pct,"window_minutes":300}}}}"""

    @Test
    fun tokenArithmeticSaturatesInsteadOfOverflowing() {
        val big = TokenCounts(Long.MAX_VALUE, Long.MAX_VALUE, Long.MAX_VALUE, Long.MAX_VALUE)
        assertEquals(Long.MAX_VALUE, big.total)
        assertEquals(Long.MAX_VALUE, (big + big).input)
    }

    @Test
    fun hugeTokenValuesDoNotOverflowAcrossManyEntries() {
        val lines = (0 until 20_000).map { line("m$it", out = "999999999999999") }
        val report = ClaudeLogParser.parse(listOf(lines.joinToString("\n").toByteArray())).value()
        assertEquals(Long.MAX_VALUE, report.blocks.first().tokens.output)
        report.weeklyTokens(utc("2026-11-26T12:00:00Z")).total
    }

    @Test
    fun partialLastLineIsNotCountedAsCorruption() {
        val data = (line("a") + "\n" + """{"type":"assistant","timestamp":"2026-11-26T10:0""").toByteArray()
        val report = ClaudeLogParser.parse(listOf(data)).value()
        assertEquals(0, report.skippedLines)
        assertEquals(1, report.entries.size)
        // A file that is only a half-written first line is empty, not "unavailable".
        assertNotNull(ClaudeLogParser.parse(listOf("""{"type":"assist""".toByteArray())).valueOrNull)
    }

    @Test
    fun completeBadLineStillCounted() {
        val data = (line("a") + "\nnot json\n" + line("b")).toByteArray()
        assertEquals(1, ClaudeLogParser.parse(listOf(data)).valueOrNull?.skippedLines)
    }

    @Test
    fun bomAndCrlfAreTolerated() {
        val data = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) + (line("a") + "\r\n" + line("b") + "\r\n").toByteArray()
        val report = ClaudeLogParser.parse(listOf(data)).value()
        assertEquals(2, report.entries.size)
        assertEquals(0, report.skippedLines)
    }

    @Test
    fun deeplyNestedAndInvalidUtf8LinesDoNotCrash() {
        val deep = "[".repeat(200_000)
        val bytes = (deep + "\n").toByteArray() + byteArrayOf(0xFF.toByte(), 0xFE.toByte(), 0x7B, 0x0A) + line("ok").toByteArray()
        val report = ClaudeLogParser.parse(listOf(bytes)).value()
        assertEquals(1, report.entries.size)
    }

    @Test
    fun dedupeKeysDoNotCollideBetweenMessageIdAndRequestId() {
        val a = """{"type":"assistant","timestamp":"2026-11-26T10:00:00Z","message":{"id":"x","usage":{"output_tokens":1}}}"""
        val b = """{"type":"assistant","timestamp":"2026-11-26T10:00:01Z","requestId":"x","message":{"usage":{"output_tokens":1}}}"""
        val report = ClaudeLogParser.parse(listOf(listOf(a, b).joinToString("\n").toByteArray())).value()
        assertEquals(2, report.entries.size)
    }

    @Test
    fun epochTimestampsAreAccepted() {
        assertEquals(Instant.ofEpochSecond(1_796_000_000), JsonLines.date(JsonPrimitive(1_796_000_000L)))
        assertEquals(Instant.ofEpochSecond(1_796_000_000), JsonLines.date(JsonPrimitive(1_796_000_000_000L)))
        assertNull(JsonLines.date(JsonPrimitive(Double.NaN)))
        assertNull(JsonLines.date(JsonPrimitive(-5)))
        assertEquals(utc("2026-11-26T10:00:00Z"), JsonLines.date(JsonPrimitive("2026-11-26T17:00:00+07:00")))
    }

    @Test
    fun directoryNamedLikeLogIsNotAFailedFile() {
        val dir = tmp.newFolder()
        val proj = File(dir, "projects/p")
        assertTrue(File(proj, "weird.jsonl").mkdirs())
        File(proj, "ok.jsonl").writeText(line("a"))
        val report = ClaudeLogParser.parse(dir.path).value()
        assertEquals(0, report.filesFailed)
        assertEquals(1, report.filesRead)
    }

    @Test
    fun danglingSymlinkIsSkipped() {
        val dir = tmp.newFolder()
        val proj = File(dir, "projects/p").also { it.mkdirs() }
        File(proj, "ok.jsonl").writeText(line("a"))
        try {
            Files.createSymbolicLink(File(proj, "dangling.jsonl").toPath(), File(dir, "missing").toPath())
        } catch (e: Exception) {
            return // symlinks not permitted here (Windows without privilege)
        }
        val report = ClaudeLogParser.parse(dir.path).value()
        assertEquals(0, report.filesFailed)
        assertEquals(1, report.filesRead)
    }

    @Test
    fun tildeConfigDirIsExpanded() {
        val home = File(System.getProperty("user.home"))
        val name = ".ufuq-test-${UUID.randomUUID()}"
        val dir = File(home, name)
        try {
            assertTrue(File(dir, "projects").mkdirs())
            File(dir, "projects/a.jsonl").writeText(line("a"))
            assertEquals(1, ClaudeLogParser.parse("~/$name").valueOrNull?.entries?.size)
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun oversizedFileIsReadFromItsTailOnWholeLines() {
        val path = tmp.newFile("big.jsonl")
        path.writeText((0 until 200).joinToString("\n") { line("m$it") })
        val data = LocalFileSource(maxFileBytes = 2_000).read(path.path)
        assertTrue(data.size <= 2_000)
        val objects = JsonLines.objects(data)
        assertTrue(objects.isNotEmpty())
        assertTrue(objects.all { it != null }, "tail must start on a line boundary")
        assertTrue(String(data, Charsets.UTF_8).contains("m199"))
    }

    @Test
    fun codexPicksLatestByTimestampNotFileOrder() {
        val src = InMemoryFileSource.ofStrings(
            strings = mapOf(
                "/s/2026/11/26/rollout-b.jsonl" to rollout("2026-11-26T08:00:00Z", 10),
                "/s/2026/11/20/rollout-a.jsonl" to rollout("2026-11-26T09:00:00Z", 55) + "\n" + rollout("2026-11-26T07:00:00Z", 5),
            ),
        )
        val limits = CodexParser.parse("/s", src).value()
        assertEquals(0.55, limits.readings.first().snapshot.fraction, 1e-9)
    }

    @Test
    fun codexResetsAtMillisecondsAndOversizedPercent() {
        val l = """{"timestamp":"2026-11-26T10:00:00Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":"140","window_minutes":300,"resets_at":1796000000000},"secondary":{"used_percent":null}}}}"""
        val limits = CodexParser.parse(listOf(l.toByteArray())).value()
        assertEquals(1, limits.readings.size)
        assertEquals(Instant.ofEpochSecond(1_796_000_000), limits.readings[0].snapshot.resetsAt)
        assertEquals(100, UsageSummary.worstPercent(limits.readings))
    }

    @Test
    fun codexFutureTimestampDoesNotPinSnapshotForever() {
        val data = listOf(rollout("2099-01-01T00:00:00Z", 99), rollout("2026-11-26T10:00:00Z", 20)).joinToString("\n").toByteArray()
        val limits = CodexParser.parse(listOf(data), now = utc("2026-11-26T12:00:00Z")).value()
        assertEquals(0.20, limits.readings.first().snapshot.fraction, 1e-9)
    }
}
