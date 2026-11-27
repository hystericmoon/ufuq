package app.ufuq.core.usage

import app.ufuq.core.UsageResult
import java.nio.file.Path
import java.time.Duration
import java.time.Instant

data class TokenCounts(
    val input: Long = 0,
    val output: Long = 0,
    val cacheCreation: Long = 0,
    val cacheRead: Long = 0,
) {
    val total: Long get() = add(add(input, output), add(cacheCreation, cacheRead))

    operator fun plus(other: TokenCounts) = TokenCounts(
        add(input, other.input), add(output, other.output),
        add(cacheCreation, other.cacheCreation), add(cacheRead, other.cacheRead),
    )

    private companion object {
        /** Saturating add: corrupt logs must not overflow. */
        fun add(a: Long, b: Long): Long = try {
            Math.addExact(a, b)
        } catch (e: ArithmeticException) {
            if (a < 0) Long.MIN_VALUE else Long.MAX_VALUE
        }
    }
}

/** One assistant message's usage after deduplication. */
data class ClaudeUsageEntry(val timestamp: Instant, val model: String?, val tokens: TokenCounts)

/** A 5-hour block: starts at the first message's hour (UTC) and lasts 5 hours. */
data class ClaudeUsageBlock(
    val start: Instant,
    val end: Instant,
    val lastActivity: Instant,
    val tokens: TokenCounts,
    val messageCount: Int,
) {
    fun isActive(now: Instant): Boolean = now >= start && now < end
}

data class ClaudeUsageReport(
    val blocks: List<ClaudeUsageBlock>,
    val entries: List<ClaudeUsageEntry>,
    val filesRead: Int,
    val filesFailed: Int,
    /** Lines that were not valid JSON (or an assistant line with unusable fields). */
    val skippedLines: Int,
    val duplicatesDropped: Int,
) {
    /** The block containing [now], if any. */
    fun currentBlock(now: Instant): ClaudeUsageBlock? = blocks.lastOrNull { it.isActive(now) }

    /** Tokens over the 7 days up to [now]. */
    fun weeklyTokens(now: Instant): TokenCounts {
        val from = now.minus(ClaudeLogParser.WEEK_LENGTH)
        return entries.filter { it.timestamp > from && it.timestamp <= now }
            .fold(TokenCounts()) { acc, e -> acc + e.tokens }
    }
}

object ClaudeLogParser {
    val BLOCK_LENGTH: Duration = Duration.ofHours(5)
    val WEEK_LENGTH: Duration = Duration.ofDays(7)

    /** `<config dir>`: `CLAUDE_CONFIG_DIR` from [environment], else `<home>/.claude` (`%USERPROFILE%\.claude` on Windows). */
    fun defaultConfigDir(
        environment: Map<String, String> = System.getenv(),
        home: String = userHome(),
    ): String {
        environment["CLAUDE_CONFIG_DIR"]?.takeIf { it.isNotEmpty() }?.let { return it }
        return Path.of(home, ".claude").toString()
    }

