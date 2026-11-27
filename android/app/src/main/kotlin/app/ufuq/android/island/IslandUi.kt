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
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
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
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.rememberTextMeasurer
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
import app.ufuq.android.prayer.SliderMath
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

private val Mono = SpanStyle(fontFeatureSettings = "tnum")
private val IslandFont = FontFamily.SansSerif

/**
 * The slider: active track, 6 dp gap, 4x52 handle, 6 dp gap, inactive track. The handle sits at
 * `fraction x (width - 4)`, so the row shows its true value (82% reads as 82%); the label spans the
 * whole row and is clipped per segment: dark ink on the active part, light ink on the inactive part.
 * It is one TalkBack node with progress semantics (label + value); the pieces inside are hidden.
 * With [onSeek] and [SliderModel.seek] it is draggable and TalkBack can step it by 10 s.
 */
@Composable
fun IslandSlider(
    model: SliderModel,
    modifier: Modifier = Modifier,
    pageHint: String? = null,
    onSeek: ((Float) -> Unit)? = null,
) {
    val tone = IslandColors.tone(model.level)
    val seek = model.seek?.takeIf { onSeek != null }
    var dragFraction by remember { mutableStateOf<Float?>(null) }
    val fraction = (dragFraction ?: model.fraction).coerceIn(0f, 1f)
    val commit by rememberUpdatedState(onSeek)
    val setProgress = stringResource(R.string.island_seek_action)
    BoxWithConstraints(
        modifier
            .height(52.dp)
            .then(
                if (seek != null) {
                    Modifier
                        .pointerInput(seek) {
                            detectTapGestures { offset ->
                                commit?.invoke(SliderMath.fractionAt(offset.x / density, size.width / density))
                            }
                        }
                        .pointerInput(seek) {
                            detectHorizontalDragGestures(
                                onDragStart = { offset -> dragFraction = SliderMath.fractionAt(offset.x / density, size.width / density) },
                                onDragEnd = { dragFraction?.let { commit?.invoke(it) }; dragFraction = null },
                                onDragCancel = { dragFraction = null },
                            ) { change, _ ->
                                change.consume()
                                dragFraction = SliderMath.fractionAt(change.position.x / density, size.width / density)
                            }
                        }
                } else {
                    Modifier
                },
            )
            .clearAndSetSemantics {
                contentDescription = model.description
                stateDescription = listOfNotNull(model.stateText.ifBlank { null }, pageHint).joinToString(", ")
                if (seek != null) {
                    // Compose has no Slider role: range info + setProgress is what makes TalkBack say "adjustable".
                    progressBarRangeInfo = ProgressBarRangeInfo(fraction, 0f..1f, seek.steps)
                    setProgress(label = setProgress) { target -> commit?.invoke(target.coerceIn(0f, 1f)); true }
                } else {
                    progressBarRangeInfo = ProgressBarRangeInfo(fraction, 0f..1f)
                }
            },
        contentAlignment = Alignment.CenterStart,
    ) {
        val total = maxWidth.value
        val handleLeft = SliderMath.handleLeftDp(fraction, total)
        val activeWidth = SliderMath.activeWidthDp(fraction, total)
        val inactiveStart = SliderMath.inactiveStartDp(fraction, total)
        val inactiveWidth = total - inactiveStart
        if (inactiveWidth > 0f) {
            Box(
                Modifier
                    .offset(x = inactiveStart.dp)
                    .width(inactiveWidth.dp)
                    .height(44.dp)
                    .clip(RoundedCornerShape(topStart = 4.dp, topEnd = 12.dp, bottomEnd = 12.dp, bottomStart = 4.dp))
                    .background(IslandColors.Track),
            )
        }
        if (activeWidth > 0f) {
            Box(
                Modifier
                    .width(activeWidth.dp)
                    .height(44.dp)
                    .clip(RoundedCornerShape(topStart = 12.dp, topEnd = 4.dp, bottomEnd = 4.dp, bottomStart = 12.dp))
                    .background(tone),
            )
        }
        Box(Modifier.offset(x = handleLeft.dp).size(width = 4.dp, height = 52.dp).clip(RoundedCornerShape(2.dp)).background(tone))

        // The end icon stays only when it fits wholly inside the inactive track.
        val iconFits = model.endIcon != null && inactiveStart <= total - LABEL_INSET_DP - ICON_DP - 6f
        val rawSecondary = dragFraction?.let { f -> seek?.let { MediaFormat.clock((f * it.durationMs).toLong()) } } ?: model.secondary
        // A secondary text that would straddle the handle is left out of the row (it stays in the
        // TalkBack description) instead of being cut in half. The trailing text sits below the track.
        val measurer = rememberTextMeasurer()
        val density = LocalDensity.current.density
        val style = androidx.compose.ui.text.TextStyle(fontFamily = IslandFont, fontSize = 14.sp, fontWeight = FontWeight.Medium, fontFeatureSettings = "tnum")
        fun widthDp(text: String) = measurer.measure(text, style).size.width / density
        val zoneStart = activeWidth
        val zoneEnd = inactiveStart
        fun straddles(from: Float, to: Float) = to > zoneStart && from < zoneEnd
        val labelEnd = LABEL_INSET_DP + widthDp(model.label)
        val secondary = rawSecondary?.takeIf { !straddles(labelEnd, labelEnd + widthDp(" $it")) }
        // One label across the row, drawn once per segment in the ink that is readable there.
        val onTone = IslandColors.onTone(model.level)
        Box(Modifier.fillMaxWidth().height(44.dp).clipSpan(0f, activeWidth)) {
            SliderLabel(model, secondary, onTone, onTone, iconFits, IslandColors.Icon)
        }
        Box(Modifier.fillMaxWidth().height(44.dp).clipSpan(inactiveStart, total)) {
            SliderLabel(model, secondary, IslandColors.Ink, IslandColors.Ink2, iconFits, IslandColors.Icon)
        }
    }
}

