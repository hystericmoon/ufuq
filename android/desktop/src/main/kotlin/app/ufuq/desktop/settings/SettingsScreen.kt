package app.ufuq.desktop.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.ufuq.core.prayer.CalcMethod

private fun methodName(m: CalcMethod) = when (m) {
    CalcMethod.KEMENAG -> "Kemenag (default)"
    CalcMethod.MWL -> "Muslim World League"
    CalcMethod.UMM_AL_QURA -> "Umm al-Qura"
    CalcMethod.CUSTOM -> "Custom"
}

@Composable
private fun SectionTitle(text: String) {
    Text(text, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 16.dp, bottom = 4.dp))
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, enabled: Boolean = true, note: String? = null, onChange: (Boolean) -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 40.dp).toggleable(value = checked, enabled = enabled, role = Role.Switch, onValueChange = onChange),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(label)
            Switch(checked = checked, onCheckedChange = null, enabled = enabled)
        }
        if (note != null) Text(note, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/**
 * The settings window: location (the same 12 cities as Android), method (Kemenag by default),
 * Claude config folders (one per account), the usage estimate budgets, launch at login, reduce motion.
 */
@Composable
fun SettingsScreen(
    settings: DesktopSettings,
    onChange: (DesktopSettings) -> Unit,
    launchAtLoginSupported: Boolean,
    effectiveReduceMotion: Boolean,
    modifier: Modifier = Modifier,
    /** Null in development builds without an update key: the update switches are disabled with a note. */
    updatesEnabled: Boolean = true,
    onCheckForUpdates: () -> Unit = {},
) {
    MaterialTheme(colorScheme = if (isSystemInDarkTheme()) darkColorScheme() else lightColorScheme()) {
        Surface(modifier.fillMaxSize()) {
            Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 16.dp)) {
                Text("Ufuq settings", style = MaterialTheme.typography.headlineSmall)

                SectionTitle("Prayer times")
                var cityMenu by remember { mutableStateOf(false) }
                Box {
                    OutlinedButton(onClick = { cityMenu = true }, modifier = Modifier.semantics { contentDescription = "City, ${settings.cityName}" }) {
                        Text("City: ${settings.cityName}")
                    }
                    DropdownMenu(expanded = cityMenu, onDismissRequest = { cityMenu = false }) {
                        Cities.ALL.forEach { city ->
                            DropdownMenuItem(text = { Text(city.name) }, onClick = { cityMenu = false; onChange(settings.copy(cityName = city.name)) })
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
                Column(Modifier.semantics { contentDescription = "Calculation method" }) {
                    DesktopSettings.METHODS.forEach { m ->
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 36.dp).selectable(selected = settings.method == m, role = Role.RadioButton) { onChange(settings.copy(method = m)) },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            RadioButton(selected = settings.method == m, onClick = null)
                            Text(methodName(m), Modifier.padding(start = 8.dp))
                        }
                    }
                }

                HorizontalDivider(Modifier.padding(top = 12.dp))
                SectionTitle("Claude accounts")
                Text(
                    "Folders to read, one per account. Empty means ${app.ufuq.core.usage.ClaudeLogParser.defaultConfigDir()}. Codex is read from the .codex folder in your user profile.",
                    style = MaterialTheme.typography.bodySmall,
                )
                settings.claudeDirs.forEach { dir ->
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(dir, Modifier.weight(1f), maxLines = 1)
                        TextButton(onClick = { onChange(settings.copy(claudeDirs = settings.claudeDirs - dir)) }, modifier = Modifier.semantics { contentDescription = "Remove $dir" }) { Text("Remove") }
                    }
                }
                var newDir by remember { mutableStateOf("") }
                Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(newDir, { newDir = it }, label = { Text("Add a Claude folder") }, singleLine = true, modifier = Modifier.weight(1f))
                    Button(
                        onClick = { onChange(settings.copy(claudeDirs = (settings.claudeDirs + newDir.trim()).distinct())); newDir = "" },
                        enabled = newDir.isNotBlank(),
                    ) { Text("Add") }
                }

                HorizontalDivider(Modifier.padding(top = 12.dp))
                SectionTitle("General")
                SwitchRow(
                    "Launch at login",
                    settings.launchAtLogin,
                    enabled = launchAtLoginSupported,
                    note = if (launchAtLoginSupported) null else "Available in the installed app on Windows.",
                ) { onChange(settings.copy(launchAtLogin = it)) }
                SwitchRow(
                    "Reduce motion",
                    effectiveReduceMotion,
                    note = "Cross-fade instead of the morph. Starts from Windows Animation effects.",
                ) { onChange(settings.copy(reduceMotion = it)) }
                SectionTitle("Updates")
                SwitchRow(
                    "Check for updates automatically",
                    settings.autoCheckUpdates,
                    enabled = updatesEnabled,
                    note = if (updatesEnabled) "Ufuq checks GitHub once a day for a new version." else "Updates are off in development builds",
                ) { onChange(settings.copy(autoCheckUpdates = it)) }
                SwitchRow(
                    "Include beta versions",
                    settings.betaUpdates,
                    enabled = updatesEnabled,
                    note = "Pre-releases may be less stable.",
                ) { onChange(settings.copy(betaUpdates = it)) }
                OutlinedButton(onClick = onCheckForUpdates, enabled = updatesEnabled) { Text("Check for updates now") }
                Spacer(Modifier.height(8.dp))
                Text("Open the island with Win+Alt+Space. Esc closes it.", style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}
