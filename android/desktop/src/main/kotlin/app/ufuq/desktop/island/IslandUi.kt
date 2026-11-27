package app.ufuq.desktop.island

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
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.ufuq.core.PeekEvent
import app.ufuq.core.UsageLevel
import app.ufuq.desktop.NotchState

// TODO: duplicated from :app (app.ufuq.android.island.IslandUi); extract to a KMP :island-ui module later.

/** The island is always black, like the camera it wraps, so these do not follow the theme (spec: android.* tokens, shared with desktop). */
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

    /** Dark text for the filled part of the track (all three fills are light enough for it). */
    private val OnAmberRed = Color(0xFF2A1A00)

    fun tone(level: UsageLevel): Color = when (level) {
        UsageLevel.NORMAL -> Accent
        UsageLevel.WARNING -> Amber
        UsageLevel.CRITICAL -> Red
    }

    fun onTone(level: UsageLevel): Color = if (level == UsageLevel.NORMAL) OnAccent else OnAmberRed
}

/** Reduce motion: then the island cross-fades instead of morphing and pages fade instead of sliding. */
val LocalReduceMotion = compositionLocalOf { false }

private val IslandFont = FontFamily.SansSerif
private val Tabular = TextStyle(fontFeatureSettings = "tnum")
private val TabularSpan = SpanStyle(fontFeatureSettings = "tnum")

/** A 2 dp ring that shows only while the element has keyboard focus (visible focus ring, spec: Accessibility). */
private fun Modifier.ring(focused: Boolean, shape: Shape): Modifier =
    if (focused) border(2.dp, IslandColors.Ink, shape) else this

/** A horizontal slice of a box, in dp: how the label is clipped to one segment of the track. */
private class SliceShape(private val startDp: Float, private val endDp: Float) : Shape {
    override fun createOutline(size: androidx.compose.ui.geometry.Size, layoutDirection: LayoutDirection, density: Density): Outline =
        Outline.Rectangle(Rect(startDp * density.density, 0f, (endDp * density.density).coerceAtLeast(startDp * density.density), size.height))
}

