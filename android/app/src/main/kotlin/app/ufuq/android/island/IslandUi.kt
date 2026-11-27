package app.ufuq.android.island

import android.provider.Settings
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.dismiss
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.ufuq.android.R
import app.ufuq.android.media.MediaFormat
import app.ufuq.core.PeekEvent
import app.ufuq.core.UsageLevel

/** The island is always black, like the camera it wraps, so these do not follow the theme (spec: android.* tokens). */
object IslandColors {
    val Black = Color(0xFF000000)
    val Track = Color(0xFF26302A)
    val Accent = Color(0xFFA8D8B9)
    val OnAccent = Color(0xFF0F3D25)
    val Ink = Color(0xFFE6EAE6)
    val Ink2 = Color(0xFFA1A1A6)
    val Icon = Color(0xFFC9CFC9)
    val Amber = Color(0xFFFFB340)
    val Red = Color(0xFFFF6B5E)
    val Divider = Color(0xFF1C211E)

    /** Label ink on the active track: dark green on mint, black on amber and red (each at least 4.5:1). */
    fun onTone(level: UsageLevel): Color = if (level == UsageLevel.NORMAL) OnAccent else Black

    fun tone(level: UsageLevel): Color = when (level) {
        UsageLevel.NORMAL -> Accent
        UsageLevel.WARNING -> Amber
        UsageLevel.CRITICAL -> Red
    }
}

/** Reduce motion: the system's animator scale is 0. Then the island cross-fades instead of morphing. */
val LocalReduceMotion = compositionLocalOf { false }

@Composable
fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember {
        runCatching {
            Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
        }.getOrDefault(false)
    }
}

/** What the overlay shows. */
sealed interface IslandMode {
    data object Collapsed : IslandMode
    data class Peek(val event: PeekEvent) : IslandMode
    data object Expanded : IslandMode
}

private val IslandFont = FontFamily.SansSerif

/** The round button; its label is its only accessible text. */
@Composable
fun IslandButton(icon: IslandIcon, label: String, onClick: () -> Unit, modifier: Modifier = Modifier, tonal: Boolean = true) {
    // 48 dp touch target; the drawn circle is 40 dp. Mint when the row has live data, dark otherwise.
    Box(
        modifier
            .size(48.dp)
            .clip(CircleShape)
            .clickable(onClickLabel = label, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(40.dp).clip(CircleShape).background(if (tonal) IslandColors.Accent else IslandColors.Track), contentAlignment = Alignment.Center) {
            Icon(IslandIcons.of(icon), contentDescription = null, tint = if (tonal) IslandColors.OnAccent else IslandColors.Ink, modifier = Modifier.size(20.dp))
        }
    }
}

/**
 * The expanded island (owner's option C, 27 Nov): one black card, one row per module, no pages.
 * A row is a heading, a large value and a thin progress line, with its round action on the right.
 * Rows without data ([IslandPageModel.showBar] false) show their message in body text and no line.
 * TalkBack reads each row as one node (label, value, progress), then its button.
 */
@Composable
fun ExpandedIsland(
    pages: List<IslandPageModel>,
    onAction: (ButtonAction) -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    onInteract: () -> Unit = {},
    onSeek: (Float) -> Unit = {},
) {
    val interact by rememberUpdatedState(onInteract)
    val close = stringResource(R.string.island_close)
    val dismissNow by rememberUpdatedState(onDismiss)
    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(28.dp))
            .background(IslandColors.Black)
            // A swipe up closes it; TalkBack users get the same as a custom action.
            .pointerInput(Unit) {
                var total = 0f
                detectVerticalDragGestures(
                    onDragStart = { total = 0f },
                    onDragEnd = { if (total < -48.dp.toPx()) dismissNow() },
                ) { _, drag -> total += drag }
            }
            .semantics { customActions = listOf(CustomAccessibilityAction(close) { dismissNow(); true }) }
            .padding(horizontal = 6.dp, vertical = 6.dp),
    ) {
        pages.forEachIndexed { index, page ->
            if (index > 0) Box(Modifier.fillMaxWidth().padding(horizontal = 12.dp).height(1.dp).background(IslandColors.Divider))
            IslandRow(
                page,
                onAction = { interact(); onAction(it) },
                onSeek = { interact(); onSeek(it) },
            )
        }
    }
}

