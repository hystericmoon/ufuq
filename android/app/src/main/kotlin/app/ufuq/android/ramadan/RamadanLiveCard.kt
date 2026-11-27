package app.ufuq.android.ramadan

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.ufuq.android.live.LiveUpdateContent
import app.ufuq.android.ui.Tokens
import androidx.compose.foundation.layout.fillMaxHeight

/**
 * The Live Update's content as a card, from the same [LiveUpdateContent] the notification is built
 * from. The system notification cannot be rendered in a unit test, so screenshots use this.
 */
@Composable
fun RamadanLiveCard(content: LiveUpdateContent, modifier: Modifier = Modifier) {
    val p = content.progress
    Column(
        modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp)).background(Tokens.Card).padding(16.dp),
    ) {
        Text(content.title, color = Tokens.Primary, fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
        Text(content.text, color = Tokens.Secondary, fontSize = 14.sp)
        Box(
            Modifier.padding(top = 12.dp).fillMaxWidth().height(8.dp).clip(RoundedCornerShape(4.dp)).background(Tokens.Track)
                .semantics { progressBarRangeInfo = ProgressBarRangeInfo(p.fraction, 0f..1f) },
        ) {
            Box(Modifier.fillMaxWidth(p.fraction).fillMaxHeight().background(Tokens.AccentPrayer))
        }
        Text("${p.percent}%  ·  ${p.countdown}", color = Tokens.Secondary, fontSize = 13.sp, modifier = Modifier.padding(top = 6.dp))
    }
}
