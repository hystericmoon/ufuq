package app.ufuq.android.travel

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import app.ufuq.android.R
import app.ufuq.android.settings.AppSettings
import app.ufuq.android.silence.ExtrasActions
import app.ufuq.android.ui.Section
import app.ufuq.android.ui.SwitchRow

@Composable
fun TravelSection(settings: AppSettings, actions: ExtrasActions) {
    Section(stringResource(R.string.travel_title))
    SwitchRow(
        title = stringResource(R.string.travel_switch),
        subtitle = stringResource(R.string.travel_switch_hint),
        checked = settings.followLocation,
        onChange = actions.onFollowLocation,
    )
}
