package app.ufuq.core

import kotlin.math.floor

enum class UsageProvider { CLAUDE, CODEX, ANTIGRAVITY }

/** One tracked account. For Claude on the Mac, [configDir] is the account's `CLAUDE_CONFIG_DIR`. */
data class UsageAccount(
    val id: String,
    val provider: UsageProvider,
    val displayName: String,
    val configDir: String? = null,
)

sealed interface UsageWindowKind {
    data object Session5h : UsageWindowKind
    data object Weekly : UsageWindowKind

    /** Antigravity-style quota per model group. */
    data class ModelGroup(val name: String) : UsageWindowKind
}

/**
 * A limit window reading for one account. [isEstimated] marks numbers computed locally instead of
 * read from the provider; the UI labels them "estimated".
 */
data class UsageWindowReading(
    val kind: UsageWindowKind,
    val snapshot: UsageSnapshot,
    val isEstimated: Boolean = false,
)

/** A parse or fetch outcome. A broken source is [Unavailable], never a crash. */
sealed interface UsageResult<out T> {
    data class Available<out T>(val value: T) : UsageResult<T>
    data class Unavailable(val reason: String) : UsageResult<Nothing>

    val valueOrNull: T? get() = (this as? Available)?.value

    val status: ModuleStatus
        get() = when (this) {
            is Available -> ModuleStatus.Ok
            is Unavailable -> ModuleStatus.Unavailable(reason)
        }
}

object UsageSummary {
    /** The reading with the highest fraction, or null when there are none (or none finite). */
    fun worst(readings: List<UsageWindowReading>): UsageWindowReading? =
        readings.filter { it.snapshot.fraction.isFinite() }.maxByOrNull { it.snapshot.fraction }

    /** Worst fraction (0..1, clamped) for the collapsed ring text; null when there are no readings. */
    fun worstFraction(readings: List<UsageWindowReading>): Double? =
        worst(readings)?.snapshot?.fraction?.coerceIn(0.0, 1.0)

    /** Whole-number percent for the collapsed text, e.g. 0.874 -> 87. */
    fun worstPercent(readings: List<UsageWindowReading>): Int? =
        worstFraction(readings)?.let { floor(it * 100).toInt() }
}
