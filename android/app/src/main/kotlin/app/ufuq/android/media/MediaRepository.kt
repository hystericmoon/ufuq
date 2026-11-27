package app.ufuq.android.media

import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.SystemClock
import android.service.notification.NotificationListenerService
import app.ufuq.android.listener.ListenerCallback
import app.ufuq.android.listener.ListenerRegistry
import app.ufuq.android.listener.UfuqNotificationListener
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Follows the active media session through the shared notification listener and exposes it as
 * [state]; null when nothing plays or access is off. Reads only media sessions (title, position,
 * state); nothing is stored or sent.
 */
class MediaRepository(private val context: Context) : ListenerCallback {
    private val _state = MutableStateFlow<MediaState?>(null)
    val state: StateFlow<MediaState?> = _state.asStateFlow()

    private var manager: MediaSessionManager? = null
    private var controller: MediaController? = null

    private val sessionsListener = MediaSessionManager.OnActiveSessionsChangedListener { select(it.orEmpty()) }
    private val controllerCallback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) = publish()
        override fun onMetadataChanged(metadata: MediaMetadata?) = publish()
        override fun onSessionDestroyed() = refresh()
    }

    fun start() = ListenerRegistry.register(this)

    fun accessGranted(): Boolean = UfuqNotificationListener.isAccessGranted(context)

    override fun onConnected(service: NotificationListenerService) {
        val m = context.getSystemService(MediaSessionManager::class.java) ?: return
        manager = m
        runCatching { m.addOnActiveSessionsChangedListener(sessionsListener, UfuqNotificationListener.component(context)) }
        refresh()
    }

    override fun onDisconnected() {
        manager?.let { runCatching { it.removeOnActiveSessionsChangedListener(sessionsListener) } }
        manager = null
        bind(null)
    }

    private fun refresh() {
        val m = manager ?: return
        val sessions = try {
            m.getActiveSessions(UfuqNotificationListener.component(context))
        } catch (_: SecurityException) {
            emptyList() // access was revoked: show the empty state, never crash
        }
        select(sessions)
    }

    /** The playing session wins; otherwise the first paused one; stopped or empty ones do not count. */
    private fun select(sessions: List<MediaController>) {
        val usable = sessions.filter { it.playbackState?.state in LIVE_STATES && it.metadata != null }
        bind(usable.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING } ?: usable.firstOrNull())
    }

    private fun bind(next: MediaController?) {
        if (next?.sessionToken != controller?.sessionToken) {
            controller?.let { runCatching { it.unregisterCallback(controllerCallback) } }
            controller = next
            next?.registerCallback(controllerCallback)
        }
        publish()
    }

    private fun publish() {
        val c = controller
        _state.value = c?.let { runCatching { build(it) }.getOrNull() }
    }

    private fun build(c: MediaController): MediaState? {
        val playback = c.playbackState ?: return null
        val meta = c.metadata ?: return null
        val title = (meta.getString(MediaMetadata.METADATA_KEY_TITLE) ?: meta.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE))
            ?.takeIf { it.isNotBlank() } ?: return null
        return MediaState(
            title = title,
            artist = (meta.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: meta.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE))?.takeIf { it.isNotBlank() },
            durationMs = meta.getLong(MediaMetadata.METADATA_KEY_DURATION).coerceAtLeast(0),
            positionMs = playback.position.coerceAtLeast(0),
            updatedAtElapsedMs = playback.lastPositionUpdateTime.takeIf { it > 0 } ?: SystemClock.elapsedRealtime(),
            speed = playback.playbackSpeed,
            playing = playback.state == PlaybackState.STATE_PLAYING,
            canSeek = playback.actions and PlaybackState.ACTION_SEEK_TO != 0L,
            packageName = c.packageName,
        )
    }

    fun togglePlayPause() {
        val c = controller ?: return
        runCatching { if (state.value?.playing == true) c.transportControls.pause() else c.transportControls.play() }
    }

    fun seekTo(positionMs: Long) {
        val c = controller ?: return
        runCatching { c.transportControls.seekTo(positionMs.coerceAtLeast(0)) }
    }

    private companion object {
        val LIVE_STATES = setOf(
            PlaybackState.STATE_PLAYING, PlaybackState.STATE_PAUSED, PlaybackState.STATE_BUFFERING,
            PlaybackState.STATE_FAST_FORWARDING, PlaybackState.STATE_REWINDING,
            PlaybackState.STATE_SKIPPING_TO_NEXT, PlaybackState.STATE_SKIPPING_TO_PREVIOUS, PlaybackState.STATE_SKIPPING_TO_QUEUE_ITEM,
        )
    }
}
