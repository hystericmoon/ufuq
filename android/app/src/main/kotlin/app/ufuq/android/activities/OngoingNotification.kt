package app.ufuq.android.activities

import kotlinx.coroutines.flow.Flow

/**
 * What the island needs to know about one ongoing notification, as plain data (no Android types, so
 * the mapping is unit-testable). Held in memory only; never written to disk or logs.
 */
data class OngoingNotification(
    /** StatusBarNotification.getKey(): stable for one notification, contains no content. */
    val key: String,
    val packageName: String,
    /** The app's label ("Gojek"), resolved by the adapter. */
    val appLabel: String,
    val title: String? = null,
    val text: String? = null,
    val isOngoing: Boolean = true,
    /** Notification.category, e.g. "navigation". */
    val category: String? = null,
    val progressMax: Int = 0,
    val progress: Int = 0,
    val progressIndeterminate: Boolean = false,
    /** Notification.`when` in epoch millis. */
    val whenMillis: Long? = null,
    val usesChronometer: Boolean = false,
    val chronometerCountDown: Boolean = false,
    /** Android 16 promoted ongoing (Live Update) flag. */
    val isPromoted: Boolean = false,
    /** Notification.ProgressStyle in use (Android 16). */
    val hasProgressStyle: Boolean = false,
    /** ProgressStyle points as fractions 0..1 of the bar (stops, milestones). */
    val progressPoints: List<Float> = emptyList(),
    val isMedia: Boolean = false,
    val isCall: Boolean = false,
    val postTimeMillis: Long = 0L,
    /** Opens the source app (its contentIntent, or its launcher). Null when it cannot be opened. */
    val open: (() -> Unit)? = null,
)

/**
 * The seam between a notification listener and the island's "other apps" feature.
 * The listener service calls [ActivitiesListenerAdapter]; everything else reads this flow.
 */
interface OngoingNotificationSource {
    /** Qualifying ongoing notifications right now (already reduced to the fields in [OngoingNotification]). */
    val ongoing: Flow<List<OngoingNotification>>
}

/** An app that posted a qualifying notification this session, for the settings list. */
data class SeenApp(val packageName: String, val label: String)
