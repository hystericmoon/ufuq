package app.ufuq.core.sync

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.InetSocketAddress
import java.net.Socket

/**
 * HTTP/1.1 GET over a plain `java.net.Socket`, one request per connection (`Connection: close`).
 *
 * Why not `HttpURLConnection`: on Android that goes through the cleartext-traffic policy, which can
 * only allow or block whole domains, not "local addresses". The app therefore keeps cleartext
 * blocked in its network security config and sends the (app-level encrypted) sync traffic through
 * this socket, which that policy does not govern. Pure JVM so a unit test can run it against a
 * local `ServerSocket`.
 */
class SocketTransport(
    private val connectTimeoutMillis: Int = 5_000,
    private val maxBodyBytes: Int = 4 * 1024 * 1024,
) : SyncTransport {
    override fun get(url: String, headers: Map<String, String>, readTimeoutMillis: Int): TransportResponse {
        val target = Target.parse(url)
        Socket().use { socket ->
            socket.connect(InetSocketAddress(target.host, target.port), connectTimeoutMillis)
            socket.soTimeout = readTimeoutMillis
            socket.tcpNoDelay = true
            val request = buildString {
                append("GET ").append(target.path).append(" HTTP/1.1\r\n")
                append("Host: ").append(target.hostHeader).append("\r\n")
                append("Accept: */*\r\n")
                append("Connection: close\r\n")
                headers.forEach { (name, value) ->
                    require('\r' !in name + value && '\n' !in name + value) { "bad header" }
                    append(name).append(": ").append(value).append("\r\n")
                }
                append("\r\n")
            }
            socket.getOutputStream().apply {
                write(request.toByteArray(Charsets.US_ASCII))
                flush()
            }
            return readResponse(socket.getInputStream())
        }
    }

    private fun readResponse(input: InputStream): TransportResponse {
        val head = readHead(input)
        val lines = head.split("\r\n")
        val status = lines.first().split(' ').getOrNull(1)?.toIntOrNull() ?: throw IOException("Bad status line")
        val fields = lines.drop(1).mapNotNull { line ->
            val i = line.indexOf(':')
            if (i <= 0) null else line.substring(0, i).trim().lowercase() to line.substring(i + 1).trim()
        }.toMap()
        val body = when {
            fields["transfer-encoding"]?.contains("chunked", ignoreCase = true) == true -> readChunked(input)
            fields["content-length"] != null -> {
                val length = fields.getValue("content-length").toIntOrNull()?.takeIf { it in 0..maxBodyBytes }
                    ?: throw IOException("Bad content length")
                readExactly(input, length)
            }
            else -> readToEnd(input)
        }
        return TransportResponse(status, body)
    }

    /** Reads up to and including the blank line; returns the head without it. */
    private fun readHead(input: InputStream): String {
        val out = ByteArrayOutputStream()
        var matched = 0
        while (matched < 4) {
            val b = input.read()
            if (b < 0) throw IOException("Connection closed before the response head ended")
            if (out.size() >= MAX_HEAD_BYTES) throw IOException("Response head too large")
            out.write(b)
            matched = if (b == TERMINATOR[matched]) matched + 1 else if (b == '\r'.code) 1 else 0
        }
        return out.toString(Charsets.ISO_8859_1.name()).dropLast(4)
    }

    private fun readExactly(input: InputStream, length: Int): ByteArray {
        val buffer = ByteArray(length)
        var read = 0
        while (read < length) {
            val n = input.read(buffer, read, length - read)
            if (n < 0) throw IOException("Connection closed mid-body")
            read += n
        }
        return buffer
    }

    private fun readToEnd(input: InputStream): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(4096)
        while (true) {
            val n = input.read(buffer)
            if (n < 0) break
            if (out.size() + n > maxBodyBytes) throw IOException("Body too large")
            out.write(buffer, 0, n)
        }
        return out.toByteArray()
    }

    private fun readChunked(input: InputStream): ByteArray {
        val out = ByteArrayOutputStream()
        while (true) {
            val size = readLine(input).substringBefore(';').trim().toIntOrNull(16) ?: throw IOException("Bad chunk size")
            if (size == 0) return out.toByteArray()
            if (out.size() + size > maxBodyBytes) throw IOException("Body too large")
            out.write(readExactly(input, size))
            readLine(input)
        }
    }

    private fun readLine(input: InputStream): String {
        val out = ByteArrayOutputStream()
        while (true) {
            val b = input.read()
            if (b < 0) throw IOException("Connection closed mid-chunk")
            if (b == '\n'.code) return out.toString(Charsets.ISO_8859_1.name()).trimEnd('\r')
            out.write(b)
        }
    }

    private class Target(val host: String, val port: Int, val path: String) {
        val hostHeader: String get() = if (host.contains(':')) "[$host]:$port" else "$host:$port"

        companion object {
            fun parse(url: String): Target {
                if (!url.startsWith("http://")) throw IOException("Only http:// URLs are supported")
                val rest = url.removePrefix("http://")
                val slash = rest.indexOf('/')
                val authority = if (slash < 0) rest else rest.substring(0, slash)
                val path = if (slash < 0) "/" else rest.substring(slash)
                val host: String
                val portText: String?
                if (authority.startsWith("[")) {
                    val end = authority.indexOf(']')
                    if (end < 0) throw IOException("Bad host")
                    host = authority.substring(1, end)
                    portText = authority.substring(end + 1).removePrefix(":").ifEmpty { null }
                } else {
                    host = authority.substringBefore(':')
                    portText = authority.substringAfter(':', "").ifEmpty { null }
                }
                val port = if (portText == null) 80 else portText.toIntOrNull() ?: throw IOException("Bad port")
                if (host.isEmpty() || port !in 1..65535) throw IOException("Bad address")
                return Target(host, port, path)
            }
        }
    }

    private companion object {
        const val MAX_HEAD_BYTES = 16 * 1024
        val TERMINATOR = intArrayOf('\r'.code, '\n'.code, '\r'.code, '\n'.code)
    }
}
