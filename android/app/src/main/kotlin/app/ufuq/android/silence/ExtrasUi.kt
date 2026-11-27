package app.ufuq.android.silence

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.ufuq.android.R
import app.ufuq.android.settings.AppSettings
import app.ufuq.android.ui.SwitchRow
import app.ufuq.android.ui.Section
import app.ufuq.android.ui.Tokens
import app.ufuq.android.ui.chipColors

/** What the settings sections need to know about permissions and saved places. */
data class ExtrasState(
    val dndGranted: Boolean = false,
    val mosques: List<Mosque> = emptyList(),
    val fineLocationGranted: Boolean = false,
    val backgroundLocationGranted: Boolean = false,
    val exactAlarmsAllowed: Boolean = true,
    /** A one-line result of the last "add mosque" attempt. */
    val message: String? = null,
)

data class ExtrasActions(
    val onSilence: (Boolean) -> Unit = {},
    val onSilenceMinutes: (Int) -> Unit = {},
    val onGrantDnd: () -> Unit = {},
    val onExactAlarms: () -> Unit = {},
    val onAddMosque: (String) -> Unit = {},
    val onRemoveMosque: (Int) -> Unit = {},
    val onBackgroundLocation: () -> Unit = {},
    val onRamadan: (Boolean) -> Unit = {},
    val onFollowLocation: (Boolean) -> Unit = {},
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SilenceSection(settings: AppSettings, state: ExtrasState, actions: ExtrasActions) {
    Section(stringResource(R.string.silence_title))
    val needsAccess = settings.silenceEnabled && !state.dndGranted
    SwitchRow(
        title = stringResource(R.string.silence_switch),
        subtitle = stringResource(if (needsAccess) R.string.silence_switch_needs_access else R.string.silence_switch_hint),
        checked = settings.silenceEnabled,
        onChange = actions.onSilence,
    )
    if (needsAccess) {
        TextButton(onClick = actions.onGrantDnd, modifier = Modifier.heightIn(min = 48.dp)) {
            Text(stringResource(R.string.silence_explain_continue), color = Tokens.AccentPrayer)
        }
    }
    Text(stringResource(R.string.silence_for), color = Tokens.Secondary, fontSize = 14.sp)
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        AppSettings.SILENCE_CHOICES.forEach { minutes ->
            FilterChip(
                selected = settings.silenceMinutes == minutes,
                onClick = { actions.onSilenceMinutes(minutes) },
                label = { Text(stringResource(R.string.settings_minutes, minutes), fontSize = 15.sp) },
                colors = chipColors(),
                modifier = Modifier.heightIn(min = 48.dp),
            )
        }
    }
    if (settings.silenceEnabled && !state.exactAlarmsAllowed) {
        Text(stringResource(R.string.silence_exact_hint), color = Tokens.Warning, fontSize = 13.sp)
        TextButton(onClick = actions.onExactAlarms, modifier = Modifier.heightIn(min = 48.dp)) {
            Text(stringResource(R.string.silence_exact_button), color = Tokens.AccentPrayer)
        }
    }
}

@Composable
fun MosquesSection(state: ExtrasState, actions: ExtrasActions) {
    Section(stringResource(R.string.mosques_title))
    Text(stringResource(R.string.mosques_hint), color = Tokens.Secondary, fontSize = 13.sp)
    if (state.mosques.isEmpty()) {
        Text(stringResource(R.string.mosques_empty), color = Tokens.Muted, fontSize = 14.sp)
    } else {
        Column(Modifier.clip(RoundedCornerShape(16.dp)).background(Tokens.Card)) {
            state.mosques.forEach { m ->
                Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(start = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.mosque_row, m.name, m.radiusMeters.toInt()), color = Tokens.Primary, fontSize = 17.sp, modifier = Modifier.weight(1f))
                    val remove = stringResource(R.string.mosque_remove, m.name)
                    TextButton(onClick = { actions.onRemoveMosque(m.id) }, modifier = Modifier.heightIn(min = 48.dp).semantics { contentDescription = remove }) {
                        Text("✕", color = Tokens.Secondary, fontSize = 18.sp)
                    }
                }
            }
        }
    }
    var name by rememberSaveable { mutableStateOf("") }
    OutlinedTextField(
        value = name,
        onValueChange = { name = it.take(40) },
        label = { Text(stringResource(R.string.mosque_name)) },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
        colors = OutlinedTextFieldDefaults.colors(
            focusedTextColor = Tokens.Primary, unfocusedTextColor = Tokens.Primary,
            focusedBorderColor = Tokens.AccentPrayer, unfocusedBorderColor = Tokens.Muted,
            focusedLabelColor = Tokens.AccentPrayer, unfocusedLabelColor = Tokens.Secondary,
            cursorColor = Tokens.AccentPrayer,
        ),
    )
    Button(
        onClick = { actions.onAddMosque(name); name = "" },
        modifier = Modifier.heightIn(min = 48.dp),
        colors = ButtonDefaults.buttonColors(containerColor = Tokens.AccentPrayer, contentColor = Color.Black),
    ) { Text(stringResource(R.string.mosque_add)) }
    if (!state.fineLocationGranted) Text(stringResource(R.string.mosque_needs_location), color = Tokens.Muted, fontSize = 13.sp)
    state.message?.let { Text(it, color = Tokens.Secondary, fontSize = 14.sp) }
    if (state.mosques.isNotEmpty() && !state.backgroundLocationGranted) {
        Text(stringResource(R.string.mosque_background_title), color = Tokens.Primary, fontSize = 17.sp)
        Text(stringResource(R.string.mosque_background_hint), color = Tokens.Secondary, fontSize = 13.sp)
        TextButton(onClick = actions.onBackgroundLocation, modifier = Modifier.heightIn(min = 48.dp)) {
            Text(stringResource(R.string.mosque_background_button), color = Tokens.AccentPrayer)
        }
    }
}
