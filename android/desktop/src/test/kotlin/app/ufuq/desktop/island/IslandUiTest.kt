package app.ufuq.desktop.island

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toAwtImage
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.DesktopComposeUiTest
import androidx.compose.ui.test.assertRangeInfoEquals
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performKeyInput
import androidx.compose.ui.test.pressKey
import androidx.compose.ui.test.v2.runDesktopComposeUiTest
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import app.ufuq.core.PeekEvent
import app.ufuq.core.UsageLevel
import app.ufuq.desktop.IslandSizes
import app.ufuq.desktop.NotchState
import app.ufuq.desktop.settings.DesktopSettings
import app.ufuq.desktop.settings.SettingsScreen
import java.io.File
import java.time.Duration
import java.time.Instant
import javax.imageio.ImageIO
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Renders the island to PNGs (build/screenshots) with Skia on the CPU, so they run headless on
 * Linux CI, and checks what the screen reader would get.
 */
@OptIn(ExperimentalTestApi::class)
class IslandUiTest {
    private val s = EnglishIslandStrings
    private val now = Instant.parse("2026-11-26T08:00:00Z")

    private val prayerProgress = PrayerProgress("Ashar", now.minus(Duration.ofMinutes(118)), now.plus(Duration.ofMinutes(72)), now)
    private val prayerPage = IslandPages.prayer(prayerProgress, s)
    private fun aiPages(vararg samples: AiUsageSample) = IslandPages.aiUsage(samples.toList(), s)
    private val codex82 = AiUsageSample("Codex", 0.82, Duration.ofMinutes(72), "5h")
    private val claudeTokens = AiUsageSample("Claude", 0.0, Duration.ofHours(3), "5h", tokens = 4_213_000)

    private val outDir = File(System.getProperty("ufuq.screenshotDir") ?: "build/screenshots").also { it.mkdirs() }

    /** Draws [content] in a [w]x[h] dp island on a plain desktop colour and writes it as a 2x PNG. */
    private fun shot(name: String, w: Int, h: Int, reduceMotion: Boolean = false, content: @Composable () -> Unit, check: DesktopComposeUiTest.() -> Unit = {}) {
        val margin = 16
        runDesktopComposeUiTest((w + 2 * margin) * 2, (h + 2 * margin) * 2) {
            setContent {
                CompositionLocalProvider(LocalReduceMotion provides reduceMotion, LocalDensity provides Density(2f)) {
                    Box(Modifier.fillMaxSize().background(Color(0xFF59605B)).padding(margin.dp), Alignment.TopCenter) {
                        Box(Modifier.size(w.dp, h.dp)) { content() }
                    }
                }
            }
            waitForIdle()
            ImageIO.write(onRoot().captureToImage().toAwtImage(), "png", File(outDir, "$name.png"))
            check()
        }
    }

    private fun expanded(pages: List<IslandPageModel>, start: Int = 0) = @Composable {
        var page by remember { mutableIntStateOf(start) }
        ExpandedIsland(pages, page, s, onPage = { page = it }, onAction = {}, onClose = {})
    }

    private val ex = IslandSizes.EXPANDED_WIDTH to IslandSizes.EXPANDED_HEIGHT

    @Test fun collapsedPill() = shot(
        "01-pill", IslandSizes.COLLAPSED_WIDTH, IslandSizes.COLLAPSED_HEIGHT,
        content = { IslandPill(PillModel("Ashar 15:12", "Claude 82%", UsageLevel.WARNING, false, "Ashar in 1 hour 12 minutes. Claude 5-hour session, 82 percent used"), s, onClick = {}) },
        check = { onNodeWithContentDescription("Ashar in 1 hour 12 minutes. Claude 5-hour session, 82 percent used").assertExists() },
    )

    @Test fun pillClickExpands() {
        var clicks = 0
        shot("01b-pill-click", 300, 32, content = { IslandPill(PillModel("Ashar 15:12", "82%", UsageLevel.NORMAL, false, "pill"), s, onClick = { clicks++ }) }, check = {
            onNodeWithContentDescription("pill").performClick()
        })
        assertEquals(1, clicks)
    }

    @Test fun peek() = shot(
        "02-peek", IslandSizes.PEEK_WIDTH, IslandSizes.PEEK_HEIGHT,
        content = { IslandPeek(PeekEvent("p", "prayer", "Ashar", "in 10 minutes, at 15:12"), s, onDismiss = {}, onHold = {}) },
        check = { onNodeWithContentDescription("Ashar. in 10 minutes, at 15:12").assertExists() },
    )

    @Test fun expandedPrayerPage() = shot(
        "03-expanded-prayer", ex.first, ex.second,
        content = expanded(listOf(prayerPage) + aiPages(codex82)),
        check = {
            // The sentence Narrator reads for the slider.
            val node = onNodeWithContentDescription("Ashar in 1 hour 12 minutes, 62 percent of the time since the previous prayer")
            node.assertRangeInfoEquals(ProgressBarRangeInfo(0.6210526f, 0f..1f))
            node.assertExists()
        },
    )

