package app.ufuq.desktop.update

import app.ufuq.core.update.AvailableUpdate
import app.ufuq.core.update.GitHubReleases
import app.ufuq.core.update.ReleaseInfo
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.security.PublicKey

sealed interface UpdateState {
    /** No public key was baked in, so nothing is ever downloaded or run. */
    data object Disabled : UpdateState
    data object Idle : UpdateState
    data object Checking : UpdateState
    data class UpToDate(val version: String) : UpdateState
    data class Available(val update: AvailableUpdate) : UpdateState
    data class Downloading(val update: AvailableUpdate, val done: Long, val total: Long) : UpdateState
    data class Verifying(val update: AvailableUpdate) : UpdateState
    /** The installer is on disk and passed every check. */
    data class Ready(val update: AvailableUpdate, val file: File) : UpdateState
    data class Failed(val message: String, val update: AvailableUpdate? = null) : UpdateState
}

const val UPDATES_OFF_MESSAGE = "Updates are off in development builds"
const val LATEST_URL = "https://api.github.com/repos/hystericmoon/ufuq/releases/latest"
const val LIST_URL = "https://api.github.com/repos/hystericmoon/ufuq/releases?per_page=30"

/**
 * Check, download, verify. Nothing runs an installer except [install], and [install] verifies the
 * file again right before it starts it. Not thread-safe by itself: the shell calls it from one coroutine at a time.
 */
class UpdateManager(
    private val currentVersion: String,
    publicKeyBase64: String,
    private val http: UpdateHttp,
    private val tempDir: File,
    /** Starts the verified installer; returns false if it could not start. */
    private val launchInstaller: (File) -> Boolean,
    private val exitApp: () -> Unit,
) {
    private val key: PublicKey? = if (publicKeyBase64.isBlank()) null else SignatureVerifier.publicKeyFromRaw(publicKeyBase64)

    val enabled: Boolean get() = key != null

    private val _state = MutableStateFlow<UpdateState>(if (key == null) UpdateState.Disabled else UpdateState.Idle)
    val state: StateFlow<UpdateState> = _state.asStateFlow()

    /** Asks GitHub for a newer release. Safe to call again; ignored while a download is running. */
    fun check(includePreReleases: Boolean) {
        if (key == null) return
        when (_state.value) {
            is UpdateState.Checking, is UpdateState.Downloading, is UpdateState.Verifying, is UpdateState.Ready -> return
            else -> Unit
        }
        _state.value = UpdateState.Checking
        _state.value = try {
            val releases: List<ReleaseInfo> = if (includePreReleases) {
                GitHubReleases.parseList(http.getString(LIST_URL))
            } else {
                GitHubReleases.parseLatest(http.getString(LATEST_URL))?.let(::listOf)
            } ?: throw IllegalStateException("GitHub sent a reply this version cannot read")
            val update = GitHubReleases.pick(releases, currentVersion, includePreReleases) { "Ufuq-$it.msi" }
            if (update != null) UpdateState.Available(update) else UpdateState.UpToDate(currentVersion)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            UpdateState.Failed("Could not check for updates: ${e.message ?: e.javaClass.simpleName}")
        }
    }

    /** Downloads the installer and its signature to the temp folder and verifies both. */
    fun download() {
        val k = key ?: return
        val update = when (val s = _state.value) {
            is UpdateState.Available -> s.update
            is UpdateState.Failed -> s.update ?: return
            else -> return
        }
        val dir = File(tempDir, "Ufuq")
        val msi = File(dir, update.installer.name)
        val sigFile = File(dir, update.signature.name)
        try {
            dir.mkdirs()
            msi.delete()
            _state.value = UpdateState.Downloading(update, 0, update.installer.size)
            http.download(update.signature.url, sigFile) { _, _ -> }
            http.download(update.installer.url, msi) { done, total ->
                _state.value = UpdateState.Downloading(update, done, if (total > 0) total else update.installer.size)
            }
            _state.value = UpdateState.Verifying(update)
            val problem = verify(msi, sigFile, update, k)
            if (problem != null) {
                msi.delete()
                _state.value = UpdateState.Failed(problem, update)
            } else {
                _state.value = UpdateState.Ready(update, msi)
            }
        } catch (e: CancellationException) {
            msi.delete()
            throw e
        } catch (e: Exception) {
            msi.delete()
            _state.value = UpdateState.Failed("Download failed: ${e.message ?: e.javaClass.simpleName}", update)
        }
    }

    /** Null when the file is good, otherwise what is wrong with it. */
    private fun verify(msi: File, sigFile: File, update: AvailableUpdate, k: PublicKey): String? {
        if (!msi.isFile || msi.length() == 0L) return "The download is empty."
        val expected = update.installer.sha256
        if (expected != null && SignatureVerifier.sha256Hex(msi) != expected) return "The download does not match GitHub's checksum, so it was discarded."
        val sig = try { sigFile.readText() } catch (_: Exception) { return "The signature file is missing." }
        if (!SignatureVerifier.verifyFile(msi, sig, k)) return "The download is not signed by Ufuq, so it was discarded."
        return null
    }

    /** Verifies once more, then starts the installer and exits so it can replace the running app. */
    fun install() {
        val k = key ?: return
        val ready = _state.value as? UpdateState.Ready ?: return
        val sigFile = File(ready.file.parentFile, ready.update.signature.name)
        val problem = verify(ready.file, sigFile, ready.update, k)
        if (problem != null) {
            ready.file.delete()
            _state.value = UpdateState.Failed(problem, ready.update)
            return
        }
        if (launchInstaller(ready.file)) exitApp()
        else _state.value = UpdateState.Failed("Could not start the installer.", ready.update)
    }

    /** Back to a neutral state after the user closes a result. */
    fun dismiss() {
        when (_state.value) {
            is UpdateState.UpToDate, is UpdateState.Failed -> _state.value = if (key == null) UpdateState.Disabled else UpdateState.Idle
            else -> Unit
        }
    }
}

/** `msiexec /i <file> /passive /norestart`. Only called with a file that passed [UpdateManager]'s checks. */
fun launchMsiexec(file: File): Boolean = try {
    ProcessBuilder("msiexec", "/i", file.absolutePath, "/passive", "/norestart").inheritIO().start()
    true
} catch (_: Exception) {
    false
}
