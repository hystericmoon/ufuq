package app.ufuq.android.sync

import app.ufuq.core.PeekEvent
import app.ufuq.core.UsageResult
import app.ufuq.core.sync.AesGcmSealer
import app.ufuq.core.sync.HttpSyncClient
import app.ufuq.core.sync.PairingPayload
import app.ufuq.core.sync.SocketTransport
import app.ufuq.core.sync.SyncClient
import java.time.Clock
import java.time.Duration
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.launch

/**
 * Keeps the Mac link alive while the app or the island is visible: a snapshot every 30 s and a
 * long-poll for events, with backoff on failure. Unpaired means no polling at all. Callers bracket
 * their visibility with [acquire] and [release]; the loop runs while at least one holder remains.
 */
class SyncController(
    private val source: PairingSource,
    private val scope: CoroutineScope,
    private val strings: SyncStrings,
    private val locator: MacLocator = MacLocator { it },
    /** This phone's name, sent to the Mac so it can show which phone is paired. */
    clientName: String? = null,
    private val clientFactory: (PairingPayload) -> SyncClient = { p ->
        HttpSyncClient(p, AesGcmSealer(p.keyBytes), p.host, transport = SocketTransport(), clientName = clientName)
    },
    private val clock: Clock = Clock.systemUTC(),
    private val online: () -> Boolean = { true },
    private val snapshotInterval: Duration = Duration.ofSeconds(30),
) {
    private val _state = MutableStateFlow<SyncState>(SyncState.Unpaired)
    val state: StateFlow<SyncState> = _state

    private val _peeks = MutableSharedFlow<PeekEvent>(extraBufferCapacity = 16, onBufferOverflow = BufferOverflow.DROP_OLDEST)

    /** Peeks from the Mac's event log and from agent state changes. */
    val peeks: SharedFlow<PeekEvent> = _peeks

    private val nudge = MutableSharedFlow<Unit>(extraBufferCapacity = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)

    private var holders = 0
    private var job: Job? = null
    private var cursorDevice: String? = null
    private var cursor = 0L

    fun acquire() {
        holders++
        if (job == null) job = scope.launch { run() }
    }

    /** Fetches a snapshot now instead of waiting out the interval (the page's refresh button). */
    fun refreshNow() {
        nudge.tryEmit(Unit)
    }

    fun release() {
        holders = (holders - 1).coerceAtLeast(0)
        if (holders == 0) {
            job?.cancel()
            job = null
        }
    }

    private suspend fun run() {
        source.pairing.collectLatest { pairing ->
            if (pairing == null) {
                _state.value = SyncState.Unpaired
                return@collectLatest
            }
            if (cursorDevice != pairing.deviceId) {
                cursorDevice = pairing.deviceId
                cursor = 0
            }
            if (_state.value !is SyncState.Live && _state.value !is SyncState.Unreachable) {
                _state.value = SyncState.Connecting(_state.value.dataOrNull)
            }
            link(pairing)
        }
    }

    private suspend fun link(pairing: PairingPayload) = coroutineScope {
        var client = clientFactory(locate(pairing))
        var previousAgents: List<app.ufuq.core.sync.SyncAgent>? = null
        var relocate = false
        var halted = false

        suspend fun refreshClient() {
            if (relocate) {
                client = clientFactory(locate(pairing))
                relocate = false
            }
        }

        // Snapshots every 30 s.
        launch {
            var failures = 0
            while (!halted) {
                refreshClient()
                val result = if (online()) client.snapshot() else UsageResult.Unavailable("Mac not reachable")
                when (result) {
                    is UsageResult.Available -> {
                        failures = 0
                        val snapshot = result.value
                        _state.value = SyncState.Live(SyncData(snapshot, clock.instant()))
                        SyncMapper.agentPeeks(previousAgents, snapshot.agents, strings).forEach(_peeks::tryEmit)
                        previousAgents = snapshot.agents
                        withTimeoutOrNull(snapshotInterval.toMillis()) { nudge.first() }
                    }
                    is UsageResult.Unavailable -> {
                        if (fail(result.reason)) {
                            halted = true
                        } else {
                            relocate = true
                            withTimeoutOrNull(backoff(++failures)) { nudge.first() }
                        }
                    }
                }
            }
        }

        // Events: the server holds each request for up to 30 s.
        launch {
            var failures = 0
            while (!halted) {
                refreshClient()
                if (!online()) {
                    delay(backoff(++failures))
                    continue
                }
                when (val result = client.events(cursor)) {
                    is UsageResult.Available -> {
                        failures = 0
                        val batch = result.value
                        cursor = batch.latestSeq
                        val now = clock.instant()
                        batch.events.mapNotNull { SyncMapper.peek(it, now) }.forEach(_peeks::tryEmit)
                        if (batch.events.isEmpty()) delay(EMPTY_POLL_GAP_MS)
                    }
                    is UsageResult.Unavailable -> {
                        if (result.reason == HttpSyncClient.PAIR_AGAIN) {
                            _state.value = SyncState.PairAgain
                            halted = true
                        } else {
                            relocate = true
                            delay(backoff(++failures))
                        }
                    }
                }
            }
        }
    }

    /** Records a snapshot failure in [state]. Returns true when polling must stop (pair again). */
    private fun fail(reason: String): Boolean {
        val last = _state.value.dataOrNull
        _state.value = when (reason) {
            HttpSyncClient.PAIR_AGAIN -> SyncState.PairAgain
            "Mac not reachable" -> SyncState.Unreachable(last)
            else -> SyncState.Problem(reason, last)
        }
        return reason == HttpSyncClient.PAIR_AGAIN
    }

    private suspend fun locate(pairing: PairingPayload): PairingPayload =
        try {
            locator.locate(pairing)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            pairing
        }

    companion object {
        private const val EMPTY_POLL_GAP_MS = 500L

        /** 2 s, 4 s, 8 s ... capped at 60 s. */
        fun backoff(failures: Int): Long = (2_000L shl (failures - 1).coerceIn(0, 5)).coerceAtMost(60_000L)
    }
}
