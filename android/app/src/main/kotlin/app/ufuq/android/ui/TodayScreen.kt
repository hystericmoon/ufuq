package app.ufuq.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.ufuq.android.R

private val Tabular = TextStyle(fontFeatureSettings = "tnum")

/** Today: the next prayer with its countdown, and the six times with the next one highlighted. */
@Composable
fun TodayScreen(state: TodayState?, onOpenSettings: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier
            .fillMaxSize()
            .background(Tokens.Bg)
            .statusBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
            Text(
                stringResource(R.string.today_title),
                color = Tokens.Primary,
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.semantics { heading() },
            )
            TextButton(onClick = onOpenSettings, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(stringResource(R.string.settings_title), color = Tokens.AccentPrayer, fontSize = 16.sp)
            }
        }
        if (state == null) {
            Text(stringResource(R.string.today_unavailable), color = Tokens.Secondary, fontSize = 16.sp)
        } else {
            NextCard(state)
            TimesCard(state)
        }
    }
}

@Composable
private fun NextCard(state: TodayState) {
    val description = stringResource(R.string.today_next_description, state.nextName, state.countdownSpoken)
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(24.dp))
            .background(Tokens.Card)
            .padding(20.dp)
            .semantics(mergeDescendants = true) { contentDescription = description },
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(stringResource(R.string.today_next, state.nextName), color = Tokens.Secondary, fontSize = 14.sp)
        Text(
            state.countdown,
            color = if (state.underTenMinutes) Tokens.AccentPrayer else Tokens.Primary,
            fontSize = 44.sp,
            fontWeight = FontWeight.SemiBold,
            style = Tabular,
        )
        Text(state.location, color = Tokens.Muted, fontSize = 14.sp)
    }
}

@Composable
private fun TimesCard(state: TodayState) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp)).background(Tokens.Card).padding(vertical = 8.dp),
    ) {
        state.rows.forEach { row ->
            val next = stringResource(R.string.today_row_next)
            val description = if (row.isNext) "${row.name} ${row.time}, $next" else "${row.name} ${row.time}"
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 52.dp)
                    .padding(horizontal = 8.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(if (row.isNext) Tokens.Track else Tokens.Card)
                    .padding(horizontal = 12.dp)
                    .semantics(mergeDescendants = true) { contentDescription = description },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    row.name,
                    color = if (row.isNext) Tokens.AccentPrayer else Tokens.Primary,
                    fontSize = 17.sp,
                    fontWeight = if (row.isNext) FontWeight.SemiBold else FontWeight.Normal,
                    modifier = Modifier.weight(1f),
                )
                // Color is never the only cue: the next row also says "Next".
                if (row.isNext) {
                    Text(next, color = Tokens.Secondary, fontSize = 13.sp, modifier = Modifier.clearAndSetSemantics { })
                    Spacer(Modifier.padding(start = 12.dp))
                }
                Text(
                    row.time,
                    color = if (row.isNext) Tokens.AccentPrayer else Tokens.Primary,
                    fontSize = 17.sp,
                    fontWeight = if (row.isNext) FontWeight.SemiBold else FontWeight.Normal,
                    style = Tabular,
                )
            }
        }
    }
}
