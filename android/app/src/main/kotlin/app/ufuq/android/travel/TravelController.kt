package app.ufuq.android.travel

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.IntentCompat
import app.ufuq.android.R
import app.ufuq.android.graph
import app.ufuq.android.settings.AppSettings
import app.ufuq.android.settings.Cities
import app.ufuq.android.settings.SettingsRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.time.ZoneId

private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

/**
 * "Follow my location": a passive listener for big moves (coarse location, no battery of its own)
 * plus a check of the last known fix at each refresh. A move of 25 km or more updates the city,
 * coordinates and time zone, and posts one quiet notice.
 */
class TravelController(private val context: Context, private val settings: SettingsRepository) {
    private val lm = context.getSystemService(LocationManager::class.java)

    private fun hasCoarse() = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    /** Called from the refresh hook: settings change, prayer boundary, boot. */
    @SuppressLint("MissingPermission")
    fun onRefresh(s: AppSettings) {
        val pi = listenerIntent(create = s.followLocation && hasCoarse())
        if (!s.followLocation || !hasCoarse()) {
            pi?.let { runCatching { lm?.removeUpdates(it) }; it.cancel() }
            return
        }
        pi ?: return
        runCatching { lm?.requestLocationUpdates(LocationManager.PASSIVE_PROVIDER, MIN_TIME_MS, TravelLogic.THRESHOLD_KM.toFloat() * 1000f, pi) }
        // The boundary check: the freshest fix any app has already obtained.
        val fix = runCatching { lm?.getLastKnownLocation(LocationManager.PASSIVE_PROVIDER) }.getOrNull()
        if (fix != null) consider(s, fix)
    }

    fun consider(s: AppSettings, fix: Location) {
        val fallback = context.getString(R.string.travel_current_location)
        val update = TravelLogic.plan(s, fix.latitude, fix.longitude, Cities.ALL, fallback) ?: return
        scope.launch {
            // Re-check against the stored place: a burst of fixes must post one notice only.
            var changed = false
            settings.update { cur ->
                val u = TravelLogic.plan(cur, fix.latitude, fix.longitude, Cities.ALL, fallback)
                if (u == null) cur else { changed = true; TravelLogic.apply(cur, u, ZoneId.systemDefault().id) }
            }
            if (changed) notify(update.name)
        }
    }

    private fun notify(city: String) {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, context.getString(R.string.channel_travel), NotificationManager.IMPORTANCE_LOW).apply {
                description = context.getString(R.string.channel_travel_description)
                setShowBadge(false)
            },
        )
        val n = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.travel_updated, city))
            .setAutoCancel(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, n)
        } catch (_: SecurityException) {
        }
    }

    private fun listenerIntent(create: Boolean): PendingIntent? = PendingIntent.getBroadcast(
        context, 7201,
        Intent(context, TravelReceiver::class.java).setAction(ACTION_LOCATION),
        // Mutable: the system adds the Location extra.
        PendingIntent.FLAG_MUTABLE or if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE,
    )

    companion object {
        const val CHANNEL = "travel"
        const val NOTIFICATION_ID = 21
        const val ACTION_LOCATION = "app.ufuq.android.travel.LOCATION"
        private const val MIN_TIME_MS = 10 * 60_000L
    }
}

/** Receives the passive location changes. */
class TravelReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val fix = IntentCompat.getParcelableExtra(intent, LocationManager.KEY_LOCATION_CHANGED, Location::class.java) ?: return
        val app = context.applicationContext
        val pending = goAsync()
        scope.launch {
            try {
                app.graph.travel.consider(app.graph.currentSettings(), fix)
            } finally {
                pending.finish()
            }
        }
    }
}
