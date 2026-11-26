package app.ufuq.android.update

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.core.content.edit
import app.ufuq.android.BuildConfig
import app.ufuq.core.update.AvailableDownload
import app.ufuq.core.update.GitHubReleases
import app.ufuq.core.update.Versions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/** What [UpdateController] needs; [UpdateRepository] on a device, a fake in tests. */
interface UpdateSource {
    val enabled: Boolean
    var autoCheck: Boolean
    var betaChannel: Boolean
    val lastCheckMillis: Long
    fun isAutoCheckDue(nowMillis: Long): Boolean = enabled && autoCheck && nowMillis - lastCheckMillis >= AUTO_INTERVAL_MS

    /** The newer release, or null when up to date. Throws [IOException] when offline. */
    suspend fun check(nowMillis: Long): AvailableDownload?

    /** Downloads and verifies the APK, reporting progress 0..1 (or -1 when the size is unknown). */
    suspend fun download(update: AvailableDownload, onProgress: (Float) -> Unit): File

    companion object {
        /** "Once a day", with slack so a check at 08:05 is not skipped because yesterday's ran at 08:10. */
        const val AUTO_INTERVAL_MS = 20L * 60 * 60 * 1000
    }
}

/**
 * Sideload updater, ported from Adwam (hystericmoon/muslimdaily `update/`), without Hilt.
 * Checks GitHub Releases for `ufuq-<version>.apk`, downloads it to the cache, checks GitHub's SHA-256
 * digest and the package name, then hands it to the system installer, which refuses an APK signed with
 * a different key. Only release builds have [BuildConfig.SELF_UPDATE].
 */
class UpdateRepository(private val context: Context) : UpdateSource {
    private val prefs = context.getSharedPreferences("updates", Context.MODE_PRIVATE)

    override val enabled: Boolean get() = BuildConfig.SELF_UPDATE && BuildConfig.UPDATE_REPO.isNotBlank()

    override var autoCheck: Boolean
        get() = prefs.getBoolean(KEY_AUTO, true)
        set(value) = prefs.edit { putBoolean(KEY_AUTO, value) }

    /** Beta: pre-releases too. Off unless this build is itself a pre-release. */
    override var betaChannel: Boolean
        get() = prefs.getBoolean(KEY_BETA, Versions.isPreRelease(BuildConfig.VERSION_NAME))
        set(value) = prefs.edit { putBoolean(KEY_BETA, value) }

    override var lastCheckMillis: Long
        get() = prefs.getLong(KEY_LAST, 0L)
        private set(value) = prefs.edit { putLong(KEY_LAST, value) }

    override suspend fun check(nowMillis: Long): AvailableDownload? = withContext(Dispatchers.IO) {
        val beta = betaChannel
        val conn = open("https://api.github.com/repos/${BuildConfig.UPDATE_REPO}/" + if (beta) "releases?per_page=$BETA_PAGE" else "releases/latest")
        conn.setRequestProperty("Accept", "application/vnd.github+json")
        try {
            when (conn.responseCode) {
                HttpURLConnection.HTTP_OK -> {
                    val body = conn.inputStream.bufferedReader().use { it.readText() }
                    lastCheckMillis = nowMillis
                    val releases = if (beta) GitHubReleases.parseList(body) else GitHubReleases.parseLatest(body)?.let(::listOf)
                    GitHubReleases.pickAsset(releases.orEmpty(), BuildConfig.VERSION_NAME, beta, ::apkName)
                }
                // No release published yet.
                HttpURLConnection.HTTP_NOT_FOUND -> null.also { lastCheckMillis = nowMillis }
                else -> throw IOException("HTTP ${conn.responseCode}")
            }
        } finally {
            conn.disconnect()
        }
    }

    override suspend fun download(update: AvailableDownload, onProgress: (Float) -> Unit): File = withContext(Dispatchers.IO) {
        val dir = File(context.cacheDir, "updates").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val target = File(dir, apkName(update.version))
        val partial = File(dir, target.name + ".part")
        val conn = open(update.asset.url)
        try {
            if (conn.responseCode != HttpURLConnection.HTTP_OK) throw IOException("HTTP ${conn.responseCode}")
            val total = conn.contentLengthLong.takeIf { it > 0 } ?: update.asset.size
            val digest = MessageDigest.getInstance("SHA-256")
            conn.inputStream.use { input ->
                partial.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var read = 0L
                    while (true) {
                        currentCoroutineContext().ensureActive()
                        val n = input.read(buffer)
                        if (n < 0) break
                        output.write(buffer, 0, n)
                        digest.update(buffer, 0, n)
                        read += n
                        onProgress(if (total > 0) (read.toFloat() / total).coerceIn(0f, 1f) else -1f)
                    }
                }
            }
            if (total > 0 && partial.length() != total) throw IOException("Incomplete download")
            if (!digestMatches(update.asset.sha256, digest.digest())) throw IOException("SHA-256 does not match GitHub's digest")
            val pkg = context.packageManager.getPackageArchiveInfo(partial.path, 0)?.packageName
            if (pkg != context.packageName) throw IOException("Not an Ufuq APK ($pkg)")
            if (!partial.renameTo(target)) throw IOException("Could not save update")
            target
        } catch (e: Exception) {
            partial.delete()
            throw e
        } finally {
            conn.disconnect()
        }
    }

    fun canInstall(): Boolean = context.packageManager.canRequestPackageInstalls()

    /** The "install unknown apps" setting for Ufuq. */
    fun installPermissionIntent(): Intent =
        Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /** The system installer; it rejects an APK signed with a different key than the installed app. */
    fun installIntent(apk: File): Intent {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", apk)
        return Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    private fun open(url: String) = (URL(url).openConnection() as HttpURLConnection).apply {
        connectTimeout = TIMEOUT_MS
        readTimeout = TIMEOUT_MS
        instanceFollowRedirects = true
        setRequestProperty("User-Agent", "Ufuq-Android/${BuildConfig.VERSION_NAME}")
    }

    companion object {
        /** The asset name release-android.yml uploads. */
        fun apkName(version: String) = "ufuq-$version.apk"

        /** True when GitHub gave no digest (older releases) or it equals [actual]. */
        fun digestMatches(expectedHex: String?, actual: ByteArray): Boolean =
            expectedHex == null || expectedHex.equals(actual.joinToString("") { "%02x".format(it) }, ignoreCase = true)

        private const val KEY_AUTO = "auto_check"
        private const val KEY_BETA = "beta_channel"
        private const val KEY_LAST = "last_check"
        private const val BETA_PAGE = 15
        private const val TIMEOUT_MS = 15_000
    }
}
