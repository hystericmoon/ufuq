package app.ufuq.android.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleResumeEffect
import app.ufuq.android.R
import app.ufuq.android.graph
import app.ufuq.android.settings.AppSettings
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId

class MainActivity : ComponentActivity() {
    private val openMediaAccess = mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        openMediaAccess.value = intent?.action == ACTION_ALLOW_MEDIA
        setContent { UfuqTheme { UfuqRoot(openMediaAccess) } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == ACTION_ALLOW_MEDIA) openMediaAccess.value = true
    }

    companion object {
        /** From the island's media page: open the explanation before Android's notification-access screen. */
        const val ACTION_ALLOW_MEDIA = "app.ufuq.android.action.ALLOW_MEDIA"
    }
}

private enum class Screen { TODAY, SETTINGS, OVERLAY_EXPLAIN, LISTENER_EXPLAIN }

@Composable
private fun UfuqRoot(openMediaAccess: MutableState<Boolean> = mutableStateOf(false)) {
    val context = LocalContext.current
    val graph = context.graph
    val scope = rememberCoroutineScope()
    val settings by graph.settings.settings.collectAsState(initial = AppSettings())
    var screen by remember { mutableStateOf(Screen.TODAY) }
    var locationMessage by remember { mutableStateOf<String?>(null) }
    var overlayGranted by remember { mutableStateOf(Settings.canDrawOverlays(context)) }
    var wantOverlay by remember { mutableStateOf(false) }
    var mediaGranted by remember { mutableStateOf(graph.media.accessGranted()) }
    LaunchedEffect(openMediaAccess.value) {
        if (openMediaAccess.value) {
            openMediaAccess.value = false
            screen = Screen.LISTENER_EXPLAIN
        }
    }

    val notificationLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    // The Live Update chip is on by default, so ask once at the start (Android 13+).
    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            notificationLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    // Back from Android's overlay-permission screen: finish the switch the user asked for.
    LifecycleResumeEffect(Unit) {
        overlayGranted = Settings.canDrawOverlays(context)
        mediaGranted = graph.media.accessGranted()
        if (wantOverlay && overlayGranted) {
            wantOverlay = false
            scope.launch { graph.settings.update { it.copy(overlayEnabled = true) } }
            screen = Screen.SETTINGS
        }
        onPauseOrDispose { }
    }

    val locationText = stringResource(R.string.settings_location_failed)
    val myLocation = stringResource(R.string.settings_my_location)
    val finding = stringResource(R.string.settings_location_finding)
    fun findLocation() {
        locationMessage = finding
        scope.launch {
            val fix = LocationFinder.find(context)
            if (fix == null) {
                locationMessage = locationText
            } else {
                locationMessage = null
                graph.settings.update {
                    it.copy(cityName = myLocation, latitude = fix.latitude, longitude = fix.longitude, zoneId = ZoneId.systemDefault().id, usesDeviceLocation = true)
                }
            }
        }
    }
    val locationLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) findLocation() else locationMessage = locationText
    }

    val actions = SettingsActions(
        onBack = { screen = Screen.TODAY },
        onCity = { city ->
            scope.launch {
                graph.settings.update {
                    it.copy(cityName = city.name, latitude = city.latitude, longitude = city.longitude, zoneId = city.zone.id, usesDeviceLocation = false)
                }
            }
        },
        onUseMyLocation = {
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
                findLocation()
            } else {
                locationLauncher.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
            }
        },
        onMethod = { m -> scope.launch { graph.settings.update { it.copy(method = m) } } },
        onOverlay = { on ->
            if (!on) {
                scope.launch { graph.settings.update { it.copy(overlayEnabled = false) } }
            } else if (Settings.canDrawOverlays(context)) {
                scope.launch { graph.settings.update { it.copy(overlayEnabled = true) } }
            } else {
                screen = Screen.OVERLAY_EXPLAIN
            }
        },
        onMediaAccess = { screen = Screen.LISTENER_EXPLAIN },
        onLiveUpdate = { on -> scope.launch { graph.settings.update { it.copy(liveUpdateEnabled = on) } } },
        onLead = { m -> scope.launch { graph.settings.update { it.copy(adhanLeadMinutes = m) } } },
    )

    BackHandler(enabled = screen != Screen.TODAY) {
        screen = if (screen == Screen.OVERLAY_EXPLAIN || screen == Screen.LISTENER_EXPLAIN) Screen.SETTINGS else Screen.TODAY
    }

    when (screen) {
        Screen.TODAY -> {
            var now by remember { mutableStateOf(Instant.now()) }
            LifecycleResumeEffect(settings) {
                now = Instant.now()
                onPauseOrDispose { }
            }
            LaunchedEffect(Unit) {
                while (true) {
                    delay(1_000)
                    now = Instant.now()
                }
            }
            val state = remember(now, settings) { graph.apply(settings); TodayState.at(now, graph.prayer) }
            TodayScreen(state, onOpenSettings = { screen = Screen.SETTINGS })
        }
        Screen.SETTINGS -> SettingsScreen(settings, actions, locationMessage, overlayGranted, mediaAccessGranted = mediaGranted)
        Screen.OVERLAY_EXPLAIN -> OverlayExplainScreen(
            onContinue = {
                wantOverlay = true
                context.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}")))
            },
            onCancel = { screen = Screen.SETTINGS },
        )
        Screen.LISTENER_EXPLAIN -> ListenerExplainScreen(
            onContinue = { context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)) },
            onCancel = { screen = Screen.SETTINGS },
        )
    }
}
