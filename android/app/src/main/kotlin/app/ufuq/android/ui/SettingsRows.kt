package app.ufuq.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.ufuq.android.R

/*
 * Building blocks of the settings pages: a section is a small heading over ONE rounded card, and the
 * card's rows are split by 1 dp inset dividers. Rows are 56 dp (64 dp with a second line), and the
 * whole row is the touch target.
 */

private val CardShape = RoundedCornerShape(16.dp)

/** A grouped section: heading, 8 dp, then one card holding [rows] with dividers between them. */
@Composable
internal fun SettingsGroup(title: String, rows: List<@Composable () -> Unit>) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        GroupHeading(title)
        SettingsCard(rows)
    }
}

@Composable
internal fun GroupHeading(title: String) {
    Text(
        title,
        color = Tokens.Secondary,
        fontSize = 14.sp,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(horizontal = 4.dp).semantics { heading() },
    )
}

@Composable
internal fun SettingsCard(rows: List<@Composable () -> Unit>) {
    Column(Modifier.fillMaxWidth().clip(CardShape).background(Tokens.Card)) {
        rows.forEachIndexed { i, row ->
            if (i > 0) RowDivider()
            row()
        }
    }
}

@Composable
private fun RowDivider() {
    Box(Modifier.padding(start = 16.dp).fillMaxWidth().height(1.dp).background(Tokens.Track))
}

private fun minHeight(subtitle: String?): Dp = if (subtitle.isNullOrEmpty()) 56.dp else 64.dp

@Composable
private fun RowTexts(title: String, subtitle: String?, subtitleColor: Color, modifier: Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(title, color = Tokens.Primary, fontSize = 17.sp, lineHeight = 22.sp)
        if (!subtitle.isNullOrEmpty()) Text(subtitle, color = subtitleColor, fontSize = 14.sp, lineHeight = 19.sp)
    }
}

/**
 * A row that opens a page. TalkBack reads "Title, value, button"; the chevron is decorative.
 */
@Composable
internal fun NavRow(title: String, value: String?, onClick: () -> Unit, valueColor: Color = Tokens.Secondary) {
    val description = if (value.isNullOrEmpty()) title else "$title, $value"
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = description }
            .heightIn(min = minHeight(value))
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        RowTexts(title, value, valueColor, Modifier.weight(1f).clearAndSetSemantics { })
        Chevron()
    }
}

@Composable
private fun Chevron() {
    Text("›", color = Tokens.Secondary, fontSize = 24.sp, modifier = Modifier.clearAndSetSemantics { })
}

/** A switch row inside a card: the whole row toggles, and TalkBack hears one switch. */
@Composable
internal fun ToggleRow(title: String, subtitle: String?, checked: Boolean, onChange: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier
            .fillMaxWidth()
            .toggleable(value = checked, role = Role.Switch, onValueChange = onChange)
            .heightIn(min = minHeight(subtitle))
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        RowTexts(title, subtitle, Tokens.Secondary, Modifier.weight(1f))
        Switch(
            checked = checked,
            onCheckedChange = null,
            colors = SwitchDefaults.colors(
                checkedTrackColor = Tokens.AccentPrayer,
                checkedThumbColor = Color.Black,
                uncheckedTrackColor = Tokens.Track,
                uncheckedThumbColor = Tokens.Secondary,
                uncheckedBorderColor = Tokens.Muted,
            ),
        )
    }
}

/** One choice of a single-choice list inside a card. */
@Composable
internal fun RadioRow(title: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
            .heightIn(min = 56.dp)
            .padding(start = 16.dp, end = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, color = Tokens.Primary, fontSize = 17.sp, lineHeight = 22.sp, modifier = Modifier.weight(1f).padding(vertical = 8.dp))
        RadioButton(
            selected = selected,
            onClick = null,
            colors = RadioButtonDefaults.colors(selectedColor = Tokens.AccentPrayer, unselectedColor = Tokens.Secondary),
            modifier = Modifier.padding(12.dp),
        )
    }
}

/** A sub-page: Back, a 26 sp title, then [content] in a scrolling column. */
@Composable
internal fun SubScreen(
    title: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    spacing: Dp = 16.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier
            .fillMaxSize()
            .background(Tokens.Bg)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(spacing),
    ) {
        Column {
            TextButton(onClick = onBack, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(stringResource(R.string.back), color = Tokens.AccentPrayer, fontSize = 16.sp)
            }
            Text(
                title,
                color = Tokens.Primary,
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(horizontal = 4.dp).semantics { heading() },
            )
        }
        content()
    }
}

/** A footnote under a card, aligned with the card's text. */
@Composable
internal fun Footnote(text: String, color: Color = Tokens.Secondary) {
    Text(text, color = color, fontSize = 14.sp, lineHeight = 19.sp, modifier = Modifier.padding(horizontal = 16.dp))
}

@Composable
internal fun chipColors() = FilterChipDefaults.filterChipColors(
    selectedContainerColor = Tokens.Track,
    selectedLabelColor = Tokens.AccentPrayer,
    labelColor = Tokens.Primary,
    containerColor = Tokens.Card,
)

/** A small heading inside a sub-page (used by the silence, mosque and other-apps sections). */
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

/** A stand-alone switch card (one switch on its own, e.g. on the Updates page). */
@Composable
internal fun SwitchRow(title: String, subtitle: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    ToggleRow(title, subtitle, checked, onChange, Modifier.clip(CardShape).background(Tokens.Card))
}
