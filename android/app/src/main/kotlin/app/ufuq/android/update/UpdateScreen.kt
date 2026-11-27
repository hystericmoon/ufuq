package app.ufuq.android.update

import android.text.format.DateUtils
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.ufuq.android.BuildConfig
import app.ufuq.android.R
import app.ufuq.android.ui.SwitchRow
import app.ufuq.android.ui.Tokens

data class UpdateActions(
    val onBack: () -> Unit = {},
    val onCheck: () -> Unit = {},
    val onDownload: () -> Unit = {},
    val onInstall: () -> Unit = {},
    val onAutoCheck: (Boolean) -> Unit = {},
    val onBetaChannel: (Boolean) -> Unit = {},
)

/** Settings → Updates. [nowMillis] and [versionName] are parameters so screenshots stay stable. */
@Composable
fun UpdateScreen(
    state: UpdateUiState,
    actions: UpdateActions,
    modifier: Modifier = Modifier,
    nowMillis: Long = System.currentTimeMillis(),
    versionName: String = BuildConfig.VERSION_NAME,
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
                stringResource(R.string.update_title),
                color = Tokens.Primary,
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(start = 8.dp).semantics { heading() },
            )
        }
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Tokens.Card).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(stringResource(R.string.update_version, versionName), color = Tokens.Primary, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            if (!state.enabled) {
                Text(stringResource(R.string.update_off_dev), color = Tokens.Secondary, fontSize = 15.sp)
            } else {
                Text(lastCheckedLabel(state.lastCheckMillis, nowMillis), color = Tokens.Secondary, fontSize = 14.sp)
                StatusBlock(state.status, actions)
            }
        }
        if (state.enabled) {
            SwitchRow(
                title = stringResource(R.string.update_auto),
                subtitle = stringResource(R.string.update_auto_hint),
                checked = state.autoCheck,
                onChange = actions.onAutoCheck,
            )
            SwitchRow(
                title = stringResource(R.string.update_beta),
                subtitle = stringResource(R.string.update_beta_hint),
                checked = state.betaChannel,
                onChange = actions.onBetaChannel,
            )
        }
        Text(stringResource(R.string.update_privacy), color = Tokens.Muted, fontSize = 13.sp, modifier = Modifier.padding(top = 4.dp))
    }
}

@Composable
private fun lastCheckedLabel(millis: Long, now: Long): String =
    if (millis <= 0L) {
        stringResource(R.string.update_never_checked)
    } else {
        stringResource(R.string.update_last_checked, DateUtils.getRelativeTimeSpanString(millis, now, DateUtils.MINUTE_IN_MILLIS).toString())
    }

/** Status text and the one action that fits it; read out by TalkBack when it changes. */
@Composable
private fun StatusBlock(status: UpdateStatus, actions: UpdateActions) {
    AnimatedContent(
        targetState = status,
        contentKey = { it::class },
        transitionSpec = { fadeIn(tween(180)) togetherWith fadeOut(tween(120)) },
        modifier = Modifier.fillMaxWidth().semantics { liveRegion = LiveRegionMode.Polite },
        label = "updateStatus",
    ) { s ->
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            when (s) {
                UpdateStatus.Idle -> PrimaryButton(stringResource(R.string.update_check), actions.onCheck)
                UpdateStatus.Checking -> {
                    Body(stringResource(R.string.update_checking))
                    LinearProgressIndicator(Modifier.fillMaxWidth(), color = Tokens.AccentPrayer, trackColor = Tokens.Track)
                }
                UpdateStatus.UpToDate -> {
                    Body(stringResource(R.string.update_up_to_date))
                    SecondaryButton(stringResource(R.string.update_check), actions.onCheck)
                }
                is UpdateStatus.Available -> {
                    Body(stringResource(R.string.update_available, s.update.version))
                    ReleaseNotes(s.update.notes)
                    PrimaryButton(stringResource(R.string.update_download), actions.onDownload)
                }
                is UpdateStatus.Downloading -> DownloadProgress(s.progress)
                is UpdateStatus.Ready -> {
                    Body(stringResource(R.string.update_ready, s.update.version))
                    PrimaryButton(stringResource(R.string.update_install), actions.onInstall)
                }
                is UpdateStatus.Failed -> {
                    Body(stringResource(R.string.update_failed), Tokens.Critical)
                    SecondaryButton(stringResource(R.string.update_retry), if (s.update != null) actions.onDownload else actions.onCheck)
                }
            }
        }
    }
}

@Composable
private fun Body(text: String, color: Color = Tokens.Primary) = Text(text, color = color, fontSize = 16.sp)

@Composable
private fun PrimaryButton(label: String, onClick: () -> Unit) = Button(
    onClick = onClick,
    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
    colors = ButtonDefaults.buttonColors(containerColor = Tokens.AccentPrayer, contentColor = Color.Black),
) { Text(label) }

@Composable
private fun SecondaryButton(label: String, onClick: () -> Unit) = OutlinedButton(
    onClick = onClick,
    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
) { Text(label, color = Tokens.AccentPrayer) }

@Composable
private fun DownloadProgress(progress: Float) {
    Body(if (progress >= 0f) stringResource(R.string.update_downloading_percent, (progress * 100).toInt()) else stringResource(R.string.update_downloading))
    if (progress >= 0f) {
        LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth(), color = Tokens.AccentPrayer, trackColor = Tokens.Track)
    } else {
        LinearProgressIndicator(Modifier.fillMaxWidth(), color = Tokens.AccentPrayer, trackColor = Tokens.Track)
    }
}

@Composable
private fun ReleaseNotes(notes: String) {
    if (notes.isBlank()) return
    Text(
        notes,
        color = Tokens.Secondary,
        fontSize = 14.sp,
        modifier = Modifier.heightIn(max = 240.dp).verticalScroll(rememberScrollState()),
    )
}

/** Shown on start when the daily check finds a newer version. */
@Composable
fun UpdatePromptDialog(state: UpdateUiState, actions: UpdateActions, onDismiss: () -> Unit) {
    val status = state.status
    val update = when (status) {
        is UpdateStatus.Available -> status.update
        is UpdateStatus.Downloading -> status.update
        is UpdateStatus.Ready -> status.update
        is UpdateStatus.Failed -> status.update
        else -> null
    } ?: return
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Tokens.Card,
        titleContentColor = Tokens.Primary,
        textContentColor = Tokens.Secondary,
        title = { Text(stringResource(R.string.update_available, update.version)) },
        text = {
            Column(Modifier.semantics { liveRegion = LiveRegionMode.Polite }, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                when (status) {
                    is UpdateStatus.Downloading -> DownloadProgress(status.progress)
                    is UpdateStatus.Failed -> Body(stringResource(R.string.update_failed), Tokens.Critical)
                    is UpdateStatus.Ready -> Body(stringResource(R.string.update_ready, update.version))
                    else -> ReleaseNotes(update.notes.ifBlank { stringResource(R.string.update_prompt_body) })
                }
            }
        },
        confirmButton = {
            val (label, onClick) = when (status) {
                is UpdateStatus.Ready -> stringResource(R.string.update_install) to actions.onInstall
                is UpdateStatus.Downloading -> return@AlertDialog
                is UpdateStatus.Failed -> stringResource(R.string.update_retry) to actions.onDownload
                else -> stringResource(R.string.update_download) to actions.onDownload
            }
            TextButton(onClick = onClick, modifier = Modifier.heightIn(min = 48.dp)) { Text(label, color = Tokens.AccentPrayer) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, modifier = Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.update_later), color = Tokens.AccentPrayer) }
        },
    )
}