private const val LABEL_INSET_DP = 12f
private const val ICON_DP = 18f

/** Draws only the part of the content between [startDp] and [endDp]. */
private fun Modifier.clipSpan(startDp: Float, endDp: Float): Modifier = drawWithContent {
    if (endDp > startDp) {
        clipRect(left = startDp.dp.toPx(), right = endDp.dp.toPx()) { this@drawWithContent.drawContent() }
    }
}

@Composable
private fun SliderLabel(model: SliderModel, secondary: String?, ink: Color, ink2: Color, showIcon: Boolean, iconTint: Color) {
    Row(Modifier.fillMaxWidth().height(44.dp).padding(horizontal = LABEL_INSET_DP.dp), verticalAlignment = Alignment.CenterVertically) {
        // The label ellipsizes at large font scales; the full text stays in the description.
        Text(
            text = buildAnnotatedString {
                withStyle(Mono.copy(color = ink)) { append(model.label) }
                secondary?.let { withStyle(Mono.copy(color = ink2, fontWeight = FontWeight.Normal)) { append(" $it") } }
            },
            modifier = Modifier.weight(1f),
            fontFamily = IslandFont,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 2,
            lineHeight = 17.sp,
            overflow = TextOverflow.Ellipsis,
        )
        if (showIcon) {
            model.endIcon?.let {
                Spacer(Modifier.width(8.dp))
                Icon(IslandIcons.of(it), contentDescription = null, tint = iconTint, modifier = Modifier.size(ICON_DP.dp))
            }
        }
    }
}

/**
 * The trailing text (reset time, media length) on its own line under the track, ending where the
 * track ends, so the handle never covers it. Always 16 dp tall, empty or not, so pages line up.
 * Hidden from TalkBack: the slider's description already says it.
 */
@Composable
fun SliderCaption(text: String?, modifier: Modifier = Modifier) {
    Text(
        text.orEmpty(),
        modifier.fillMaxWidth().heightIn(min = 16.dp).clearAndSetSemantics { },
        color = IslandColors.Ink2,
        fontFamily = IslandFont,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        maxLines = 1,
        textAlign = androidx.compose.ui.text.style.TextAlign.End,
        style = androidx.compose.ui.text.TextStyle(fontFeatureSettings = "tnum"),
    )
}

/** The round 48 dp tonal button; its label is its only accessible text. */
@Composable
fun IslandButton(icon: IslandIcon, label: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(48.dp)
            .clip(CircleShape)
            .background(IslandColors.Accent)
            .clickable(onClickLabel = label, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Icon(IslandIcons.of(icon), contentDescription = null, tint = IslandColors.OnAccent, modifier = Modifier.size(22.dp))
    }
}

