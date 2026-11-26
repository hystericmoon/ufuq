package app.ufuq.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.ufuq.android.R
import app.ufuq.android.settings.AppSettings
import app.ufuq.android.settings.Cities
import app.ufuq.core.prayer.CalcMethod
import app.ufuq.android.ramadan.RamadanSection
import app.ufuq.android.silence.ExtrasActions
import app.ufuq.android.silence.ExtrasState
import app.ufuq.android.silence.MosquesSection
import app.ufuq.android.silence.SilenceSection
import app.ufuq.android.travel.TravelSection
import app.ufuq.core.prayer.PrayerLocation

/** Callbacks from the settings screen. */
data class SettingsActions(
    val onBack: () -> Unit = {},
    val onCity: (PrayerLocation) -> Unit = {},
    val onUseMyLocation: () -> Unit = {},
    val onMethod: (CalcMethod) -> Unit = {},
    val onOverlay: (Boolean) -> Unit = {},
    val onLiveUpdate: (Boolean) -> Unit = {},
    val onLead: (Int) -> Unit = {},
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SettingsScreen(
    settings: AppSettings,
    actions: SettingsActions,
    locationMessage: String?,
    overlayPermissionGranted: Boolean,
    modifier: Modifier = Modifier,
    extras: ExtrasState = ExtrasState(),
    extrasActions: ExtrasActions = ExtrasActions(),
) {
    Column(
        modifier
            .fillMaxSize()
            .background(Tokens.Bg)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = actions.onBack, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(stringResource(R.string.back), color = Tokens.AccentPrayer, fontSize = 16.sp)
            }
            Text(
                stringResource(R.string.settings_title),
                color = Tokens.Primary,
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(start = 8.dp).semantics { heading() },
            )
        }

        Section(stringResource(R.string.settings_surfaces))
        SwitchRow(
            title = stringResource(R.string.settings_live_update),
            subtitle = stringResource(R.string.settings_live_update_hint),
            checked = settings.liveUpdateEnabled,
            onChange = actions.onLiveUpdate,
        )
        SwitchRow(
            title = stringResource(R.string.settings_overlay),
            subtitle = stringResource(
                if (settings.overlayEnabled || overlayPermissionGranted) R.string.settings_overlay_hint else R.string.settings_overlay_hint_needs_permission,
            ),
            checked = settings.overlayEnabled,
            onChange = actions.onOverlay,
        )

        Section(stringResource(R.string.settings_location))
        Button(
            onClick = actions.onUseMyLocation,
            modifier = Modifier.heightIn(min = 48.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Tokens.AccentPrayer, contentColor = androidx.compose.ui.graphics.Color.Black),
        ) { Text(stringResource(R.string.settings_use_my_location)) }
        if (locationMessage != null) Text(locationMessage, color = Tokens.Secondary, fontSize = 14.sp)
        if (settings.usesDeviceLocation) {
            CityRow(settings.cityName, selected = true, onClick = {})
        }
        Column(Modifier.clip(RoundedCornerShape(16.dp)).background(Tokens.Card)) {
            Cities.ALL.forEach { city ->
                CityRow(city.name, selected = !settings.usesDeviceLocation && settings.cityName == city.name) { actions.onCity(city) }
            }
        }

        Section(stringResource(R.string.settings_method))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AppSettings.METHODS.forEach { method ->
                FilterChip(
                    selected = settings.method == method,
                    onClick = { actions.onMethod(method) },
                    label = { Text(methodName(method), fontSize = 15.sp) },
                    colors = chipColors(),
                    modifier = Modifier.heightIn(min = 48.dp),
                )
            }
        }

        Section(stringResource(R.string.settings_lead))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AppSettings.LEAD_CHOICES.forEach { minutes ->
                FilterChip(
                    selected = settings.adhanLeadMinutes == minutes,
                    onClick = { actions.onLead(minutes) },
                    label = { Text(stringResource(R.string.settings_minutes, minutes), fontSize = 15.sp) },
                    colors = chipColors(),
                    modifier = Modifier.heightIn(min = 48.dp),
                )
            }
        }
        Text(stringResource(R.string.settings_lead_hint), color = Tokens.Muted, fontSize = 13.sp)

        SilenceSection(settings, extras, extrasActions)
        MosquesSection(extras, extrasActions)
        RamadanSection(settings, extrasActions)
        TravelSection(settings, extrasActions)
    }
}

@Composable
internal fun chipColors() = FilterChipDefaults.filterChipColors(
    selectedContainerColor = Tokens.Track,
    selectedLabelColor = Tokens.AccentPrayer,
    labelColor = Tokens.Primary,
    containerColor = Tokens.Card,
)

@Composable
private fun methodName(method: CalcMethod): String = when (method) {
    CalcMethod.KEMENAG -> stringResource(R.string.method_kemenag)
    CalcMethod.MWL -> stringResource(R.string.method_mwl)
    CalcMethod.UMM_AL_QURA -> stringResource(R.string.method_umm_al_qura)
    CalcMethod.CUSTOM -> stringResource(R.string.method_custom)
}

@Composable
internal fun Section(title: String) {
    Text(
        title,
        color = Tokens.Secondary,
        fontSize = 14.sp,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(top = 12.dp).semantics { heading() },
    )
}

@Composable
internal fun SwitchRow(title: String, subtitle: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Tokens.Card)
            .toggleable(value = checked, role = Role.Switch, onValueChange = onChange)
            .heightIn(min = 64.dp)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, color = Tokens.Primary, fontSize = 17.sp)
            Text(subtitle, color = Tokens.Secondary, fontSize = 13.sp)
        }
        Switch(
            checked = checked,
            onCheckedChange = null,
            colors = SwitchDefaults.colors(
                checkedTrackColor = Tokens.AccentPrayer,
                checkedThumbColor = androidx.compose.ui.graphics.Color.Black,
                uncheckedTrackColor = Tokens.Track,
                uncheckedThumbColor = Tokens.Secondary,
                uncheckedBorderColor = Tokens.Muted,
            ),
        )
    }
}

@Composable
private fun CityRow(name: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
            .heightIn(min = 48.dp)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(name, color = Tokens.Primary, fontSize = 17.sp, modifier = Modifier.weight(1f))
        RadioButton(selected = selected, onClick = null)
    }
}
