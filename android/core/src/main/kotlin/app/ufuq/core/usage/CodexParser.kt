package app.ufuq.core.usage

import app.ufuq.core.UsageResult
import app.ufuq.core.UsageSnapshot
import app.ufuq.core.UsageWindowKind
import app.ufuq.core.UsageWindowReading
import java.nio.file.Path
import java.time.Duration
import java.time.Instant
import kotlinx.serialization.json.JsonObject
import kotlin.math.abs

/** The latest rate-limit snapshot found in Codex session logs. */
data class CodexRateLimits(val capturedAt: Instant, val readings: List<UsageWindowReading>)

/**
 * Parses `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`: `payload.type == "token_count"`,
 * `payload.rate_limits.{primary,secondary}` with `used_percent`, `window_minutes` and
 * `resets_in_seconds` or `resets_at`.
 */
object CodexParser {
    fun defaultSessionsDir(home: String = userHome()): String = Path.of(home, ".codex", "sessions").toString()

    /** Reads the newest [maxFiles] rollout files and returns the most recent snapshot. Never throws. */
    fun parse(
        sessionsDir: String = defaultSessionsDir(),
        source: FileSource = LocalFileSource(),
        maxFiles: Int = 20,
        now: Instant = Instant.now(),
    ): UsageResult<CodexRateLimits> {
        val dir = expandTilde(sessionsDir)
        val paths = try {
            source.files(dir, ".jsonl")
        } catch (e: Exception) {
            return UsageResult.Unavailable("Codex sessions not readable: ${e.message}")
        }
        val rollouts = paths
            .filter { it.substringAfterLast('/').substringAfterLast('\\').startsWith("rollout-") }
            .sortedDescending()
            .take(maxOf(maxFiles, 0))
        if (rollouts.isEmpty()) return UsageResult.Unavailable("No Codex session files found")

        val acc = Accumulator(now)
        var read = 0
        for (path in rollouts) {
            val data = try {
                source.read(path)
            } catch (e: Exception) {
                continue
            }
            acc.ingest(data)
            read++
        }
        if (read == 0) return UsageResult.Unavailable("No Codex session file could be read")
        return acc.finish()
    }

    /**
     * Snapshots stamped more than a day after [now] are clock skew or corruption and are ignored,
     * so one bad line cannot pin the "latest" snapshot forever.
     */
    fun parse(files: List<ByteArray>, now: Instant = Instant.now()): UsageResult<CodexRateLimits> {
        val acc = Accumulator(now)
        for (data in files) acc.ingest(data)
        return acc.finish()
    }

    private class Accumulator(val now: Instant) {
        var best: CodexRateLimits? = null
        var sawSnapshotLine = false

        fun ingest(data: ByteArray) {
            val latestAllowed = now.plus(Duration.ofDays(1))
            JsonLines.forEachObject(data) { obj ->
                if (obj == null) return@forEachObject
                val payload = JsonLines.obj(obj["payload"]) ?: return@forEachObject
                if (JsonLines.string(payload["type"]) != "token_count") return@forEachObject
                val limits = JsonLines.obj(payload["rate_limits"]) ?: return@forEachObject
                val timestamp = JsonLines.date(obj["timestamp"]) ?: return@forEachObject
                if (timestamp > latestAllowed) return@forEachObject
                sawSnapshotLine = true
                val readings = readings(limits, timestamp)
                if (readings.isEmpty()) return@forEachObject
                val current = best
                if (current != null && timestamp < current.capturedAt) return@forEachObject
                best = CodexRateLimits(timestamp, readings)
            }
        }

        fun finish(): UsageResult<CodexRateLimits> {
            best?.let { return UsageResult.Available(it) }
            return UsageResult.Unavailable(
                if (sawSnapshotLine) {
                    "Codex rate_limits had no usable window"
                } else {
                    "No Codex rate-limit snapshot found in session logs"
                },
            )
        }
    }

    internal fun readings(limits: JsonObject, capturedAt: Instant): List<UsageWindowReading> {
        val out = mutableListOf<UsageWindowReading>()
        for ((name, fallback) in listOf("primary" to UsageWindowKind.Session5h, "secondary" to UsageWindowKind.Weekly)) {
            val window = JsonLines.obj(limits[name]) ?: continue
            val percent = JsonLines.double(window["used_percent"])?.takeIf { it.isFinite() } ?: continue
            val kind = JsonLines.double(window["window_minutes"])?.let { kind(it) } ?: fallback
            val epoch = JsonLines.double(window["resets_at"])?.let { JsonLines.epochDate(it) }
            val secs = JsonLines.double(window["resets_in_seconds"])
            val resetsAt: Instant? = when {
                epoch != null -> epoch
                secs != null && secs.isFinite() && abs(secs) < 1e9 ->
                    capturedAt.plusMillis(Math.round(secs * 1000))
                else -> null
            }
            out += UsageWindowReading(
                kind,
                UsageSnapshot(fraction = maxOf(percent, 0.0) / 100, capturedAt = capturedAt, resetsAt = resetsAt),
            )
        }
        return out
    }

    /** Windows up to 6 h count as the session window; longer ones as weekly. */
    internal fun kind(minutes: Double): UsageWindowKind =
        if (minutes <= 360) UsageWindowKind.Session5h else UsageWindowKind.Weekly
}