/** The label row that overlays the whole track: name and secondary at the start, trailing text and icon at the end. */
@Composable
private fun TrackLabels(model: SliderModel, primary: Color, secondary: Color, modifier: Modifier = Modifier) {
    Row(modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(
            text = buildAnnotatedString {
                withStyle(TabularSpan.copy(color = primary)) { append(model.label) }
                model.secondary?.let { withStyle(TabularSpan.copy(color = secondary, fontWeight = FontWeight.Normal)) { append(" $it") } }
            },
            modifier = Modifier.weight(1f),
            fontFamily = IslandFont,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        model.trailing?.let {
            Spacer(Modifier.width(8.dp))
            Text(it, color = secondary, fontFamily = IslandFont, fontSize = 14.sp, maxLines = 1, style = Tabular.copy(color = secondary))
        }
        model.endIcon?.let {
            Spacer(Modifier.width(8.dp))
            Icon(IslandIcons.of(it), contentDescription = null, tint = secondary, modifier = Modifier.size(18.dp))
        }
    }
}

/**
 * The proportional slider: the handle (4x52) sits at `fraction x (width - 4)`, the active track
 * runs from the start to 6 dp before it, the inactive track from 6 dp after it to the end. The
 * label overlays the whole track; each segment clips its own copy, so the text is dark on the
 * fill and light on the dark track. It is one accessibility node with progress semantics.
 */
@Composable
fun IslandSlider(model: SliderModel, modifier: Modifier = Modifier, pageHint: String? = null) {
    val tone = IslandColors.tone(model.level)
    BoxWithConstraints(
        modifier
            .height(52.dp)
            .clearAndSetSemantics {
                contentDescription = model.description
                stateDescription = listOfNotNull(model.stateText, pageHint).joinToString(", ")
                progressBarRangeInfo = ProgressBarRangeInfo(model.fraction.coerceIn(0f, 1f), 0f..1f)
            },
    ) {
        val total = maxWidth.value
        val g = SliderGeometry.of(model.fraction, total)
        val activeShape = RoundedCornerShape(topStart = 12.dp, topEnd = 4.dp, bottomEnd = 4.dp, bottomStart = 12.dp)
        val inactiveShape = RoundedCornerShape(topStart = 4.dp, topEnd = 12.dp, bottomEnd = 12.dp, bottomStart = 4.dp)
        if (g.activeWidth > 0.5f) {
            Box(Modifier.align(Alignment.CenterStart).width(g.activeWidth.dp).height(44.dp).clip(activeShape).background(tone))
        }
        Box(Modifier.align(Alignment.CenterStart).offset(x = g.handleX.dp).size(width = SliderGeometry.HANDLE_DP.dp, height = 52.dp).clip(RoundedCornerShape(2.dp)).background(tone))
        if (g.inactiveWidth > 0.5f) {
            Box(Modifier.align(Alignment.CenterStart).offset(x = g.inactiveStart.dp).width(g.inactiveWidth.dp).height(44.dp).clip(inactiveShape).background(IslandColors.Track))
        }
        // Two copies of the label across the full track, each clipped to its segment.
        val onTone = IslandColors.onTone(model.level)
        if (g.activeWidth > 0.5f) {
            TrackLabels(model, onTone, onTone.copy(alpha = 0.8f), Modifier.align(Alignment.CenterStart).fillMaxWidth().height(44.dp).clip(SliceShape(0f, g.activeWidth)))
        }
        if (g.inactiveWidth > 0.5f) {
            TrackLabels(model, IslandColors.Ink, IslandColors.Ink2, Modifier.align(Alignment.CenterStart).fillMaxWidth().height(44.dp).clip(SliceShape(g.inactiveStart, total)))
        }
    }
}

/** The round 48 dp tonal button inside a 54 dp box that leaves room for the focus ring; its label is its only accessible text. */
@Composable
fun IslandButton(icon: IslandIcon, label: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    Box(
        modifier
            .size(54.dp)
            .ring(focused, CircleShape)
            .padding(3.dp)
            .clip(CircleShape)
            .background(IslandColors.Accent)
            .clickable(interactionSource = interaction, indication = null, onClickLabel = label, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Icon(IslandIcons.of(icon), contentDescription = null, tint = IslandColors.OnAccent, modifier = Modifier.size(22.dp))
    }
}

/** A page dot: a 28 dp target with a visible focus ring; selecting it switches the page. */
@Composable
private fun PageDot(selected: Boolean, label: String, onSelect: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    Box(
        Modifier
            .size(28.dp)
            .ring(focused, CircleShape)
            .selectable(selected = selected, interactionSource = interaction, indication = null, role = Role.Tab, onClick = onSelect)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(if (selected) 7.dp else 5.dp).clip(CircleShape).background(if (selected) IslandColors.Ink else IslandColors.Ink2))
    }
}

/**
 * The expanded island: black, radius 28. Left and right arrows or the dots switch pages, Tab
 * reaches the button and the dots, Esc closes.
 */
@Composable
fun ExpandedIsland(
    pages: List<IslandPageModel>,
    pageIndex: Int,
    strings: IslandStrings,
    onPage: (Int) -> Unit,
    onAction: (ButtonAction) -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
    reduceMotion: Boolean = LocalReduceMotion.current,
    requestFocus: Boolean = true,
) {
    val root = remember { FocusRequester() }
    val closeNow by rememberUpdatedState(onClose)
    val pageNow by rememberUpdatedState(onPage)
    val index = pageIndex.coerceIn(0, (pages.size - 1).coerceAtLeast(0))
    val indexNow by rememberUpdatedState(index)
    // The window only becomes focusable once expanded, so ask again when it gains focus.
    val windowFocused = LocalWindowInfo.current.isWindowFocused
    if (requestFocus) LaunchedEffect(windowFocused) { runCatching { root.requestFocus() } }
    Box(
        modifier
            .fillMaxSize()
            .clip(RoundedCornerShape(28.dp))
            .background(IslandColors.Black)
            .focusRequester(root)
            .onPreviewKeyEvent { e ->
                if (e.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                when (e.key) {
                    Key.Escape -> { closeNow(); true }
                    Key.DirectionLeft -> { if (indexNow > 0) pageNow(indexNow - 1); true }
                    Key.DirectionRight -> { if (indexNow < pages.size - 1) pageNow(indexNow + 1); true }
                    else -> false
                }
            }
            .focusable(),
    ) {
        AnimatedContent(
            targetState = index,
            modifier = Modifier.fillMaxSize(),
            transitionSpec = {
                if (reduceMotion) {
                    ContentTransform(fadeIn(tween(150)), fadeOut(tween(150)), sizeTransform = SizeTransform(clip = false) { _, _ -> snap() })
                } else {
                    val dir = if (targetState > initialState) 1 else -1
                    ContentTransform(
                        slideInHorizontally(tween(220)) { it * dir / 4 } + fadeIn(tween(220)),
                        slideOutHorizontally(tween(220)) { -it * dir / 4 } + fadeOut(tween(120)),
                        sizeTransform = SizeTransform(clip = false) { _, _ -> snap() },
                    )
                }
            },
            label = "page",
        ) { i ->
            val page = pages.getOrNull(i)
            if (page != null) {
                Row(
                    Modifier.fillMaxSize().padding(start = 22.dp, end = 14.dp, bottom = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IslandSlider(page.slider, Modifier.weight(1f), pageHint = strings.pageOf(i + 1, pages.size))
                    IslandButton(page.buttonIcon, page.buttonLabel, onClick = { onAction(page.buttonAction) })
                }
            }
        }
        if (pages.size > 1) {
            Row(Modifier.align(Alignment.BottomCenter), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                pages.forEachIndexed { i, _ -> PageDot(i == index, strings.pageOf(i + 1, pages.size)) { onPage(i) } }
            }
        }
    }
}

/** The collapsed pill, 300x32: prayer on the left, AI usage on the right. */
@Composable
fun IslandPill(pill: PillModel, strings: IslandStrings, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val shape = RoundedCornerShape(14.dp)
    Row(
        modifier
            .fillMaxSize()
            .clip(shape)
            .background(IslandColors.Black)
            .ring(focused, shape)
            .clickable(interactionSource = interaction, indication = null, onClickLabel = strings.expand, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = pill.description }
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            Text(pill.left, color = Color.White, fontFamily = IslandFont, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, style = Tabular.copy(color = Color.White))
        }
        Spacer(Modifier.width(8.dp))
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
            val right = IslandColors.tone(pill.rightLevel)
            Text(pill.right, color = right, fontFamily = IslandFont, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, style = Tabular.copy(color = right))
        }
    }
}

/** A peek: one alert, auto-dismissed by the queue after 6 s; hovering with the pointer holds it, a click dismisses. */
@Composable
fun IslandPeek(event: PeekEvent, strings: IslandStrings, onDismiss: () -> Unit, onHold: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    val critical = event.priority == PeekEvent.Priority.CRITICAL
    val holdNow by rememberUpdatedState(onHold)
    val shape = RoundedCornerShape(22.dp)
    Column(
        modifier
            .fillMaxSize()
            .clip(shape)
            .background(IslandColors.Black)
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    // Hover enters and exits are separate events; hold while the pointer is inside.
                    while (true) {
                        val e = awaitPointerEvent()
                        when (e.type) {
                            PointerEventType.Enter -> holdNow(true)
                            PointerEventType.Exit -> holdNow(false)
                            else -> Unit
                        }
                    }
                }
            }
            .clickable(onClickLabel = strings.dismiss, role = Role.Button, onClick = onDismiss)
            .semantics(mergeDescendants = true) {
                contentDescription = event.announcement
                liveRegion = if (critical) LiveRegionMode.Assertive else LiveRegionMode.Polite
                role = Role.Button
                onClick(strings.dismiss) { onDismiss(); true }
            }
            .padding(horizontal = 22.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(event.title, color = Color.White, fontFamily = IslandFont, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(event.message, color = IslandColors.Ink2, fontFamily = IslandFont, fontSize = 14.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

/**
 * Everything the island window draws. Switching state fades and scales the content only (the
 * window is resized once by the shell); with Reduce motion it is a plain cross-fade.
 */
@Composable
fun IslandContent(
    mode: NotchState,
    pill: PillModel?,
    pages: List<IslandPageModel>,
    pageIndex: Int,
    strings: IslandStrings,
    onPillClick: () -> Unit,
    onPage: (Int) -> Unit,
    onAction: (ButtonAction) -> Unit,
    onClose: () -> Unit,
    onPeekDismiss: () -> Unit,
    onPeekHold: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    reduceMotion: Boolean = LocalReduceMotion.current,
) {
    AnimatedContent(
        targetState = mode,
        modifier = modifier.fillMaxSize(),
        contentKey = { it.kind },
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
            NotchState.Collapsed -> if (pill != null) IslandPill(pill, strings, onPillClick)
            is NotchState.Peek -> IslandPeek(target.event, strings, onPeekDismiss, onPeekHold)
            NotchState.Expanded -> ExpandedIsland(pages, pageIndex, strings, onPage, onAction, onClose, reduceMotion = reduceMotion)
        }
    }
}