    @Test fun expandedUsageAmber() = shot(
        "04-expanded-ai-amber", ex.first, ex.second,
        content = expanded(listOf(prayerPage) + aiPages(codex82), start = 1),
        check = {
            onNodeWithContentDescription("Codex 5-hour session, 82 percent used, resets in 1 hour 12 minutes").assertExists()
        },
    )

    @Test fun expandedUsageRed() = shot(
        "05-expanded-ai-red", ex.first, ex.second,
        content = expanded(aiPages(AiUsageSample("Codex", 0.97, Duration.ofMinutes(35), "5h")), start = 0),
    )

    @Test fun expandedUsageLowAndFull() {
        shot("06-expanded-ai-low", ex.first, ex.second, content = expanded(aiPages(AiUsageSample("Codex work", 0.03, Duration.ofHours(4), "week"))))
        shot("07-expanded-ai-full", ex.first, ex.second, content = expanded(aiPages(AiUsageSample("Codex", 1.0, null, "5h"))))
    }

    @Test fun expandedClaudeTokens() = shot(
        "09-expanded-ai-claude-tokens", ex.first, ex.second,
        content = expanded(listOf(prayerPage) + aiPages(claudeTokens, codex82), start = 1),
        check = {
            // A count with no known limit: no %, no progress range for Narrator to read as a level.
            val node = onNodeWithContentDescription("Claude 5-hour session, 4.2 million tokens used, resets in 3 hours")
            node.assertExists()
            assertEquals(null, node.fetchSemanticsNode().config.getOrElseNullable(androidx.compose.ui.semantics.SemanticsProperties.ProgressBarRangeInfo) { null })
        },
    )

    @Test fun expandedEmptyUsage() = shot(
        "08-expanded-ai-empty", ex.first, ex.second,
        content = expanded(listOf(prayerPage) + aiPages(), start = 1),
        check = { onNodeWithContentDescription(s.noUsageDescription).assertExists() },
    )

    @Test fun reduceMotionStillRenders() = shot(
        "09-expanded-reduce-motion", ex.first, ex.second, reduceMotion = true,
        content = expanded(listOf(prayerPage) + aiPages(codex82)),
    )

    @Test fun arrowKeysAndDotsSwitchPagesAndEscCloses() {
        var closed = 0
        var page = -1
        runDesktopComposeUiTest(420, 112) {
            setContent {
                var p by remember { mutableIntStateOf(0) }
                page = p
                ExpandedIsland(listOf(prayerPage) + aiPages(codex82), p, s, onPage = { p = it }, onAction = {}, onClose = { closed++ })
            }
            waitForIdle()
            onRoot().performKeyInput { pressKey(Key.DirectionRight) }
            waitForIdle()
            assertEquals(1, page)
            onRoot().performKeyInput { pressKey(Key.DirectionRight) } // already on the last page
            waitForIdle()
            assertEquals(1, page)
            onRoot().performKeyInput { pressKey(Key.DirectionLeft) }
            waitForIdle()
            assertEquals(0, page)
            onNodeWithContentDescription("Page 2 of 2").performClick()
            waitForIdle()
            assertEquals(1, page)
            onRoot().performKeyInput { pressKey(Key.Escape) }
            assertEquals(1, closed)
        }
    }

    @Test fun buttonIsLabelledAndClickable() {
        var action: ButtonAction? = null
        runDesktopComposeUiTest(420, 112) {
            setContent { ExpandedIsland(aiPages(codex82), 0, s, onPage = {}, onAction = { action = it }, onClose = {}) }
            waitForIdle()
            onNodeWithContentDescription("Refresh usage").performClick()
        }
        assertEquals(ButtonAction.REFRESH, action)
    }

    @Test fun contentSwitchesWithTheState() {
        var mode by mutableStateOf<NotchState>(NotchState.Collapsed)
        runDesktopComposeUiTest(420, 112) {
            setContent {
                IslandContent(
                    mode, PillModel("Ashar 15:12", "82%", UsageLevel.NORMAL, false, "the pill"), listOf(prayerPage), 0, s,
                    onPillClick = {}, onPage = {}, onAction = {}, onClose = {}, onPeekDismiss = {}, onPeekHold = {},
                    reduceMotion = true,
                )
            }
            waitForIdle()
            onNodeWithContentDescription("the pill").assertExists()
            mode = NotchState.Expanded
            mainClock.advanceTimeBy(600)
            waitForIdle()
            onNodeWithContentDescription("Settings").assertExists()
        }
    }

    @Test fun settingsWindow() {
        runDesktopComposeUiTest(520 * 2, 720 * 2) {
            setContent {
                CompositionLocalProvider(LocalDensity provides Density(2f)) {
                    SettingsScreen(DesktopSettings(claudeDirs = listOf("C:\\Users\\me\\.claude", "C:\\Users\\me\\.claude-work")), onChange = {}, launchAtLoginSupported = true, effectiveReduceMotion = false)
                }
            }
            waitForIdle()
            ImageIO.write(onRoot().captureToImage().toAwtImage(), "png", File(outDir, "10-settings.png"))
            onNodeWithContentDescription("City, Jakarta").assertExists()
        }
    }
}
