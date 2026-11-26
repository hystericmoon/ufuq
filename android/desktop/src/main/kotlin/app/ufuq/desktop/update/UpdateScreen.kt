package app.ufuq.desktop.update

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/** The one sentence a screen reader announces for [state]. */
fun updateStatusText(state: UpdateState, currentVersion: String): String = when (state) {
    UpdateState.Disabled -> UPDATES_OFF_MESSAGE
    UpdateState.Idle -> "Ufuq $currentVersion"
    UpdateState.Checking -> "Checking for updates"
    is UpdateState.UpToDate -> "Ufuq is up to date (${state.version})"
    is UpdateState.Available -> "Ufuq ${state.update.version} is available. You have $currentVersion."
    is UpdateState.Downloading -> "Downloading Ufuq ${state.update.version}, ${downloadPercent(state)} percent"
    is UpdateState.Verifying -> "Verifying the download"
    is UpdateState.Ready -> "Ufuq ${state.update.version} is ready. Restart to update."
    is UpdateState.Failed -> state.message
}

/** 0..100, or 0 while the size is unknown. */
fun downloadPercent(s: UpdateState.Downloading): Int =
    if (s.total > 0) (s.done * 100 / s.total).toInt().coerceIn(0, 100) else 0

/**
 * The update window. One live-region status line, a progress bar with a range for screen readers,
 * and plain buttons, so Tab / Space / Enter work and Narrator reads every step.
 */
@Composable
fun UpdateScreen(
    state: UpdateState,
    currentVersion: String,
    onCheck: () -> Unit,
    onDownload: () -> Unit,
    onRestart: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    MaterialTheme(colorScheme = if (isSystemInDarkTheme()) darkColorScheme() else lightColorScheme()) {
        Surface(modifier.fillMaxSize()) {
            Column(Modifier.verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Ufuq updates", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
                Text(
                    updateStatusText(state, currentVersion),
                    modifier = Modifier.fillMaxWidth().semantics { liveRegion = LiveRegionMode.Polite },
                )
                if (state is UpdateState.Downloading) {
                    val pct = downloadPercent(state)
                    LinearProgressIndicator(
                        progress = { pct / 100f },
                        modifier = Modifier.fillMaxWidth().semantics {
                            contentDescription = "Download progress"
                            progressBarRangeInfo = ProgressBarRangeInfo(pct / 100f, 0f..1f)
                        },
                    )
                }
                if (state is UpdateState.Available && state.update.notes.isNotBlank()) {
                    Text("What's new", style = MaterialTheme.typography.titleSmall, modifier = Modifier.semantics { heading() })
                    Text(state.update.notes, style = MaterialTheme.typography.bodySmall)
                }
                val primary = remember { FocusRequester() }
                // The main button of each step takes focus, so Enter does the obvious thing.
                LaunchedEffect(state::class) { runCatching { primary.requestFocus() } }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    when (state) {
                        is UpdateState.Available -> {
                            Button(onClick = onDownload, modifier = Modifier.focusRequester(primary)) { Text("Download and verify") }
                        }
                        is UpdateState.Ready -> {
                            Button(onClick = onRestart, modifier = Modifier.focusRequester(primary)) { Text("Restart to update") }
                        }
                        is UpdateState.Failed -> {
                            Button(onClick = if (state.update != null) onDownload else onCheck, modifier = Modifier.focusRequester(primary)) { Text("Try again") }
                        }
                        is UpdateState.Idle, is UpdateState.UpToDate -> {
                            Button(onClick = onCheck, modifier = Modifier.focusRequester(primary)) { Text("Check for updates") }
                        }
                        else -> Unit
                    }
                    if (state !is UpdateState.Downloading && state !is UpdateState.Verifying) {
                        OutlinedButton(onClick = onClose) { Text(if (state is UpdateState.Ready) "Later" else "Close") }
                    }
                }
            }
        }
    }
}

/** Auto-check is due when it is on, updates are enabled, and the last check was 24 hours ago or more. */
fun autoCheckDue(enabled: Boolean, updatesEnabled: Boolean, lastCheckMillis: Long, nowMillis: Long): Boolean =
    enabled && updatesEnabled && (lastCheckMillis <= 0 || nowMillis - lastCheckMillis >= 24L * 60 * 60 * 1000 || lastCheckMillis > nowMillis)
