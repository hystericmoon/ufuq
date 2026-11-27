package app.ufuq.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.ufuq.android.R
import app.ufuq.android.settings.AppSettings
import app.ufuq.core.prayer.CalcMethod
import app.ufuq.core.prayer.PrayerLocation

/** The pages Home opens. */
enum class SettingsPage { LOCATION, METHOD, LEAD, SILENCE, OTHER_APPS, MAC }

/** Callbacks from Home and its sub-pages. */
data class SettingsActions(
    val onBack: () -> Unit = {},
    val onOpen: (SettingsPage) -> Unit = {},
    val onCity: (PrayerLocation) -> Unit = {},
    val onUseMyLocation: () -> Unit = {},
    val onMethod: (CalcMethod) -> Unit = {},
    val onOverlay: (Boolean) -> Unit = {},
    val onMediaAccess: () -> Unit = {},
    val onLiveUpdate: (Boolean) -> Unit = {},
    val onLead: (Int) -> Unit = {},
    val onOtherApps: (Boolean) -> Unit = {},
    val onOtherAppAllow: (String, Boolean) -> Unit = { _, _ -> },
    val onOtherAppsLearnMore: () -> Unit = {},
    val onOtherAppsGrant: () -> Unit = {},
    val onPairMac: () -> Unit = {},
    val onForgetMac: () -> Unit = {},
    val onUpdates: () -> Unit = {},
    val onRamadan: (Boolean) -> Unit = {},
    val onFollowLocation: (Boolean) -> Unit = {},
)

/**
 * Home: the app's job is to set up the island, the notification and the Mac link, so the app opens
 * on its settings. A short status card on top; prayer is one line of context, not the hero.
 */
