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
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
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
 * The slider: active track, 6 dp gap, 4x52 handle, 6 dp gap, inactive track with the label inside.
 * It is one TalkBack node with progress semantics (label + value); the pieces inside are hidden.
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
        contentAlignment = Alignment.CenterStart,
    ) {
        val activeWidth = SliderMath.activeWidthDp(model.fraction, maxWidth.value).dp
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (activeWidth > 0.dp) {
                Box(
                    Modifier
                        .width(activeWidth)
                        .height(44.dp)
                        .clip(RoundedCornerShape(topStart = 12.dp, topEnd = 4.dp, bottomEnd = 4.dp, bottomStart = 12.dp))
                        .background(tone),
                )
                Spacer(Modifier.width(6.dp))
            }
            Box(Modifier.size(width = 4.dp, height = 52.dp).clip(RoundedCornerShape(2.dp)).background(tone))
            Spacer(Modifier.width(6.dp))
            Row(
                Modifier
                    .weight(1f)
                    .height(44.dp)
                    .clip(RoundedCornerShape(topStart = 4.dp, topEnd = 12.dp, bottomEnd = 12.dp, bottomStart = 4.dp))
                    .background(IslandColors.Track)
                    .padding(horizontal = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // The label ellipsizes at large font scales; the full text stays in the description.
                Text(
                    text = buildAnnotatedString {
                        withStyle(Mono.copy(color = IslandColors.Ink)) { append(model.label) }
                        model.secondary?.let { withStyle(Mono.copy(color = IslandColors.Ink2, fontWeight = FontWeight.Normal)) { append(" $it") } }
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
                    Text(it, color = IslandColors.Ink2, fontFamily = IslandFont, fontSize = 14.sp, maxLines = 1, style = androidx.compose.ui.text.TextStyle(fontFeatureSettings = "tnum"))
                }
                model.endIcon?.let {
                    Spacer(Modifier.width(8.dp))
                    Icon(IslandIcons.of(it), contentDescription = null, tint = IslandColors.Icon, modifier = Modifier.size(18.dp))
                }
            }
        }
    }
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

/** The expanded island: black, 104 dp tall, radius 32; pages swipe horizontally. */
@Composable
fun ExpandedIsland(
    pages: List<IslandPageModel>,
    onAction: (ButtonAction) -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    initialPage: Int = 0,
    onInteract: () -> Unit = {},
) {
    val pager = rememberPagerState(initialPage = initialPage.coerceIn(0, (pages.size - 1).coerceAtLeast(0))) { pages.size }
    val interact by rememberUpdatedState(onInteract)
    LaunchedEffect(pager.currentPage) { interact() }
    val close = stringResource(R.string.island_close)
    val dismissNow by rememberUpdatedState(onDismiss)
    Box(
        modifier
            .fillMaxWidth()
            .height(104.dp)
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
            Row(
                Modifier.fillMaxSize().padding(start = 22.dp, end = 18.dp),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IslandSlider(page.slider, Modifier.weight(1f), pageHint = hint)
                IslandButton(page.buttonIcon, page.buttonLabel, onClick = { interact(); onAction(page.buttonAction) })
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
            IslandMode.Expanded -> ExpandedIsland(pages, onAction, onClose, onInteract = onInteract)
        }
    }
}

@Composable
fun ProvideIslandMotion(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalReduceMotion provides rememberReduceMotion(), content = content)
}
