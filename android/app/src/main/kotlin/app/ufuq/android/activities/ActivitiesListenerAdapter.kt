package app.ufuq.android.activities

import android.app.ActivityOptions
import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import android.service.notification.StatusBarNotification
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update

/**
 * The listener calls this; it never is a service itself. Keeps qualifying ongoing notifications in
 * memory only (nothing is written to disk, logged or sent). The listener must call, on its own
 * callbacks and on any thread:
 *
 *  - [onListenerConnected] from onListenerConnected(), with getActiveNotifications()
 *  - [onNotificationPosted] from onNotificationPosted(sbn)
 *  - [onNotificationRemoved] from onNotificationRemoved(sbn)
 *  - [onListenerDisconnected] from onListenerDisconnected()
 */
class ActivitiesListenerAdapter(context: Context) : OngoingNotificationSource {
    private val context = context.applicationContext
    private val live = MutableStateFlow<Map<String, OngoingNotification>>(emptyMap())
    private val seen = MutableStateFlow<Map<String, String>>(emptyMap())
    private val labels = HashMap<String, String>()

    override val ongoing: Flow<List<OngoingNotification>> = live.map { it.values.toList() }

    /** Apps that posted a qualifying notification since the process started. */
    val seenApps: Flow<List<SeenApp>> = seen.map { m -> m.map { SeenApp(it.key, it.value) }.sortedBy { it.label.lowercase() } }

    fun onListenerConnected(active: Array<StatusBarNotification>?) {
        live.value = emptyMap()
        active?.forEach(::onNotificationPosted)
    }

    fun onListenerDisconnected() {
        live.value = emptyMap()
    }

    fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        val n = runCatching { read(sbn) }.getOrNull()
        if (n != null && OngoingMapper.qualifies(n, context.packageName)) {
            live.update { it + (n.key to n) }
            seen.update { it + (n.packageName to n.appLabel) }
        } else {
            live.update { it - sbn.key }
        }
    }

    fun onNotificationRemoved(sbn: StatusBarNotification?) {
        sbn ?: return
        live.update { it - sbn.key }
    }

    private fun label(pkg: String): String = labels.getOrPut(pkg) {
        runCatching {
            val pm = context.packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
        }.getOrDefault(pkg)
    }

    private fun read(sbn: StatusBarNotification): OngoingNotification {
        val n = sbn.notification
        val x = n.extras
        val template = x.getString(Notification.EXTRA_TEMPLATE).orEmpty()
        val category = n.category
        var max = x.getInt(Notification.EXTRA_PROGRESS_MAX)
        var progress = x.getInt(Notification.EXTRA_PROGRESS)
        var indeterminate = x.getBoolean(Notification.EXTRA_PROGRESS_INDETERMINATE)
        val progressStyle = template.endsWith("ProgressStyle")
        var points = emptyList<Float>()
        if (progressStyle && Build.VERSION.SDK_INT >= 36) {
            runCatching {
                val style = Notification.Builder.recoverBuilder(context, n).style as? Notification.ProgressStyle
                if (style != null) {
                    max = style.progressMax.takeIf { it > 0 } ?: max
                    progress = style.progress
                    indeterminate = style.isProgressIndeterminate
                    points = if (max > 0) style.progressPoints.map { (it.position.toFloat() / max).coerceIn(0f, 1f) } else emptyList()
                }
            }
        }
        val promoted = Build.VERSION.SDK_INT >= 36 &&
            (n.flags and Notification.FLAG_PROMOTED_ONGOING != 0 || x.getBoolean(Notification.EXTRA_REQUEST_PROMOTED_ONGOING))
        return OngoingNotification(
            key = sbn.key,
            packageName = sbn.packageName,
            appLabel = label(sbn.packageName),
            title = x.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
            text = x.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
            isOngoing = n.flags and Notification.FLAG_ONGOING_EVENT != 0,
            category = category,
            progressMax = max,
            progress = progress,
            progressIndeterminate = indeterminate,
            whenMillis = n.`when`.takeIf { it > 0 },
            usesChronometer = x.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER),
            chronometerCountDown = x.getBoolean(Notification.EXTRA_CHRONOMETER_COUNT_DOWN),
            isPromoted = promoted,
            hasProgressStyle = progressStyle,
            progressPoints = points,
            isMedia = template.endsWith("MediaStyle") || template.endsWith("DecoratedMediaCustomViewStyle") ||
                x.containsKey(Notification.EXTRA_MEDIA_SESSION),
            isCall = category == Notification.CATEGORY_CALL || template.endsWith("CallStyle"),
            postTimeMillis = sbn.postTime,
            open = opener(sbn.packageName, n.contentIntent),
        )
    }

    private fun opener(pkg: String, intent: PendingIntent?): () -> Unit = {
        val sent = intent != null && runCatching {
            if (Build.VERSION.SDK_INT >= 34) {
                val options = ActivityOptions.makeBasic()
                    .setPendingIntentBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
                intent.send(options.toBundle())
            } else {
                intent.send()
            }
        }.isSuccess
        if (!sent) {
            context.packageManager.getLaunchIntentForPackage(pkg)
                ?.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                ?.let { runCatching { context.startActivity(it) } }
        }
    }
}
