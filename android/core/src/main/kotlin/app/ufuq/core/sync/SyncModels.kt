package app.ufuq.core.sync

import app.ufuq.core.UsageAccount
import app.ufuq.core.UsageProvider
import app.ufuq.core.UsageSnapshot
import app.ufuq.core.UsageWindowKind
import app.ufuq.core.UsageWindowReading
import java.time.Instant
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json

/** Wire constants of the Mac to phone sync; the spec is `docs/sync.md`. */
object SyncProtocol {
    const val VERSION = 1
    const val AAD = "ufuq-sync-v1"
    const val NONCE_LENGTH = 12
    const val TAG_LENGTH = 16
    const val KEY_LENGTH = 32
    const val MAX_CLOCK_SKEW_SECONDS = 5 * 60L
    const val AUTH_HEADER = "X-Ufuq-Auth"
    const val AUTH_PREFIX = "ufuq-sync-auth:"
    const val BONJOUR_TYPE = "_ufuq._tcp"
}

/** ISO 8601 UTC, whole seconds on the wire; any ISO instant is accepted on read. */
object InstantIso : KSerializer<Instant> {
    override val descriptor = PrimitiveSerialDescriptor("app.ufuq.core.sync.InstantIso", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: Instant) = encoder.encodeString(value.toString())
    override fun deserialize(decoder: Decoder): Instant = Instant.parse(decoder.decodeString())
}

internal val SyncJson = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    encodeDefaults = true
}

@Serializable
data class SyncReading(
    val accountId: String,
    val accountName: String,
    /** `claude`, `codex` or `antigravity`. */
    val provider: String,
    /** `session5h`, `weekly` or `modelGroup`. */
    val kind: String,
    val group: String? = null,
    val fraction: Double,
    @Serializable(with = InstantIso::class) val capturedAt: Instant,
    @Serializable(with = InstantIso::class) val resetsAt: Instant? = null,
    val isEstimated: Boolean = false,
) {
    /** The shared usage model, or null for a provider or kind this app version does not know. */
    fun toDomain(): Pair<UsageAccount, UsageWindowReading>? {
        val usageProvider = when (provider) {
            "claude" -> UsageProvider.CLAUDE
            "codex" -> UsageProvider.CODEX
            "antigravity" -> UsageProvider.ANTIGRAVITY
            else -> return null
        }
        val windowKind = when (kind) {
            "session5h" -> UsageWindowKind.Session5h
            "weekly" -> UsageWindowKind.Weekly
            "modelGroup" -> UsageWindowKind.ModelGroup(group ?: return null)
            else -> return null
        }
        return UsageAccount(accountId, usageProvider, accountName) to
            UsageWindowReading(windowKind, UsageSnapshot(fraction, capturedAt, resetsAt), isEstimated)
    }
}

enum class SyncAgentState { RUNNING, WAITING, DONE }

@Serializable
data class SyncAgent(
    val id: String,
    val title: String,
    /** `running`, `waiting` or `done`; see [agentState]. */
    val state: String,
    @Serializable(with = InstantIso::class) val updatedAt: Instant,
) {
    /** Null for a state a newer Mac app added. */
    val agentState: SyncAgentState?
        get() = SyncAgentState.entries.firstOrNull { it.name.equals(state, ignoreCase = true) }
}

@Serializable
data class SyncSnapshot(
    val version: Int,
    @Serializable(with = InstantIso::class) val generatedAt: Instant,
    val readings: List<SyncReading>,
    val agents: List<SyncAgent>,
)

@Serializable
data class SyncEvent(
    val seq: Long,
    val id: String,
    val moduleId: String,
    val title: String,
    val message: String,
    /** `normal` or `critical`. */
    val priority: String,
    @Serializable(with = InstantIso::class) val createdAt: Instant,
) {
    val isCritical: Boolean get() = priority == "critical"
}

@Serializable
data class SyncEventBatch(
    val version: Int,
    @Serializable(with = InstantIso::class) val generatedAt: Instant,
    /** The cursor: pass it as `since` next time. */
    val latestSeq: Long,
    val events: List<SyncEvent>,
)
