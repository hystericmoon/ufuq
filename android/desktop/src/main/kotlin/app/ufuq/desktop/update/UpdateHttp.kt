package app.ufuq.desktop.update

import java.io.File
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration

/** The network side of the updater, behind an interface so tests can serve canned releases and files. */
interface UpdateHttp {
    fun getString(url: String): String

    /** Writes [url] to [dest], reporting (bytes so far, total or -1). Throws on any failure. */
    fun download(url: String, dest: File, onProgress: (Long, Long) -> Unit)
}

class JdkUpdateHttp : UpdateHttp {
    private val client = HttpClient.newBuilder()
        .followRedirects(HttpClient.Redirect.NORMAL)
        .connectTimeout(Duration.ofSeconds(15))
        .build()

    private fun request(url: String, accept: String): HttpRequest {
        require(url.startsWith("https://")) { "Only https downloads are allowed" }
        return HttpRequest.newBuilder(URI.create(url))
            .timeout(Duration.ofMinutes(10))
            .header("Accept", accept)
            .header("User-Agent", "Ufuq-Windows-Updater")
            .GET()
            .build()
    }

    override fun getString(url: String): String {
        val r = client.send(request(url, "application/vnd.github+json"), HttpResponse.BodyHandlers.ofString())
        check(r.statusCode() == 200) { "GitHub answered HTTP ${r.statusCode()}" }
        return r.body()
    }

    override fun download(url: String, dest: File, onProgress: (Long, Long) -> Unit) {
        val r = client.send(request(url, "application/octet-stream"), HttpResponse.BodyHandlers.ofInputStream())
        check(r.statusCode() == 200) { "Download failed: HTTP ${r.statusCode()}" }
        val total = r.headers().firstValueAsLong("Content-Length").orElse(-1)
        dest.parentFile?.mkdirs()
        r.body().use { input ->
            dest.outputStream().use { out ->
                val buf = ByteArray(64 * 1024)
                var done = 0L
                var lastReport = 0L
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    out.write(buf, 0, n)
                    done += n
                    if (done - lastReport >= 256 * 1024) { lastReport = done; onProgress(done, total) }
                }
                onProgress(done, total)
            }
        }
    }
}
