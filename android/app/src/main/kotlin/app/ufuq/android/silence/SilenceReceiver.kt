package app.ufuq.android.silence

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import app.ufuq.android.graph
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

/** Adhan start, restore and geofence events. */
class SilenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val app = context.applicationContext
        val pending = goAsync()
        scope.launch {
            try {
                val silence = app.graph.silence
                when (action) {
                    ACTION_ADHAN -> silence.onAdhan(app.graph.currentSettings(), intent.getLongExtra(EXTRA_AT, System.currentTimeMillis()))
                    ACTION_RESTORE -> silence.onRestore()
                    ACTION_GEOFENCE -> GeofenceMapping.event(intent)?.let { silence.onGeofence(app.graph.currentSettings(), it) }
                }
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        const val ACTION_ADHAN = "app.ufuq.android.silence.ADHAN"
        const val ACTION_RESTORE = "app.ufuq.android.silence.RESTORE"
        const val ACTION_GEOFENCE = "app.ufuq.android.silence.GEOFENCE"
        const val EXTRA_AT = "at"
    }
}
