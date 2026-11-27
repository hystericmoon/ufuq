package app.ufuq.android.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.ufuq.android.R
import app.ufuq.android.activities.SeenApp
import app.ufuq.android.settings.AppSettings
import app.ufuq.android.settings.Cities
import app.ufuq.android.silence.ExtrasActions
import app.ufuq.android.silence.ExtrasState
import app.ufuq.android.silence.MosquesSection
import app.ufuq.android.silence.SilenceSection
import app.ufuq.android.sync.MacSyncSection

/** Location: "Use my location", then the city list as one card of radio rows. */
@Composable
fun LocationScreen(settings: AppSettings, actions: SettingsActions, locationMessage: String?, modifier: Modifier = Modifier) {
    SubScreen(stringResource(R.string.settings_location), actions.onBack, modifier) {
        Column {
            Button(
                onClick = actions.onUseMyLocation,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Tokens.AccentPrayer, contentColor = Color.Black),
            ) { Text(stringResource(R.string.settings_use_my_location), fontSize = 16.sp) }
            if (locationMessage != null) {
                Text(
                    locationMessage,
                    color = Tokens.Secondary,
                    fontSize = 14.sp,
                    modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp).semantics { liveRegion = LiveRegionMode.Polite },
                )
            }
        }
        val rows = buildList<@Composable () -> Unit> {
            if (settings.usesDeviceLocation) add { RadioRow(settings.placeName, selected = true, onClick = {}) }
            Cities.ALL.forEach { city ->
                add { RadioRow(city.name, selected = !settings.usesDeviceLocation && settings.cityName == city.name) { actions.onCity(city) } }
            }
        }
        SettingsCard(rows)
    }
}

@Composable
fun MethodScreen(settings: AppSettings, actions: SettingsActions, modifier: Modifier = Modifier) {
    SubScreen(stringResource(R.string.settings_method), actions.onBack, modifier) {
        SettingsCard(AppSettings.METHODS.map<app.ufuq.core.prayer.CalcMethod, @Composable () -> Unit> { method -> { RadioRow(methodName(method), settings.method == method) { actions.onMethod(method) } } })
    }
}

@Composable
fun LeadScreen(settings: AppSettings, actions: SettingsActions, modifier: Modifier = Modifier) {
    SubScreen(stringResource(R.string.settings_lead), actions.onBack, modifier) {
        Column {
            SettingsCard(
                AppSettings.LEAD_CHOICES.map<Int, @Composable () -> Unit> { minutes ->
                    { RadioRow(stringResource(R.string.settings_minutes, minutes), settings.adhanLeadMinutes == minutes) { actions.onLead(minutes) } }
                },
            )
            Column(Modifier.padding(top = 8.dp)) { Footnote(stringResource(R.string.settings_lead_hint)) }
        }
    }
}

/** Silence at prayer: the timed silence after the adhan, and saved mosques. */
@Composable
fun SilencePage(settings: AppSettings, extras: ExtrasState, extrasActions: ExtrasActions, onBack: () -> Unit, modifier: Modifier = Modifier) {
    SubScreen(stringResource(R.string.silence_title), onBack, modifier, spacing = 12.dp) {
        SilenceSection(settings, extras, extrasActions)
        MosquesSection(extras, extrasActions)
    }
}

@Composable
fun OtherAppsPage(settings: AppSettings, actions: SettingsActions, accessGranted: Boolean, apps: List<SeenApp>, modifier: Modifier = Modifier) {
    SubScreen(stringResource(R.string.other_title_short), actions.onBack, modifier) {
        OtherAppsSection(
            enabled = settings.otherAppsEnabled,
            accessGranted = accessGranted,
            apps = apps,
            allowed = settings.otherAppsAllowed,
            onToggle = actions.onOtherApps,
            onAllow = actions.onOtherAppAllow,
            onLearnMore = actions.onOtherAppsLearnMore,
            onGrantAccess = actions.onOtherAppsGrant,
        )
    }
}

@Composable
fun MacPage(macName: String?, actions: SettingsActions, modifier: Modifier = Modifier) {
    SubScreen(stringResource(R.string.sync_settings_section), actions.onBack, modifier) {
        MacSyncSection(macName, onPair = actions.onPairMac, onForget = actions.onForgetMac)
    }
}