@Composable
fun HomeScreen(
    settings: AppSettings,
    actions: SettingsActions,
    overlayPermissionGranted: Boolean,
    modifier: Modifier = Modifier,
    today: TodayState? = null,
    mediaAccessGranted: Boolean = false,
    dndGranted: Boolean = false,
    /** The paired Mac's name, or null when unpaired. */
    macName: String? = null,
    versionName: String = app.ufuq.android.BuildConfig.VERSION_NAME,
) {
    val on = stringResource(R.string.home_on)
    val off = stringResource(R.string.home_off)
    val islandNeedsPermission = settings.overlayEnabled && !overlayPermissionGranted
    Column(
        modifier
            .fillMaxSize()
            .background(Tokens.Bg)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Box(Modifier.heightIn(min = 48.dp).padding(horizontal = 4.dp), contentAlignment = Alignment.CenterStart) {
                Text(
                    stringResource(R.string.app_name),
                    color = Tokens.Primary,
                    fontSize = 26.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.semantics { heading() },
                )
            }
            StatusCard(
                next = today?.let { stringResource(R.string.home_next, it.nextName, it.nextTime, it.location) }
                    ?: stringResource(R.string.home_next_unavailable),
                warnings = listOfNotNull(
                    if (islandNeedsPermission) stringResource(R.string.home_island_needs_permission) else null,
                    if (settings.silenceEnabled && !dndGranted) stringResource(R.string.home_status_silence_needs_access) else null,
                ),
            )
        }

        SettingsGroup(
            stringResource(R.string.home_section_island),
            listOf(
                {
                    ToggleRow(
                        title = stringResource(R.string.settings_overlay),
                        subtitle = stringResource(
                            if (settings.overlayEnabled || overlayPermissionGranted) R.string.settings_overlay_hint else R.string.settings_overlay_hint_needs_permission,
                        ),
                        checked = settings.overlayEnabled,
                        onChange = actions.onOverlay,
                    )
                },
                {
                    ToggleRow(
                        title = stringResource(R.string.settings_live_update),
                        subtitle = stringResource(R.string.settings_live_update_hint),
                        checked = settings.liveUpdateEnabled,
                        onChange = actions.onLiveUpdate,
                    )
                },
                {
                    NavRow(
                        title = stringResource(R.string.settings_media),
                        value = stringResource(if (mediaAccessGranted) R.string.settings_media_on else R.string.settings_media_off),
                        onClick = actions.onMediaAccess,
                    )
                },
                {
                    NavRow(
                        title = stringResource(R.string.other_title_short),
                        value = if (settings.otherAppsEnabled) on else off,
                        onClick = { actions.onOpen(SettingsPage.OTHER_APPS) },
                    )
                },
            ),
        )

        SettingsGroup(
            stringResource(R.string.sync_settings_section),
            listOf(
                {
                    if (macName == null) {
                        NavRow(stringResource(R.string.sync_settings_pair), stringResource(R.string.sync_settings_pair_hint), actions.onPairMac)
                    } else {
                        NavRow(stringResource(R.string.sync_settings_paired, macName), stringResource(R.string.home_mac_paired_hint), { actions.onOpen(SettingsPage.MAC) })
                    }
                },
            ),
        )

        SettingsGroup(
            stringResource(R.string.home_section_prayer),
            listOf(
                { NavRow(stringResource(R.string.settings_location), settings.placeName, { actions.onOpen(SettingsPage.LOCATION) }) },
                { NavRow(stringResource(R.string.settings_method), methodName(settings.method), { actions.onOpen(SettingsPage.METHOD) }) },
                {
                    NavRow(
                        stringResource(R.string.settings_lead),
                        stringResource(R.string.settings_minutes, settings.adhanLeadMinutes),
                        { actions.onOpen(SettingsPage.LEAD) },
                    )
                },
                {
                    val needsAccess = settings.silenceEnabled && !dndGranted
                    NavRow(
                        title = stringResource(R.string.silence_title),
                        value = when {
                            needsAccess -> stringResource(R.string.home_silence_needs_access)
                            settings.silenceEnabled -> stringResource(R.string.home_silence_on, settings.silenceMinutes)
                            else -> off
                        },
                        onClick = { actions.onOpen(SettingsPage.SILENCE) },
                        valueColor = if (needsAccess) Tokens.Warning else Tokens.Secondary,
                    )
                },
                {
                    ToggleRow(
                        title = stringResource(R.string.ramadan_switch),
                        subtitle = stringResource(R.string.ramadan_switch_hint),
                        checked = settings.ramadanManual,
                        onChange = actions.onRamadan,
                    )
                },
                {
                    ToggleRow(
                        title = stringResource(R.string.travel_switch),
                        subtitle = stringResource(R.string.travel_switch_hint),
                        checked = settings.followLocation,
                        onChange = actions.onFollowLocation,
                    )
                },
            ),
        )

        SettingsGroup(
            stringResource(R.string.settings_about),
            listOf({ NavRow(stringResource(R.string.settings_updates), stringResource(R.string.update_version, versionName), actions.onUpdates) }),
        )
    }
}

/** The next prayer, then one amber line per thing that needs attention. One TalkBack node. */
@Composable
private fun StatusCard(next: String, warnings: List<String>) {
    val description = (listOf(next) + warnings).joinToString(". ")
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Tokens.Card)
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .clearAndSetSemantics { contentDescription = description },
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(next, color = Tokens.Primary, fontSize = 17.sp, modifier = Modifier.padding(vertical = 4.dp))
        warnings.forEach { Text(it, color = Tokens.Warning, fontSize = 14.sp) }
    }
}

@Composable
internal fun methodName(method: CalcMethod): String = when (method) {
    CalcMethod.KEMENAG -> stringResource(R.string.method_kemenag)
    CalcMethod.MWL -> stringResource(R.string.method_mwl)
    CalcMethod.UMM_AL_QURA -> stringResource(R.string.method_umm_al_qura)
    CalcMethod.CUSTOM -> stringResource(R.string.method_custom)
}
