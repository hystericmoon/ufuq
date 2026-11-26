package app.ufuq.android.listener

import android.content.ComponentName
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationManagerCompat
import java.util.concurrent.CopyOnWriteArrayList

/**
 * The one notification-listener service of the app. Android grants this access once, so the media
 * page (A3) and other apps' live activities (A7) share it: each feature subscribes through
 * [ListenerRegistry] instead of declaring its own service. It reads nothing itself, stores nothing
 * and sends nothing.
 */
class UfuqNotificationListener : NotificationListenerService() {
    override fun onListenerConnected() {
        ListenerRegistry.connected = this
        ListenerRegistry.forEach { it.onConnected(this) }
    }

    override fun onListenerDisconnected() {
        ListenerRegistry.connected = null
        ListenerRegistry.forEach { it.onDisconnected() }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) = ListenerRegistry.forEach { it.onPosted(sbn) }

    override fun onNotificationRemoved(sbn: StatusBarNotification) = ListenerRegistry.forEach { it.onRemoved(sbn) }

    companion object {
        fun component(context: Context) = ComponentName(context, UfuqNotificationListener::class.java)

        /** True when the user has allowed notification access for Ufuq. */
        fun isAccessGranted(context: Context): Boolean =
            NotificationManagerCompat.getEnabledListenerPackages(context).contains(context.packageName)
    }
}

/** What a feature can listen to. All callbacks arrive on the main thread; every one is optional. */
interface ListenerCallback {
    fun onConnected(service: NotificationListenerService) {}
    fun onDisconnected() {}
    fun onPosted(sbn: StatusBarNotification) {}
    fun onRemoved(sbn: StatusBarNotification) {}
}

/** Small in-process registry so features subscribe to the shared listener without owning a service. */
object ListenerRegistry {
    private val callbacks = CopyOnWriteArrayList<ListenerCallback>()

    /** The bound service while access is granted and Android has connected it, else null. */
    @Volatile var connected: NotificationListenerService? = null
        internal set

    /** Subscribes [callback]; when the listener is already connected it gets [ListenerCallback.onConnected] at once. */
    fun register(callback: ListenerCallback) {
        if (callbacks.addIfAbsent(callback)) connected?.let(callback::onConnected)
    }

    fun unregister(callback: ListenerCallback) {
        callbacks.remove(callback)
    }

    internal fun forEach(action: (ListenerCallback) -> Unit) {
        for (callback in callbacks) runCatching { action(callback) } // one feature's bug never stops the others
    }
}
