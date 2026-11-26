package app.ufuq.android.silence

import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import androidx.core.content.ContextCompat

/** Reads and sets Do Not Disturb. Needs the user's "Do Not Disturb access" grant. */
interface DndGateway {
    fun hasAccess(): Boolean
    fun currentFilter(): Int
    fun setFilter(filter: Int)
}

class SystemDnd(context: Context) : DndGateway {
    private val nm = context.getSystemService(NotificationManager::class.java)
    override fun hasAccess() = nm.isNotificationPolicyAccessGranted
    override fun currentFilter() = nm.currentInterruptionFilter
    override fun setFilter(filter: Int) {
        runCatching { nm.setInterruptionFilter(filter) }
    }
}

enum class AlarmKind(val requestCode: Int, val action: String) {
    ADHAN(7101, SilenceReceiver.ACTION_ADHAN),
    RESTORE(7102, SilenceReceiver.ACTION_RESTORE),
}

interface SilenceAlarms {
    fun schedule(kind: AlarmKind, atMillis: Long)
    fun cancel(kind: AlarmKind)

    /** False on Android 12+ until the user allows exact alarms. */
    fun canScheduleExact(): Boolean
}

class SystemAlarms(private val context: Context) : SilenceAlarms {
    private val alarms = context.getSystemService(AlarmManager::class.java)

    override fun canScheduleExact() = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()

    @SuppressLint("ScheduleExactAlarm")
    override fun schedule(kind: AlarmKind, atMillis: Long) {
        val pi = pending(kind, atMillis)
        val choice = AlarmChoice.of(canScheduleExact())
        try {
            when (choice) {
                AlarmChoice.Exact -> alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pi)
                is AlarmChoice.Window -> alarms.setWindow(AlarmManager.RTC_WAKEUP, atMillis, choice.lengthMillis, pi)
            }
        } catch (_: SecurityException) {
            // Permission revoked between the check and the call: fall back to the inexact window.
            alarms.setWindow(AlarmManager.RTC_WAKEUP, atMillis, AlarmChoice.WINDOW_MILLIS, pi)
        }
    }

    override fun cancel(kind: AlarmKind) {
        alarms.cancel(pending(kind, 0))
    }

    private fun pending(kind: AlarmKind, atMillis: Long): PendingIntent = PendingIntent.getBroadcast(
        context, kind.requestCode,
        Intent(context, SilenceReceiver::class.java).setAction(kind.action).putExtra(SilenceReceiver.EXTRA_AT, atMillis),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
}

/** Keeps the system's proximity alerts equal to the saved mosques. */
interface ProximityRegistrar {
    fun sync(mosques: List<Mosque>)
}

/** `LocationManager.addProximityAlert`: no Play Services. Deprecated since API 29, but still works for this. */
@Suppress("DEPRECATION")
class SystemProximity(private val context: Context) : ProximityRegistrar {
    private val lm = context.getSystemService(LocationManager::class.java)
    private val registered = mutableSetOf<Int>()

    @SuppressLint("MissingPermission")
    override fun sync(mosques: List<Mosque>) {
        val allowed = ContextCompat.checkSelfPermission(context, android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val wanted = if (allowed) mosques else emptyList()
        // Alerts vanish on reboot together with their PendingIntent; "registered" is asked of the system.
        for (id in knownIds(mosques)) {
            if (wanted.none { it.id == id }) {
                intent(id, create = false)?.let { runCatching { lm?.removeProximityAlert(it) }; it.cancel() }
            }
        }
        for (m in wanted) {
            if (intent(m.id, create = false) != null) continue
            val pi = intent(m.id, create = true) ?: continue
            try {
                lm?.addProximityAlert(m.latitude, m.longitude, m.radiusMeters, -1L, pi)
                registered += m.id
            } catch (_: SecurityException) {
                pi.cancel()
            }
        }
    }

    private fun knownIds(mosques: List<Mosque>): Set<Int> = registered + mosques.map { it.id }

    private fun intent(id: Int, create: Boolean): PendingIntent? {
        val i = Intent(context, SilenceReceiver::class.java)
            .setAction(SilenceReceiver.ACTION_GEOFENCE)
            .setData(Uri.parse("ufuq://mosque/$id"))
        // The system adds "entering" to the intent, which needs a mutable PendingIntent (explicit component, so safe).
        val flags = PendingIntent.FLAG_MUTABLE or if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE
        return PendingIntent.getBroadcast(context, id, i, flags)
    }
}
