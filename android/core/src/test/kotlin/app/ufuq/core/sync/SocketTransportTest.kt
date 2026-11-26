package app.ufuq.core.sync

import app.ufuq.core.UsageResult
import java.io.IOException
import java.net.ServerSocket
import java.net.Socket
import java.time.Clock
import java.time.ZoneOffset
import java.util.Base64
import kotlin.concurrent.thread
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

/** The raw-socket transport against a local `ServerSocket`, with the real sealer and the fixture snapshot. */
class SocketTransportTest {
    private val sealer = AesGcmSealer(SyncFixtures.KEY)
    private val clock = Clock.fixed(SyncFixtures.GENERATED, ZoneOffset.UTC)
    private val pairing = PairingPayload.parse(SyncFixtures.text("pairing.json"))
    private val snapshotJson = SyncFixtures.text("snapshot.json").trim()

    /** Serves one connection: records the request head, then calls [respond] with the socket. */
    private fun serve(respond: (Socket, String) -> Unit): Pair<ServerSocket, () -> String> {
        val server = ServerSocket(0, 1, java.net.InetAddress.getLoopbackAddress())
        var seen = ""
        thread(isDaemon = true) {
            server.accept().use { socket ->
                val head = StringBuilder()
                val input = socket.getInputStream()
                while (!head.endsWith("\r\n\r\n")) head.append(input.read().toChar())
                seen = head.toString()
                respond(socket, seen)
            }
        }
        return server to { seen }
    }

    private fun Socket.reply(status: String, body: ByteArray, extra: String = "Content-Length: ${body.size}\r\n") {
        getOutputStream().apply {
            write("HTTP/1.1 $status\r\n${extra}Connection: close\r\n\r\n".toByteArray())
            write(body)
            flush()
        }
    }

    private fun client(server: ServerSocket) =
        HttpSyncClient(pairing.copy(port = server.localPort), sealer, "127.0.0.1", clock, SocketTransport())

    @Test fun endToEndSnapshotDecrypts(): Unit = runBlocking {
        val (server, seen) = serve { socket, head ->
            // Verify the auth token the way the Mac does.
            val token = head.lines().first { it.startsWith(SyncProtocol.AUTH_HEADER) }.substringAfter(": ").trim()
            val plain = sealer.open(Base64.getUrlDecoder().decode(token)).toString(Charsets.UTF_8)
            assertEquals("ufuq-sync-auth:${SyncFixtures.GENERATED.epochSecond}", plain)
            socket.reply("200 OK", sealer.seal(snapshotJson.toByteArray()))
        }
        server.use {
            val snapshot = assertIs<UsageResult.Available<SyncSnapshot>>(client(server).snapshot()).value
            assertEquals(3, snapshot.readings.size)
            assertEquals("Refactor sync", snapshot.agents.first().title)
            assertTrue(seen().startsWith("GET /v1/snapshot HTTP/1.1\r\n"))
            assertTrue(seen().contains("Connection: close"))
        }
    }

    @Test fun eventsPathCarriesCursor(): Unit = runBlocking {
        val batch = """{"events":[],"generatedAt":"2026-11-28T09:00:00Z","latestSeq":7,"version":1}"""
        val (server, seen) = serve { socket, _ -> socket.reply("200 OK", sealer.seal(batch.toByteArray())) }
        server.use {
            val result = assertIs<UsageResult.Available<SyncEventBatch>>(client(server).events(7))
            assertEquals(7, result.value.latestSeq)
            assertTrue(seen().startsWith("GET /v1/events?since=7 HTTP/1.1"))
        }
    }

    @Test fun unauthorizedWithEmptyBodyIsPairAgain(): Unit = runBlocking {
        val (server, _) = serve { socket, _ -> socket.reply("401 Unauthorized", ByteArray(0)) }
        server.use {
            assertEquals("Pair again", assertIs<UsageResult.Unavailable>(client(server).snapshot()).reason)
        }
    }

    @Test fun bodyWithoutContentLengthReadsToClose() {
        val (server, _) = serve { socket, _ -> socket.reply("200 OK", "hello".toByteArray(), extra = "") }
        server.use {
            val r = SocketTransport().get("http://127.0.0.1:${server.localPort}/x", emptyMap(), 2_000)
            assertEquals("hello", r.body.toString(Charsets.UTF_8))
        }
    }

    @Test fun chunkedBodyIsDecoded() {
        val (server, _) = serve { socket, _ ->
            socket.getOutputStream().apply {
                write("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n".toByteArray())
                flush()
            }
        }
        server.use {
            val r = SocketTransport().get("http://127.0.0.1:${server.localPort}/x", emptyMap(), 2_000)
            assertEquals("hello world", r.body.toString(Charsets.UTF_8))
        }
    }

    @Test fun refusedConnectionAndTimeoutAreIoErrors(): Unit = runBlocking {
        val closedPort = ServerSocket(0).use { it.localPort }
        assertFailsWith<IOException> { SocketTransport(connectTimeoutMillis = 500).get("http://127.0.0.1:$closedPort/", emptyMap(), 500) }
        val (silent, _) = serve { _, _ -> Thread.sleep(1_500) }
        silent.use {
            assertFailsWith<IOException> { SocketTransport().get("http://127.0.0.1:${silent.localPort}/", emptyMap(), 300) }
        }
        val down = HttpSyncClient(pairing.copy(port = closedPort), sealer, "127.0.0.1", clock, SocketTransport(500))
        assertEquals("Mac not reachable", assertIs<UsageResult.Unavailable>(down.snapshot()).reason)
    }

    @Test fun rejectsNonHttpUrls() {
        assertFailsWith<IOException> { SocketTransport().get("https://example.com/", emptyMap(), 100) }
    }
}
