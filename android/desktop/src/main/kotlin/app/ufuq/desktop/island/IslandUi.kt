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
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
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
import app.ufuq.desktop.IslandSizes
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
    val Divider = Color(0xFF1C211E)

    /** Dark text for the filled part of the track (all three fills are light enough for it). */
    private val OnAmberRed = Color(0xFF2A1A00)

    fun tone(level: UsageLevel): Color = when (level) {
        UsageLevel.NORMAL -> Accent
        UsageLevel.WARNING -> Amber
        UsageLevel.CRITICAL -> Red
    }

    fun onTone(level: UsageLevel): Color = if (level == UsageLevel.NORMAL) OnAccent else OnAmberRed
}

/** Reduce motion: then the island cross-fades instead of morphing. */
val LocalReduceMotion = compositionLocalOf { false }

private val IslandFont = FontFamily.SansSerif
private val Tabular = TextStyle(fontFeatureSettings = "tnum")
private val TabularSpan = SpanStyle(fontFeatureSettings = "tnum")

/** A 2 dp ring that shows only while the element has keyboard focus (visible focus ring, spec: Accessibility). */
private fun Modifier.ring(focused: Boolean, shape: Shape): Modifier =
    if (focused) border(2.dp, IslandColors.Ink, shape) else this

/** The round button (40 dp drawn, 48 dp target) inside a 54 dp box that leaves room for the focus ring; its label is its only accessible text. */
@Composable
fun IslandButton(icon: IslandIcon, label: String, onClick: () -> Unit, modifier: Modifier = Modifier, tonal: Boolean = true) {
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    Box(
        modifier
            .size(54.dp)
            .ring(focused, CircleShape)
            .padding(3.dp)
            .clip(CircleShape)
            .clickable(interactionSource = interaction, indication = null, onClickLabel = label, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(40.dp).clip(CircleShape).background(if (tonal) IslandColors.Accent else IslandColors.Track), contentAlignment = Alignment.Center) {
            Icon(IslandIcons.of(icon), contentDescription = null, tint = if (tonal) IslandColors.OnAccent else IslandColors.Ink, modifier = Modifier.size(20.dp))
        }
    }
}

/**
 * The expanded island (option C, as on Android): one black card, one row per module, no pages.
 * Tab moves between the row buttons, Esc closes. Each row is one screen-reader node (label, value,
 * progress where it is a meter), then its button.
 */
@Composable
fun ExpandedIsland(
    pages: List<IslandPageModel>,
    onAction: (ButtonAction) -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
    requestFocus: Boolean = true,
) {
    val root = remember { FocusRequester() }
    val closeNow by rememberUpdatedState(onClose)
    // The window only becomes focusable once expanded, so ask again when it gains focus.
    val windowFocused = LocalWindowInfo.current.isWindowFocused
    if (requestFocus) LaunchedEffect(windowFocused) { runCatching { root.requestFocus() } }
    Column(
        modifier
            .fillMaxSize()
            .clip(RoundedCornerShape(28.dp))
            .background(IslandColors.Black)
            .focusRequester(root)
            .onPreviewKeyEvent { e ->
                if (e.type == KeyEventType.KeyDown && e.key == Key.Escape) { closeNow(); true } else false
            }
            .focusable()
            .padding(vertical = IslandSizes.EXPANDED_PADDING.dp, horizontal = 6.dp),
    ) {
        pages.forEachIndexed { i, page ->
            if (i > 0) Box(Modifier.fillMaxWidth().padding(horizontal = 12.dp).height(1.dp).background(IslandColors.Divider))
            IslandRow(page, onAction)
        }
    }
}

/** One module: heading, large value and a 4 dp line (a meter only), with its button on the right. */
@Composable
fun IslandRow(page: IslandPageModel, onAction: (ButtonAction) -> Unit, modifier: Modifier = Modifier) {
    val model = page.slider
    // A message row: its title ("AI usage") is the heading, its hint is the message.
    val heading = if (page.message) model.label else listOfNotNull(model.label, model.trailing).joinToString(" · ")
    val value = model.secondary.orEmpty()
    Row(
        modifier.fillMaxWidth().height(IslandSizes.EXPANDED_ROW.dp).padding(start = 14.dp, end = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(
            Modifier.weight(1f).clearAndSetSemantics {
                contentDescription = model.description
                if (model.stateText.isNotBlank()) stateDescription = model.stateText
                if (model.meter && !page.message) progressBarRangeInfo = ProgressBarRangeInfo(model.fraction.coerceIn(0f, 1f), 0f..1f)
            },
        ) {
            Text(heading, color = IslandColors.Ink2, fontFamily = IslandFont, fontSize = 13.sp, lineHeight = 17.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, style = Tabular.copy(color = IslandColors.Ink2))
            if (page.message) {
                Text(value, color = IslandColors.Ink, fontFamily = IslandFont, fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            } else {
                Text(value, color = IslandColors.Ink, fontFamily = IslandFont, fontSize = 22.sp, lineHeight = 26.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, style = Tabular.copy(color = IslandColors.Ink))
                if (model.meter) {
                    BoxWithConstraints(Modifier.padding(top = 6.dp).fillMaxWidth().height(4.dp).clip(RoundedCornerShape(2.dp)).background(IslandColors.Track)) {
                        val f = model.fraction.coerceIn(0f, 1f)
                        if (f > 0f) Box(Modifier.width(maxWidth * f).fillMaxHeight().clip(RoundedCornerShape(2.dp)).background(IslandColors.tone(model.level)))
                    }
                }
            }
        }
        Spacer(Modifier.width(10.dp))
        IslandButton(page.buttonIcon, page.buttonLabel, onClick = { onAction(page.buttonAction) }, tonal = !page.message)
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
    strings: IslandStrings,
    onPillClick: () -> Unit,
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
            NotchState.Expanded -> ExpandedIsland(pages, onAction, onClose)
        }
    }
}