/** One module in the expanded card. */
@Composable
fun IslandRow(page: IslandPageModel, onAction: (ButtonAction) -> Unit, onSeek: (Float) -> Unit, modifier: Modifier = Modifier) {
    val model = page.slider
    val seek = model.seek
    val setProgressLabel = stringResource(R.string.island_seek_action)
    var dragFraction by remember { mutableStateOf<Float?>(null) }
    val fraction = (dragFraction ?: model.fraction).coerceIn(0f, 1f)
    val commit by rememberUpdatedState(onSeek)
    // A message row (no data yet) leads with its short hint and shows the message below it.
    val heading = if (page.showBar) listOfNotNull(model.label, model.trailing).joinToString(" · ") else model.secondary
    val dragged = dragFraction?.let { f -> seek?.let { MediaFormat.clock((f * it.durationMs).toLong()) } }
    val value = if (page.showBar) dragged ?: model.secondary ?: "" else model.label
    Column(modifier.fillMaxWidth().padding(start = 14.dp, end = 8.dp, top = 8.dp, bottom = 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(
                Modifier
                    .weight(1f)
                    .clearAndSetSemantics {
                        contentDescription = model.description
                        if (model.stateText.isNotBlank()) stateDescription = model.stateText
                        if (page.showBar) {
                            if (seek != null) {
                                // Compose has no Slider role: range info + setProgress is what makes TalkBack say "adjustable".
                                progressBarRangeInfo = ProgressBarRangeInfo(fraction, 0f..1f, seek.steps)
                                setProgress(label = setProgressLabel) { target -> commit(target.coerceIn(0f, 1f)); true }
                            } else {
                                progressBarRangeInfo = ProgressBarRangeInfo(fraction, 0f..1f)
                            }
                        }
                    },
            ) {
                // Text keeps a fixed line count, so a long title ellipsizes; the full text is in the description.
                heading?.let {
                    Text(it, color = IslandColors.Ink2, fontFamily = IslandFont, fontSize = 13.sp, lineHeight = 17.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, style = TabularNums)
                }
                if (page.showBar) {
                    Text(value, color = IslandColors.Ink, fontFamily = IslandFont, fontSize = 22.sp, lineHeight = 26.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, style = TabularNums)
                } else {
                    Text(value, color = IslandColors.Ink, fontFamily = IslandFont, fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
            Spacer(Modifier.width(12.dp))
            IslandButton(page.buttonIcon, page.buttonLabel, onClick = { onAction(page.buttonAction) }, tonal = page.showBar)
        }
        if (page.showBar) {
            ProgressLine(
                fraction = fraction,
                level = model.level,
                modifier = Modifier.padding(end = 6.dp),
                onDrag = if (seek != null) {
                    { f, done -> if (done) { commit(f); dragFraction = null } else dragFraction = f }
                } else {
                    null
                },
                onDragCancel = { dragFraction = null },
            )
        }
    }
}

private val TabularNums = androidx.compose.ui.text.TextStyle(fontFeatureSettings = "tnum")

/**
 * A 4 dp line: filled part in the row's tone (amber and red always come with the % in the text).
 * Draggable when [onDrag] is set; the touch strip is then 24 dp tall. Hidden from TalkBack: the
 * row's text node carries the progress and the seek action.
 */
@Composable
private fun ProgressLine(
    fraction: Float,
    level: UsageLevel,
    modifier: Modifier = Modifier,
    onDrag: ((Float, Boolean) -> Unit)? = null,
    onDragCancel: () -> Unit = {},
) {
    val drag by rememberUpdatedState(onDrag)
    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .height(if (onDrag != null) 24.dp else 12.dp)
            .then(
                if (onDrag != null) {
                    Modifier
                        .pointerInput(Unit) {
                            detectTapGestures { offset -> drag?.invoke((offset.x / size.width).coerceIn(0f, 1f), true) }
                        }
                        .pointerInput(Unit) {
                            var last = 0f
                            detectHorizontalDragGestures(
                                onDragStart = { offset -> last = (offset.x / size.width).coerceIn(0f, 1f); drag?.invoke(last, false) },
                                onDragEnd = { drag?.invoke(last, true) },
                                onDragCancel = onDragCancel,
                            ) { change, _ ->
                                change.consume()
                                last = (change.position.x / size.width).coerceIn(0f, 1f)
                                drag?.invoke(last, false)
                            }
                        }
                } else {
                    Modifier
                },
            )
            .clearAndSetSemantics { },
        contentAlignment = Alignment.CenterStart,
    ) {
        Box(Modifier.fillMaxWidth().height(4.dp).clip(RoundedCornerShape(2.dp)).background(IslandColors.Track))
        if (fraction > 0f) {
            Box(Modifier.width(maxWidth * fraction).height(4.dp).clip(RoundedCornerShape(2.dp)).background(IslandColors.tone(level)))
        }
    }
}

/** The collapsed pill: prayer on the left, the right wing on the other side of the camera gap. */
@Composable
fun IslandPill(
    pill: PillModel,
    gapDp: Int,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    placement: IslandGeometry.Placement = IslandGeometry.Placement(IslandGeometry.PILL_PADDING_DP, IslandGeometry.DEFAULT_PILL_DP),
) {
    val expand = stringResource(R.string.island_expand)
    // The touch target is at least 48 dp tall and starts at the screen edge; the pill drawn in it
    // is centred on the camera hole. Text is fixed at 12 sp so the pill keeps hugging the camera at
    // large font sizes; TalkBack reads the full sentence from the description.
    Box(
        modifier
            .defaultMinSize(minWidth = 48.dp, minHeight = 48.dp)
            .clickable(onClickLabel = expand, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = pill.description },
        contentAlignment = Alignment.TopCenter,
    ) {
        val density = LocalDensity.current
        val fixed = with(density) { 12.dp.toSp() }
        Row(
            Modifier
                .padding(top = placement.topDp.dp)
                .width(IntrinsicSize.Max)
                .height(placement.heightDp.dp)
                .clip(RoundedCornerShape(percent = 50))
                .background(IslandColors.Black)
                .padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.weight(1f).defaultMinSize(minWidth = 28.dp), contentAlignment = Alignment.CenterStart) {
                Text(pill.left, color = Color.White, fontFamily = IslandFont, fontSize = fixed, fontWeight = FontWeight.SemiBold, maxLines = 1, style = androidx.compose.ui.text.TextStyle(fontFeatureSettings = "tnum"))
            }
            Spacer(Modifier.width(if (gapDp > 0) gapDp.dp else 8.dp))
            Box(Modifier.weight(1f).defaultMinSize(minWidth = 28.dp), contentAlignment = Alignment.CenterEnd) {
                Text(pill.right, color = IslandColors.tone(pill.rightLevel), fontFamily = IslandFont, fontSize = fixed, fontWeight = FontWeight.SemiBold, maxLines = 1, style = androidx.compose.ui.text.TextStyle(fontFeatureSettings = "tnum"))
            }
        }
    }
}

/** A peek: one alert, auto-dismissed by the queue after 6 s; touch-and-hold keeps it. */
@Composable
fun IslandPeek(event: PeekEvent, onDismiss: () -> Unit, onHold: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    val dismiss = stringResource(R.string.island_dismiss)
    val critical = event.priority == PeekEvent.Priority.CRITICAL
    val holdNow by rememberUpdatedState(onHold)
    val dismissNow by rememberUpdatedState(onDismiss)
    Column(
        modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 72.dp)
            .clip(RoundedCornerShape(28.dp))
            .background(IslandColors.Black)
            .pointerInput(Unit) {
                detectTapGestures(
                    onPress = { holdNow(true); tryAwaitRelease(); holdNow(false) },
                    onTap = { dismissNow() },
                )
            }
            .semantics(mergeDescendants = true) {
                contentDescription = event.announcement
                liveRegion = if (critical) LiveRegionMode.Assertive else LiveRegionMode.Polite
                role = Role.Button
                onClick(dismiss) { dismissNow(); true }
            }
            .padding(horizontal = 22.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(event.title, color = Color.White, fontFamily = IslandFont, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(event.message, color = IslandColors.Ink2, fontFamily = IslandFont, fontSize = 14.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * Everything the overlay window draws. Switching mode fades and scales the content only (the
 * window is resized once, by the service); with Reduce motion it is a plain cross-fade.
 */
@Composable
fun IslandContent(
    mode: IslandMode,
    pill: PillModel?,
    pages: List<IslandPageModel>,
    gapDp: Int,
    onPillClick: () -> Unit,
    onAction: (ButtonAction) -> Unit,
    onClose: () -> Unit,
    onPeekDismiss: () -> Unit,
    onPeekHold: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    onInteract: () -> Unit = {},
    reduceMotion: Boolean = LocalReduceMotion.current,
    onSeek: (Float) -> Unit = {},
    placement: IslandGeometry.Placement = IslandGeometry.Placement(IslandGeometry.PILL_PADDING_DP, IslandGeometry.DEFAULT_PILL_DP),
) {
    AnimatedContent(
        targetState = mode,
        modifier = modifier,
        contentKey = { it::class },
        transitionSpec = {
            val enter = if (reduceMotion) {
                fadeIn(tween(150))
            } else {
                fadeIn(tween(120)) + scaleIn(spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessMediumLow), initialScale = 0.9f, transformOrigin = TransformOrigin(0.5f, 0f))
            }
            ContentTransform(enter, fadeOut(tween(if (reduceMotion) 150 else 70)), sizeTransform = SizeTransform(clip = false) { _, _ -> snap() })
        },
        contentAlignment = Alignment.TopCenter,
        label = "island",
    ) { target ->
        when (target) {
            IslandMode.Collapsed -> if (pill != null) IslandPill(pill, gapDp, onPillClick, placement = placement)
            is IslandMode.Peek -> IslandPeek(target.event, onPeekDismiss, onPeekHold)
            IslandMode.Expanded -> ExpandedIsland(pages, onAction, onClose, onInteract = onInteract, onSeek = onSeek)
        }
    }
}

@Composable
fun ProvideIslandMotion(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalReduceMotion provides rememberReduceMotion(), content = content)
}
