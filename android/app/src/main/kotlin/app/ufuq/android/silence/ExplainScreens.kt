package app.ufuq.android.silence

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.ufuq.android.R
import app.ufuq.android.ui.Tokens

/** Explains Do Not Disturb access before sending the user to Android's screen for it. */
@Composable
fun SilenceExplainScreen(onContinue: () -> Unit, onCancel: () -> Unit, modifier: Modifier = Modifier) =
    ExplainScreen(
        R.string.silence_explain_title, listOf(R.string.silence_explain_what, R.string.silence_explain_why, R.string.silence_explain_safe),
        R.string.silence_explain_continue, R.string.silence_explain_cancel, onContinue, onCancel, modifier,
    )

/** Explains "Allow all the time" location, separately from fine location and optional. */
@Composable
fun BackgroundLocationExplainScreen(onContinue: () -> Unit, onCancel: () -> Unit, modifier: Modifier = Modifier) =
    ExplainScreen(
        R.string.background_explain_title, listOf(R.string.background_explain_what, R.string.background_explain_why),
        R.string.background_explain_continue, R.string.background_explain_cancel, onContinue, onCancel, modifier,
    )

@Composable
private fun ExplainScreen(
    title: Int, paragraphs: List<Int>, continueLabel: Int, cancelLabel: Int,
    onContinue: () -> Unit, onCancel: () -> Unit, modifier: Modifier,
) {
    Column(
        modifier.fillMaxSize().background(Tokens.Bg).statusBarsPadding().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(stringResource(title), color = Tokens.Primary, fontSize = 26.sp, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
        paragraphs.forEachIndexed { i, p -> Text(stringResource(p), color = if (i == 0) Tokens.Primary else Tokens.Secondary, fontSize = if (i == 0) 17.sp else 16.sp) }
        Button(
            onClick = onContinue,
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Tokens.AccentPrayer, contentColor = Color.Black),
        ) { Text(stringResource(continueLabel)) }
        TextButton(onClick = onCancel, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
            Text(stringResource(cancelLabel), color = Tokens.AccentPrayer)
        }
    }
}
