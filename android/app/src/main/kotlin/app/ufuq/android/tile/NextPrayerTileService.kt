package app.ufuq.android.tile

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import app.ufuq.android.R
import app.ufuq.android.graph
import app.ufuq.android.island.IslandService
import app.ufuq.android.prayer.Countdown
import app.ufuq.android.prayer.PrayerProgress
import app.ufuq.android.ui.MainActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.time.Instant

/**
 * Quick Settings tile. Label = the next prayer, subtitle = the countdown. Tapping expands the
 * island when the overlay is on, and opens the app otherwise. Redrawn whenever the shade opens.
 */
class NextPrayerTileService : TileService() {
    private var scope: CoroutineScope? = null

    override fun onStartListening() {
        super.onStartListening()
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate).also { it.launch { render() } }
    }

    override fun onStopListening() {
        scope?.cancel()
        scope = null
        super.onStopListening()
    }

    private suspend fun render() {
        val tile = qsTile ?: return
        graph.currentSettings()
        val progress = PrayerProgress.at(Instant.now(), graph.prayer)
        tile.icon = Icon.createWithResource(this, R.drawable.ic_mosque)
        if (progress == null) {
            tile.label = getString(R.string.tile_label)
            tile.state = Tile.STATE_INACTIVE
            if (Build.VERSION.SDK_INT >= 29) tile.subtitle = getString(R.string.tile_no_location)
        } else {
            tile.label = progress.name
            tile.state = Tile.STATE_ACTIVE
            if (Build.VERSION.SDK_INT >= 29) tile.subtitle = Countdown.short(progress.remaining)
            tile.contentDescription = getString(R.string.tile_description, progress.name, Countdown.short(progress.remaining))
        }
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()
        scope?.launch {
            val overlayOn = graph.currentSettings().overlayEnabled
            // The running island expands in place; if it is not alive, try to start it; else open the app.
            if (overlayOn && (graph.island.requestExpand() || IslandService.expand(this@NextPrayerTileService))) {
                // The island draws over the shade; a tile cannot collapse it without opening an activity.
            } else {
                openApp()
            }
        }
    }

    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE))
        } else {
            @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
            startActivityAndCollapse(intent)
        }
    }
}
