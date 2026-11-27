package app.ufuq.core.sync

import app.ufuq.core.UsageResult
import com.sun.net.httpserver.HttpServer
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.time.Clock
import java.time.ZoneOffset
import java.util.Base64
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

class HttpSyncClientTest {
    private val sealer = AesGcmSealer(SyncFixtures.KEY)
    private val clock = Clock.fixed(SyncFixtures.GENERATED, ZoneOffset.UTC)
    private val pairing = PairingPayload.parse(SyncFixtures.text("pairing.json"))
    private val snapshotJson = SyncFixtures.text("snapshot.json").trim()

    private fun client(host: String = "10.0.0.5", transport: SyncTransport) = HttpSyncClient(pairing, sealer, host, clock, transport)

    private fun reply(status: Int = 200, plain: String? = null, with: SyncSealer = sealer) =
        SyncTransport { _, _, _ -> TransportResponse(status, plain?.let { with.seal(it.toByteArray()) } ?: ByteArray(0)) }

    private fun unavailable(result: UsageResult<*>): String = assertIs<UsageResult.Unavailable>(result).reason

    @Test fun fetchesSnapshotWithValidAuthHeader(): Unit = runBlocking {
        var seenUrl = ""
        var seenAuth = ""
        val result = client { url, headers, _ ->
            seenUrl = url
            seenAuth = headers.getValue(SyncProtocol.AUTH_HEADER)
            TransportResponse(200, sealer.seal(snapshotJson.toByteArray()))
        }.snapshot()
        assertEquals("http://10.0.0.5:49152/v1/snapshot", seenUrl)
        val plain = sealer.open(Base64.getUrlDecoder().decode(seenAuth)).toString(Charsets.UTF_8)
        assertEquals("ufuq-sync-auth:${SyncFixtures.GENERATED.epochSecond}", plain)
        assertEquals(3, assertIs<UsageResult.Available<SyncSnapshot>>(result).value.readings.size)
    }

    @Test fun unauthorizedMeansPairAgain(): Unit = runBlocking {
        assertEquals("Pair again", unavailable(client(transport = reply(401)).snapshot()))
        assertEquals("Pair again", unavailable(client(transport = reply(401)).events(0)))
    }

    @Test fun wrongKeyReplyMeansPairAgain(): Unit = runBlocking {
        val other = AesGcmSealer(ByteArray(32) { 7 })
        assertEquals("Pair again", unavailable(client(transport = reply(plain = snapshotJson, with = other)).snapshot()))
    }

    @Test fun rejectsReplayedOrSkewedPayloads(): Unit = runBlocking {
        val old = snapshotJson.replace("2026-11-28T09:00:00Z", "2026-11-28T08:50:00Z")
        assertTrue(unavailable(client(transport = reply(plain = old)).snapshot()).contains("Clocks differ"))
        val nearly = snapshotJson.replace("2026-11-28T09:00:00Z", "2026-11-28T08:55:01Z")
        assertIs<UsageResult.Available<SyncSnapshot>>(client(transport = reply(plain = nearly)).snapshot())
    }

    @Test fun networkAndServerErrorsAreUnavailable(): Unit = runBlocking {
        val down = SyncTransport { _, _, _ -> throw IOException("no route") }
        assertEquals("Mac not reachable", unavailable(client(transport = down).snapshot()))
        assertTrue(unavailable(client(transport = reply(500)).snapshot()).contains("500"))
        assertEquals("Unexpected reply from the Mac", unavailable(client(transport = reply(plain = "{nope")).snapshot()))
        val future = snapshotJson.replace("\"version\":1", "\"version\":2")
        assertEquals("Update Ufuq on this phone", unavailable(client(transport = reply(plain = future)).snapshot()))
    }

    @Test fun eventsUseSinceCursorAndIpv6Brackets(): Unit = runBlocking {
        var url = ""
        val body = """{"version":1,"generatedAt":"2026-11-28T09:00:00Z","latestSeq":4,"events":[]}"""
        val result = client(host = "fe80::1") { u, _, timeout ->
            url = u
            assertEquals(35_000, timeout)
            TransportResponse(200, sealer.seal(body.toByteArray()))
        }.events(3)
        assertEquals("http://[fe80::1]:49152/v1/events?since=3", url)
        assertEquals(4L, assertIs<UsageResult.Available<SyncEventBatch>>(result).value.latestSeq)
    }

    @Test fun httpUrlTransportTalksToARealServer(): Unit = runBlocking {
        val server = HttpServer.create(InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0)
        server.createContext("/v1/snapshot") { exchange ->
            val token = exchange.requestHeaders.getFirst(SyncProtocol.AUTH_HEADER)
            if (token == null) {
                exchange.sendResponseHeaders(401, -1)
            } else {
                val bytes = sealer.seal(snapshotJson.toByteArray())
                exchange.sendResponseHeaders(200, bytes.size.toLong())
                exchange.responseBody.use { it.write(bytes) }
            }
            exchange.close()
        }
        server.start()
        try {
            val real = pairing.copy(port = server.address.port)
            val result = HttpSyncClient(real, sealer, "127.0.0.1", clock).snapshot()
            assertEquals(2, assertIs<UsageResult.Available<SyncSnapshot>>(result).value.agents.size)
            val closed = HttpSyncClient(real.copy(port = 1), sealer, "127.0.0.1", clock).snapshot()
            assertEquals("Mac not reachable", unavailable(closed))
        } finally {
            server.stop(0)
        }
    }
}
