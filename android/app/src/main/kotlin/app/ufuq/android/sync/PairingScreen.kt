package app.ufuq.android.sync

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.ufuq.android.R
import app.ufuq.android.ui.Tokens

enum class PairingError { INVALID, UNSUPPORTED }

data class PairingUiState(
    val cameraGranted: Boolean = false,
    /** The user said no to the camera: say so, and point at the paste field. */
    val cameraDenied: Boolean = false,
    val scanning: Boolean = false,
    val code: String = "",
    val error: PairingError? = null,
    /** Set once pairing worked; the screen then shows the "Paired" card. */
    val pairedName: String? = null,
)

data class PairingActions(
    val onBack: () -> Unit = {},
    val onScan: () -> Unit = {},
    val onStopScan: () -> Unit = {},
    val onCodeChange: (String) -> Unit = {},
    val onPasteFromClipboard: () -> Unit = {},
    val onSubmit: () -> Unit = {},
    val onDone: () -> Unit = {},
)

/** "Pair with your Mac". [camera] draws the live preview while [PairingUiState.scanning]; the paste field is the no-camera path. */
@Composable
fun PairingScreen(
    state: PairingUiState,
    actions: PairingActions,
    modifier: Modifier = Modifier,
    camera: @Composable (Modifier) -> Unit = {},
) {
    Column(
        modifier
            .fillMaxSize()
            .background(Tokens.Bg)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = actions.onBack, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(stringResource(R.string.back), color = Tokens.AccentPrayer, fontSize = 16.sp)
            }
            Text(
                stringResource(R.string.pair_title),
                color = Tokens.Primary,
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(start = 8.dp).semantics { heading() },
            )
        }
        if (state.pairedName != null) PairedCard(state.pairedName, actions.onDone) else PairingForm(state, actions, camera)
    }
}

@Composable
private fun PairingForm(state: PairingUiState, actions: PairingActions, camera: @Composable (Modifier) -> Unit) {
    Text(stringResource(R.string.pair_intro), color = Tokens.Primary, fontSize = 17.sp)

    Heading(stringResource(R.string.pair_step_scan))
    if (state.scanning) {
        camera(Modifier.fillMaxWidth().heightIn(min = 280.dp).clip(RoundedCornerShape(16.dp)).background(Tokens.Card))
        OutlinedButton(onClick = actions.onStopScan, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
            Text(stringResource(R.string.pair_camera_stop), color = Tokens.AccentPrayer)
        }
    } else {
        if (!state.cameraGranted) Text(stringResource(R.string.pair_camera_why), color = Tokens.Secondary, fontSize = 15.sp)
        if (state.cameraDenied) {
            Text(stringResource(R.string.pair_camera_denied), color = Tokens.Warning, fontSize = 15.sp)
        }
        Button(
            onClick = actions.onScan,
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Tokens.AccentPrayer, contentColor = Color.Black),
        ) { Text(stringResource(if (state.cameraGranted) R.string.pair_scan_button else R.string.pair_camera_allow)) }
    }

    Heading(stringResource(R.string.pair_step_paste))
    Text(stringResource(R.string.pair_paste_hint), color = Tokens.Secondary, fontSize = 15.sp)
    OutlinedTextField(
        value = state.code,
        onValueChange = actions.onCodeChange,
        label = { Text(stringResource(R.string.pair_paste_label)) },
        isError = state.error != null,
        minLines = 2,
        maxLines = 4,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false),
        colors = OutlinedTextFieldDefaults.colors(
            focusedTextColor = Tokens.Primary,
            unfocusedTextColor = Tokens.Primary,
            focusedBorderColor = Tokens.AccentPrayer,
            unfocusedBorderColor = Tokens.Muted,
            focusedLabelColor = Tokens.AccentPrayer,
            unfocusedLabelColor = Tokens.Secondary,
            cursorColor = Tokens.AccentPrayer,
        ),
        modifier = Modifier.fillMaxWidth(),
    )
    state.error?.let {
        Text(
            stringResource(if (it == PairingError.UNSUPPORTED) R.string.pair_error_unsupported else R.string.pair_error_invalid),
            color = Tokens.Critical,
            fontSize = 15.sp,
            modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
        )
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedButton(onClick = actions.onPasteFromClipboard, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) {
            Text(stringResource(R.string.pair_paste_from_clipboard), color = Tokens.AccentPrayer)
        }
        Button(
            onClick = actions.onSubmit,
            enabled = state.code.isNotBlank(),
            modifier = Modifier.weight(1f).heightIn(min = 48.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Tokens.AccentPrayer, contentColor = Color.Black),
        ) { Text(stringResource(R.string.pair_paste_button)) }
    }
}

@Composable
private fun PairedCard(name: String, onDone: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Tokens.Card).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            stringResource(R.string.pair_done_title, name),
            color = Tokens.Primary,
            fontSize = 20.sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.semantics { heading(); liveRegion = LiveRegionMode.Polite },
        )
        Text(stringResource(R.string.pair_done_hint), color = Tokens.Secondary, fontSize = 16.sp)
    }
    Button(
        onClick = onDone,
        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
        colors = ButtonDefaults.buttonColors(containerColor = Tokens.AccentPrayer, contentColor = Color.Black),
    ) { Text(stringResource(R.string.pair_done_button)) }
}

@Composable
private fun Heading(text: String) {
    Text(
        text,
        color = Tokens.Secondary,
        fontSize = 14.sp,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(top = 8.dp).semantics { heading() },
    )
}

/** The Settings section: pair, or show the paired Mac with "Forget this Mac". */
@Composable
fun MacSyncSection(macName: String?, onPair: () -> Unit, onForget: () -> Unit) {
    Heading(stringResource(R.string.sync_settings_section))
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Tokens.Card).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (macName == null) {
            Text(stringResource(R.string.sync_settings_pair_hint), color = Tokens.Secondary, fontSize = 15.sp)
            Button(
                onClick = onPair,
                modifier = Modifier.heightIn(min = 48.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Tokens.AccentPrayer, contentColor = Color.Black),
            ) { Text(stringResource(R.string.sync_settings_pair)) }
        } else {
            Text(stringResource(R.string.sync_settings_paired, macName), color = Tokens.Primary, fontSize = 17.sp)
            OutlinedButton(onClick = onForget, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(stringResource(R.string.sync_settings_forget), color = Tokens.Critical)
            }
        }
    }
}
