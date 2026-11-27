package app.ufuq.core.sync

import app.ufuq.core.UsageResult
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.util.Base64
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerializationException

/** Reads the Mac's usage and agent status. A broken link is [UsageResult.Unavailable], never a throw. */
interface SyncClient {
    suspend fun snapshot(): UsageResult<SyncSnapshot>

    /** Long-polls (up to 30 s) for events after [since]; an empty batch means nothing happened. */
    suspend fun events(since: Long): UsageResult<SyncEventBatch>
}

class TransportResponse(val status: Int, val body: ByteArray)

/** One blocking GET. Throws [IOException] when the Mac cannot be reached. */
fun interface SyncTransport {
    fun get(url: String, headers: Map<String, String>, readTimeoutMillis: Int): TransportResponse
}

/** The default transport, on `java.net.HttpURLConnection` (no third-party HTTP library). */
class HttpUrlTransport(private val connectTimeoutMillis: Int = 5_000) : SyncTransport {
    override fun get(url: String, headers: Map<String, String>, readTimeoutMillis: Int): TransportResponse {
        val connection = URI(url).toURL().openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "GET"
            connection.connectTimeout = connectTimeoutMillis
            connection.readTimeout = readTimeoutMillis
            connection.useCaches = false
            headers.forEach { (name, value) -> connection.setRequestProperty(name, value) }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            return TransportResponse(status, stream?.use { it.readBytes() } ?: ByteArray(0))
        } finally {
            connection.disconnect()
        }
    }
}

class HttpSyncClient(
    private val pairing: PairingPayload,
    private val sealer: SyncSealer,
    /** The address NSD resolved; falls back to the QR's host hint. */
    private val host: String = pairing.host,
    private val clock: Clock = Clock.systemUTC(),
    private val transport: SyncTransport = HttpUrlTransport(),
) : SyncClient {
    override suspend fun snapshot(): UsageResult<SyncSnapshot> =
        fetch("/v1/snapshot", SNAPSHOT_TIMEOUT_MS) { text ->
            val snapshot = SyncJson.decodeFromString(SyncSnapshot.serializer(), text)
            Triple(snapshot, snapshot.version, snapshot.generatedAt)
        }

    override suspend fun events(since: Long): UsageResult<SyncEventBatch> =
        fetch("/v1/events?since=$since", EVENTS_TIMEOUT_MS) { text ->
            val batch = SyncJson.decodeFromString(SyncEventBatch.serializer(), text)
            Triple(batch, batch.version, batch.generatedAt)
        }

    private suspend fun <T> fetch(
        path: String,
        timeoutMillis: Int,
        decode: (String) -> Triple<T, Int, Instant>,
    ): UsageResult<T> = withContext(Dispatchers.IO) {
        val response = try {
            val token = Base64.getUrlEncoder().withoutPadding().encodeToString(
                sealer.seal("${SyncProtocol.AUTH_PREFIX}${clock.instant().epochSecond}".toByteArray(Charsets.UTF_8)),
            )
            transport.get("http://${hostForUrl(host)}:${pairing.port}$path", mapOf(SyncProtocol.AUTH_HEADER to token), timeoutMillis)
        } catch (e: CancellationException) {
            throw e
        } catch (e: IOException) {
            return@withContext UsageResult.Unavailable("Mac not reachable")
        }
        when {
            response.status == 401 -> UsageResult.Unavailable(PAIR_AGAIN)
            response.status != 200 -> UsageResult.Unavailable("Mac replied with HTTP ${response.status}")
            else -> interpret(response.body, decode)
        }
    }

    private fun <T> interpret(body: ByteArray, decode: (String) -> Triple<T, Int, Instant>): UsageResult<T> {
        val plain = try {
            sealer.open(body)
        } catch (e: SealException) {
            return UsageResult.Unavailable(PAIR_AGAIN)
        }
        val (value, version, generatedAt) = try {
            decode(plain.toString(Charsets.UTF_8))
        } catch (e: SerializationException) {
            return UsageResult.Unavailable("Unexpected reply from the Mac")
        } catch (e: IllegalArgumentException) {
            return UsageResult.Unavailable("Unexpected reply from the Mac")
        }
        if (version > SyncProtocol.VERSION) return UsageResult.Unavailable("Update Ufuq on this phone")
        val skew = Duration.between(generatedAt, clock.instant()).abs()
        if (skew.seconds > SyncProtocol.MAX_CLOCK_SKEW_SECONDS) {
            return UsageResult.Unavailable("Clocks differ by more than 5 minutes")
        }
        return UsageResult.Available(value)
    }

    private fun hostForUrl(host: String) = if (host.contains(':') && !host.startsWith("[")) "[$host]" else host

    companion object {
        const val PAIR_AGAIN = "Pair again"
        private const val SNAPSHOT_TIMEOUT_MS = 10_000
        private const val EVENTS_TIMEOUT_MS = 35_000
    }
}
