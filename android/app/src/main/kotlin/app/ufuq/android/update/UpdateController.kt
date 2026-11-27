package app.ufuq.android.update

import app.ufuq.core.update.AvailableDownload
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.File

sealed interface UpdateStatus {
    data object Idle : UpdateStatus
    data object Checking : UpdateStatus
    data object UpToDate : UpdateStatus
    data class Available(val update: AvailableDownload) : UpdateStatus
    /** [progress] is 0..1, or negative when the size is unknown. */
    data class Downloading(val update: AvailableDownload, val progress: Float) : UpdateStatus
    data class Ready(val update: AvailableDownload, val apk: File) : UpdateStatus
    data class Failed(val update: AvailableDownload?) : UpdateStatus
}

data class UpdateUiState(
    val enabled: Boolean = false,
    val autoCheck: Boolean = true,
    val betaChannel: Boolean = false,
    val lastCheckMillis: Long = 0L,
    val status: UpdateStatus = UpdateStatus.Idle,
    /** Show the "update available" dialog (found by the daily check). */
    val prompt: Boolean = false,
)

/** Process-wide updater state (Adwam's UpdateViewModel without Hilt), shared by the prompt and the Updates screen. */
class UpdateController(
    private val source: UpdateSource,
    private val scope: CoroutineScope,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val _state = MutableStateFlow(
        UpdateUiState(source.enabled, source.autoCheck, source.betaChannel, source.lastCheckMillis),
    )
    val state: StateFlow<UpdateUiState> = _state.asStateFlow()
    private var job: Job? = null

    /** Silent daily check on start; surfaces only when an update exists. */
    fun autoCheck() {
        val now = clock()
        if (!source.isAutoCheckDue(now) || job?.isActive == true) return
        job = scope.launch {
            val found = runCatching { source.check(now) }.getOrNull()
            _state.update {
                it.copy(
                    lastCheckMillis = source.lastCheckMillis,
                    status = found?.let(UpdateStatus::Available) ?: it.status,
                    prompt = found != null,
                )
            }
        }
    }

    fun checkNow() {
        if (!source.enabled || job?.isActive == true) return
        _state.update { it.copy(status = UpdateStatus.Checking) }
        job = scope.launch {
            val result = runCatching { source.check(clock()) }
            _state.update {
                it.copy(
                    lastCheckMillis = source.lastCheckMillis,
                    status = result.fold(
                        onSuccess = { found -> found?.let(UpdateStatus::Available) ?: UpdateStatus.UpToDate },
                        onFailure = { UpdateStatus.Failed(null) },
                    ),
                )
            }
        }
    }

    fun download() {
        val update = when (val s = _state.value.status) {
            is UpdateStatus.Available -> s.update
            is UpdateStatus.Failed -> s.update ?: return
            else -> return
        }
        if (job?.isActive == true) return
        _state.update { it.copy(status = UpdateStatus.Downloading(update, 0f)) }
        job = scope.launch {
            val result = runCatching {
                source.download(update) { p -> _state.update { s -> s.copy(status = UpdateStatus.Downloading(update, p)) } }
            }
            _state.update {
                it.copy(status = result.fold(onSuccess = { apk -> UpdateStatus.Ready(update, apk) }, onFailure = { UpdateStatus.Failed(update) }))
            }
        }
    }

    /** The downloaded APK, when one is ready to install. */
    fun readyApk(): File? = (_state.value.status as? UpdateStatus.Ready)?.apk

    fun dismissPrompt() = _state.update { it.copy(prompt = false) }

    fun setAutoCheck(enabled: Boolean) {
        source.autoCheck = enabled
        _state.update { it.copy(autoCheck = enabled) }
    }

    /** Switching channel checks again at once, so a tester sees the beta straight away. */
    fun setBetaChannel(enabled: Boolean) {
        source.betaChannel = enabled
        _state.update { it.copy(betaChannel = enabled) }
        checkNow()
    }
}
