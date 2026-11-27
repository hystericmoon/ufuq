package app.ufuq.android.ui

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
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.ufuq.android.R
import app.ufuq.android.activities.SeenApp

/**
 * "Other apps in the island (Beta)": off by default. Turning it on goes through the explanation
 * screen first; once on, the user picks which apps may show (only apps that posted a qualifying
 * notification this session are listed).
 */
@Composable
fun OtherAppsSection(
    enabled: Boolean,
    accessGranted: Boolean,
    apps: List<SeenApp>,
    allowed: Set<String>,
    onToggle: (Boolean) -> Unit,
    onAllow: (String, Boolean) -> Unit,
    onLearnMore: () -> Unit,
    onGrantAccess: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SwitchRow(
            title = stringResource(R.string.other_switch),
            subtitle = stringResource(if (enabled) R.string.other_switch_on_hint else R.string.other_switch_hint),
            checked = enabled,
            onChange = onToggle,
        )
        TextButton(onClick = onLearnMore, modifier = Modifier.heightIn(min = 48.dp)) {
            Text(stringResource(R.string.other_learn_more), color = Tokens.AccentPrayer, fontSize = 15.sp)
        }
        if (enabled) {
            if (!accessGranted) {
                Text(stringResource(R.string.other_needs_access), color = Tokens.Warning, fontSize = 14.sp)
                Button(
                    onClick = onGrantAccess,
                    modifier = Modifier.heightIn(min = 48.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Tokens.AccentPrayer, contentColor = Color.Black),
                ) { Text(stringResource(R.string.other_grant)) }
            }
            Text(stringResource(R.string.other_apps_heading), color = Tokens.Secondary, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            if (apps.isEmpty()) {
                Text(stringResource(R.string.other_apps_empty), color = Tokens.Muted, fontSize = 14.sp)
            } else {
                Column(Modifier.clip(RoundedCornerShape(16.dp)).background(Tokens.Card)) {
                    apps.forEach { app ->
                        val on = app.packageName in allowed
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .toggleable(value = on, role = Role.Checkbox, onValueChange = { onAllow(app.packageName, it) })
                                .heightIn(min = 48.dp)
                                .padding(horizontal = 16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(app.label, color = Tokens.Primary, fontSize = 17.sp, modifier = Modifier.weight(1f))
                            Checkbox(checked = on, onCheckedChange = null)
                        }
                    }
                }
            }
        }
    }
}

/** What is read and what is not, before the notification-access screen. */
@Composable
fun OtherAppsExplainScreen(accessGranted: Boolean, onContinue: () -> Unit, onCancel: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier
            .fillMaxSize()
            .background(Tokens.Bg)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            stringResource(R.string.other_title),
            color = Tokens.Primary,
            fontSize = 26.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.semantics { heading() },
        )
        Text(stringResource(R.string.other_beta), color = Tokens.Warning, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
        Text(stringResource(R.string.other_read), color = Tokens.Primary, fontSize = 17.sp)
        Text(stringResource(R.string.other_not_read), color = Tokens.Secondary, fontSize = 16.sp)
        Text(stringResource(R.string.other_stored), color = Tokens.Secondary, fontSize = 16.sp)
        Text(stringResource(R.string.other_choose), color = Tokens.Secondary, fontSize = 16.sp)
        Button(
            onClick = onContinue,
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Tokens.AccentPrayer, contentColor = Color.Black),
        ) { Text(stringResource(if (accessGranted) R.string.other_turn_on else R.string.other_continue)) }
        TextButton(onClick = onCancel, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
            Text(stringResource(R.string.overlay_cancel), color = Tokens.AccentPrayer)
        }
    }
}
