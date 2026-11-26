package app.ufuq.android.island

import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow

/** In-process link between the Quick Settings tile and the running island service. */
class IslandController {
    private val _expand = MutableSharedFlow<Unit>(extraBufferCapacity = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    val expandRequests: SharedFlow<Unit> = _expand

    /** True while [IslandService] is alive and has its overlay on screen. */
    @Volatile var isShowing: Boolean = false

    /** Asks the running island to expand. Returns false when it is not showing. */
    fun requestExpand(): Boolean {
        if (!isShowing) return false
        return _expand.tryEmit(Unit)
    }
}
