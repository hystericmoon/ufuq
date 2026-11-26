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
import app.ufuq.android.silence.BackgroundLocationExplainScreen
import app.ufuq.android.silence.ExtrasActions
import app.ufuq.android.silence.ExtrasState
import app.ufuq.android.silence.SilenceExplainScreen
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { UfuqTheme { UfuqRoot() } }
    }
}

private enum class Screen { TODAY, SETTINGS, OVERLAY_EXPLAIN, SILENCE_EXPLAIN, BACKGROUND_EXPLAIN }

@Composable
private fun UfuqRoot() {
    val context = LocalContext.current
    val graph = context.graph
    val scope = rememberCoroutineScope()
    val settings by graph.settings.settings.collectAsState(initial = AppSettings())
    var screen by remember { mutableStateOf(Screen.TODAY) }
    var locationMessage by remember { mutableStateOf<String?>(null) }
    var overlayGranted by remember { mutableStateOf(Settings.canDrawOverlays(context)) }
    var wantOverlay by remember { mutableStateOf(false) }
    var wantSilence by remember { mutableStateOf(false) }
    var dndGranted by remember { mutableStateOf(graph.silence.hasDndAccess()) }
    var fineGranted by remember { mutableStateOf(granted(context, Manifest.permission.ACCESS_FINE_LOCATION)) }
    var backgroundGranted by remember { mutableStateOf(granted(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION)) }
    var exactAllowed by remember { mutableStateOf(graph.silence.canScheduleExact()) }
    var mosqueMessage by remember { mutableStateOf<String?>(null) }
    val mosques by graph.silence.mosques.collectAsState()

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
        if (wantOverlay && overlayGranted) {
            wantOverlay = false
            scope.launch { graph.settings.update { it.copy(overlayEnabled = true) } }
            screen = Screen.SETTINGS
        }
        // Back from Do Not Disturb access, location or exact-alarm settings.
        dndGranted = graph.silence.hasDndAccess()
        fineGranted = granted(context, Manifest.permission.ACCESS_FINE_LOCATION)
        backgroundGranted = granted(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        exactAllowed = graph.silence.canScheduleExact()
        if (wantSilence && dndGranted) {
            wantSilence = false
            scope.launch { graph.settings.update { it.copy(silenceEnabled = true) } }
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
    val mosqueSaved = stringResource(R.string.mosque_added)
    val mosqueFailed = stringResource(R.string.mosque_failed)
    fun addMosque(name: String) {
        mosqueMessage = finding
        scope.launch {
            val fix = LocationFinder.find(context)
            if (fix == null) {
                mosqueMessage = mosqueFailed
            } else {
                val m = graph.silence.addMosque(name, fix.latitude, fix.longitude)
                mosqueMessage = mosqueSaved.format(m.name)
                graph.liveUpdate.refresh(graph.currentSettings()) // registers the new proximity alert
            }
        }
    }
    var pendingMosqueName by remember { mutableStateOf("") }
    val fineLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        fineGranted = ok
        if (ok) addMosque(pendingMosqueName) else mosqueMessage = mosqueFailed
    }
    val backgroundLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok -> backgroundGranted = ok }
    val followLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) scope.launch { graph.settings.update { it.copy(followLocation = true) } }
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
        onLiveUpdate = { on -> scope.launch { graph.settings.update { it.copy(liveUpdateEnabled = on) } } },
        onLead = { m -> scope.launch { graph.settings.update { it.copy(adhanLeadMinutes = m) } } },
    )

    val extrasState = ExtrasState(dndGranted, mosques, fineGranted, backgroundGranted, exactAllowed, mosqueMessage)
    val extrasActions = ExtrasActions(
        onSilence = { on ->
            if (!on) {
                wantSilence = false
                scope.launch { graph.settings.update { it.copy(silenceEnabled = false) } }
            } else if (graph.silence.hasDndAccess()) {
                scope.launch { graph.settings.update { it.copy(silenceEnabled = true) } }
            } else {
                screen = Screen.SILENCE_EXPLAIN
            }
        },
        onSilenceMinutes = { m -> scope.launch { graph.settings.update { it.copy(silenceMinutes = m) } } },
        onGrantDnd = { screen = Screen.SILENCE_EXPLAIN },
        onExactAlarms = {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${context.packageName}")))
            }
        },
        onAddMosque = { name ->
            if (fineGranted) {
                addMosque(name)
            } else {
                pendingMosqueName = name
                fineLauncher.launch(Manifest.permission.ACCESS_FINE_LOCATION)
            }
        },
        onRemoveMosque = { id ->
            graph.silence.removeMosque(id)
            scope.launch { graph.liveUpdate.refresh(graph.currentSettings()) }
        },
        onBackgroundLocation = { screen = Screen.BACKGROUND_EXPLAIN },
        onRamadan = { on -> scope.launch { graph.settings.update { it.copy(ramadanManual = on) } } },
        onFollowLocation = { on ->
            if (!on || granted(context, Manifest.permission.ACCESS_COARSE_LOCATION)) {
                scope.launch { graph.settings.update { it.copy(followLocation = on) } }
            } else {
                followLauncher.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
            }
        },
    )

    BackHandler(enabled = screen != Screen.TODAY) {
        screen = if (screen == Screen.OVERLAY_EXPLAIN || screen == Screen.SILENCE_EXPLAIN || screen == Screen.BACKGROUND_EXPLAIN) Screen.SETTINGS else Screen.TODAY
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
        Screen.SETTINGS -> SettingsScreen(settings, actions, locationMessage, overlayGranted, extras = extrasState, extrasActions = extrasActions)
        Screen.SILENCE_EXPLAIN -> SilenceExplainScreen(
            onContinue = {
                wantSilence = true
                context.startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
            },
            onCancel = { wantSilence = false; screen = Screen.SETTINGS },
        )
        Screen.BACKGROUND_EXPLAIN -> BackgroundLocationExplainScreen(
            onContinue = {
                screen = Screen.SETTINGS
                // Android 11+ sends the user to the app's settings for "Allow all the time"; Android 10 asks in place.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}")))
                } else {
                    backgroundLauncher.launch(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
                }
            },
            onCancel = { screen = Screen.SETTINGS },
        )
        Screen.OVERLAY_EXPLAIN -> OverlayExplainScreen(
            onContinue = {
                wantOverlay = true
                context.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}")))
            },
            onCancel = { screen = Screen.SETTINGS },
        )
    }
}

private fun granted(context: android.content.Context, permission: String) =
    ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