/** The expanded island: black, 116 dp tall, radius 32; pages swipe horizontally. */
@Composable
fun ExpandedIsland(
    pages: List<IslandPageModel>,
    onAction: (ButtonAction) -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    initialPage: Int = 0,
    onInteract: () -> Unit = {},
    onSeek: (Float) -> Unit = {},
) {
    val pager = rememberPagerState(initialPage = initialPage.coerceIn(0, (pages.size - 1).coerceAtLeast(0))) { pages.size }
    val interact by rememberUpdatedState(onInteract)
    LaunchedEffect(pager.currentPage) { interact() }
    val close = stringResource(R.string.island_close)
    val dismissNow by rememberUpdatedState(onDismiss)
    Box(
        modifier
            .fillMaxWidth()
            .height(116.dp)
            .clip(RoundedCornerShape(32.dp))
            .background(IslandColors.Black)
            // A swipe up closes it; TalkBack users get the same as a custom action.
            .pointerInput(Unit) {
                var total = 0f
                detectVerticalDragGestures(
                    onDragStart = { total = 0f },
                    onDragEnd = { if (total < -48.dp.toPx()) dismissNow() },
                ) { _, drag -> total += drag }
            }
            .semantics { customActions = listOf(CustomAccessibilityAction(close) { dismissNow(); true }) },
    ) {
        HorizontalPager(pager, Modifier.fillMaxSize()) { index ->
            val page = pages[index]
            val hint = stringResource(R.string.island_page_of, index + 1, pages.size)
            // Slider row at the top, its trailing text on a caption line that ends under the track.
            Column(Modifier.fillMaxSize().padding(start = 22.dp, end = 18.dp, top = 16.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    IslandSlider(page.slider, Modifier.weight(1f), pageHint = hint, onSeek = { interact(); onSeek(it) })
                    IslandButton(page.buttonIcon, page.buttonLabel, onClick = { interact(); onAction(page.buttonAction) })
                }
                SliderCaption(page.slider.trailing, Modifier.padding(top = 4.dp, end = 48.dp + 16.dp))
            }
        }
        if (pages.size > 1) {
            Row(
                Modifier.align(Alignment.BottomCenter).padding(bottom = 7.dp).clearAndSetSemantics { },
                horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                repeat(pages.size) { i ->
                    Box(Modifier.size(4.dp).clip(CircleShape).background(if (i == pager.currentPage) IslandColors.Ink else IslandColors.Track))
                }
            }
        }
    }
}

/** The collapsed pill: prayer on the left, the right wing on the other side of the camera gap. */
@Composable
fun IslandPill(pill: PillModel, gapDp: Int, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val expand = stringResource(R.string.island_expand)
    // The touch target is at least 48 dp tall; the pill drawn in it is 32 dp.
    Box(
        modifier
            .defaultMinSize(minHeight = 48.dp)
            .clickable(onClickLabel = expand, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = pill.description },
        contentAlignment = Alignment.TopCenter,
    ) {
        Row(
            Modifier
                .width(IntrinsicSize.Max)
                .height(32.dp)
                .clip(RoundedCornerShape(percent = 50))
                .background(IslandColors.Black)
                .padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                Text(pill.left, color = Color.White, fontFamily = IslandFont, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, style = androidx.compose.ui.text.TextStyle(fontFeatureSettings = "tnum"))
            }
            Spacer(Modifier.width(if (gapDp > 0) gapDp.dp else 8.dp))
            Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
                Text(pill.right, color = IslandColors.tone(pill.rightLevel), fontFamily = IslandFont, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, style = androidx.compose.ui.text.TextStyle(fontFeatureSettings = "tnum"))
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
            IslandMode.Collapsed -> if (pill != null) IslandPill(pill, gapDp, onPillClick)
            is IslandMode.Peek -> IslandPeek(target.event, onPeekDismiss, onPeekHold)
            IslandMode.Expanded -> ExpandedIsland(pages, onAction, onClose, onInteract = onInteract, onSeek = onSeek)
        }
    }
}

@Composable
fun ProvideIslandMotion(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalReduceMotion provides rememberReduceMotion(), content = content)
}
