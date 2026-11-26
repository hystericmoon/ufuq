package app.ufuq.android.sync

import app.ufuq.core.sync.SyncSnapshot
import java.time.Instant

/** The last good snapshot and when it arrived on this phone. */
data class SyncData(val snapshot: SyncSnapshot, val fetchedAt: Instant)

/** Where the Mac link stands. Page B and the pill read this; nothing in it throws. */
sealed interface SyncState {
    /** No Mac paired: nothing is polled. */
    data object Unpaired : SyncState

    /** First contact (or a retry after returning to the app); [data] is the last good snapshot, if any. */
    data class Connecting(val data: SyncData? = null) : SyncState

    data class Live(val data: SyncData) : SyncState

    /** The Mac cannot be reached (not on this network, asleep). The last data stays, marked stale. */
    data class Unreachable(val data: SyncData? = null) : SyncState

    /** The key was rejected: the Mac forgot this phone or its key changed. */
    data object PairAgain : SyncState

    /** Anything else the client reports (clock skew, newer protocol, bad reply). */
    data class Problem(val reason: String, val data: SyncData? = null) : SyncState

    val dataOrNull: SyncData?
        get() = when (this) {
            is Live -> data
            is Connecting -> data
            is Unreachable -> data
            is Problem -> data
            else -> null
        }
}