    /** Reads every `projects/**/*.jsonl` under [configDir] (`~` is expanded), one file at a time. Never throws. */
    fun parse(configDir: String, source: FileSource = LocalFileSource()): UsageResult<ClaudeUsageReport> {
        val projects = try {
            Path.of(expandTilde(configDir)).resolve("projects").toString()
        } catch (e: Exception) {
            return UsageResult.Unavailable("Claude logs not readable: invalid path $configDir")
        }
        val paths = try {
            source.files(projects, ".jsonl")
        } catch (e: Exception) {
            return UsageResult.Unavailable("Claude logs not readable: ${e.message}")
        }
        val acc = Accumulator()
        var failed = 0
        for (path in paths) {
            val data = try {
                source.read(path)
            } catch (e: Exception) {
                null
            }
            if (data != null) acc.ingest(data) else failed++
        }
        if (paths.isNotEmpty() && acc.filesRead == 0) {
            return UsageResult.Unavailable("No Claude log file could be read ($failed failed)")
        }
        return acc.finish(failed)
    }

    /** Parses raw JSONL file contents. */
    fun parse(files: List<ByteArray>, filesFailed: Int = 0): UsageResult<ClaudeUsageReport> {
        val acc = Accumulator()
        for (data in files) acc.ingest(data)
        return acc.finish(filesFailed)
    }

    /** Folds files in one at a time so only the deduplicated entries stay in memory. */
    private class Accumulator {
        val byKey = LinkedHashMap<String, ClaudeUsageEntry>()
        val keyless = mutableListOf<ClaudeUsageEntry>()
        var skipped = 0
        var duplicates = 0
        var validObjects = 0
        var filesRead = 0

        fun ingest(data: ByteArray) {
            filesRead++
            JsonLines.forEachObject(data) { obj ->
                if (obj == null) {
                    skipped++
                    return@forEachObject
                }
                validObjects++
                if (JsonLines.string(obj["type"]) != "assistant") return@forEachObject
                val message = JsonLines.obj(obj["message"]) ?: return@forEachObject
                val usage = JsonLines.obj(message["usage"]) ?: return@forEachObject
                val timestamp = JsonLines.date(obj["timestamp"])
                if (timestamp == null) {
                    skipped++
                    return@forEachObject
                }
                fun tokens(key: String) = maxOf(JsonLines.int(usage[key]) ?: 0L, 0L)
                val entry = ClaudeUsageEntry(
                    timestamp, JsonLines.string(message["model"]),
                    TokenCounts(
                        tokens("input_tokens"), tokens("output_tokens"),
                        tokens("cache_creation_input_tokens"), tokens("cache_read_input_tokens"),
                    ),
                )
                // Prefixes keep a message id "x" apart from a request id "x".
                val ids = listOfNotNull(
                    JsonLines.string(message["id"])?.let { "m:$it" },
                    JsonLines.string(obj["requestId"])?.let { "r:$it" },
                )
                if (ids.isEmpty()) {
                    keyless += entry
                    return@forEachObject
                }
                val key = ids.joinToString("|")
                val existing = byKey[key]
                if (existing != null) {
                    duplicates++
                    // Streamed duplicates grow as the message completes; keep the fullest.
                    if (entry.tokens.total > existing.tokens.total) byKey[key] = entry
                } else {
                    byKey[key] = entry
                }
            }
        }

        fun finish(filesFailed: Int): UsageResult<ClaudeUsageReport> {
            if (validObjects == 0 && skipped > 0) {
                return UsageResult.Unavailable("Claude logs are not valid JSONL ($skipped bad lines)")
            }
            val entries = (byKey.values + keyless).sortedBy { it.timestamp }
            return UsageResult.Available(
                ClaudeUsageReport(blocks(entries), entries, filesRead, filesFailed, skipped, duplicates),
            )
        }
    }

    internal fun floorToHour(t: Instant): Instant = Instant.ofEpochSecond(Math.floorDiv(t.epochSecond, 3600L) * 3600L)

    /**
     * Entries must be sorted. A new block starts when a message falls past the current block's end,
     * or after a gap of more than 5 hours.
     */
    internal fun blocks(entries: List<ClaudeUsageEntry>): List<ClaudeUsageBlock> {
        val result = mutableListOf<ClaudeUsageBlock>()
        for (entry in entries) {
            val last = result.lastOrNull()
            if (last != null && entry.timestamp < last.end &&
                Duration.between(last.lastActivity, entry.timestamp) <= BLOCK_LENGTH
            ) {
                result[result.size - 1] = last.copy(
                    tokens = last.tokens + entry.tokens,
                    messageCount = last.messageCount + 1,
                    lastActivity = entry.timestamp,
                )
            } else {
                val start = floorToHour(entry.timestamp)
                result += ClaudeUsageBlock(start, start.plus(BLOCK_LENGTH), entry.timestamp, entry.tokens, 1)
            }
        }
        return result
    }
}
