package app.ufuq.android.ramadan

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import app.ufuq.android.R
import app.ufuq.android.settings.AppSettings
import app.ufuq.android.silence.ExtrasActions
import app.ufuq.android.ui.Section
import app.ufuq.android.ui.SwitchRow

@Composable
fun RamadanSection(settings: AppSettings, actions: ExtrasActions) {
    Section(stringResource(R.string.ramadan_title))
    SwitchRow(
        title = stringResource(R.string.ramadan_switch),
        subtitle = stringResource(R.string.ramadan_switch_hint),
        checked = settings.ramadanManual,
        onChange = actions.onRamadan,
    )
}
