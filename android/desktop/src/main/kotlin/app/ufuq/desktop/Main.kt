package app.ufuq.desktop

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.graphics.toComposeImageBitmap
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.ApplicationScope
import androidx.compose.ui.window.Tray
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowPosition
import androidx.compose.ui.window.application
import androidx.compose.ui.window.isTraySupported
import androidx.compose.ui.window.rememberWindowState
import app.ufuq.desktop.island.EnglishIslandStrings
import app.ufuq.desktop.island.IslandContent
import app.ufuq.desktop.island.LocalReduceMotion
import app.ufuq.desktop.platform.GlobalHotkey
import app.ufuq.desktop.platform.LaunchAtLogin
import app.ufuq.desktop.platform.Windows
import app.ufuq.desktop.settings.DesktopSettings
import app.ufuq.desktop.settings.SettingsScreen
import app.ufuq.desktop.settings.SettingsStore
import app.ufuq.desktop.usage.UsageRepository
import com.sun.jna.Pointer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.awt.Color
import java.awt.GraphicsEnvironment
import java.awt.RenderingHints
import java.awt.Toolkit
import java.awt.image.BufferedImage

/** Remembers the window that had focus before the island opened, so Esc can give it back. */
private class ForegroundKeeper {
    private var previous: Pointer? = null
    fun remember() { previous = Windows.foregroundWindow() }
    fun restore() { Windows.restoreForeground(previous); previous = null }
}

/** The primary screen's area in dp; a fixed 1080p when there is no display (headless). */
private fun primaryScreen(): ScreenRect = try {
    val config = GraphicsEnvironment.getLocalGraphicsEnvironment().defaultScreenDevice.defaultConfiguration
    val b = config.bounds
    ScreenRect(b.x, b.y, b.width, b.height, Toolkit.getDefaultToolkit().getScreenInsets(config).top)
} catch (e: Exception) {
    ScreenRect(0, 0, 1920, 1080)
}

private fun trayImage(): BufferedImage {
    val img = BufferedImage(32, 32, BufferedImage.TYPE_INT_ARGB)
    val g = img.createGraphics()
    g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
    g.color = Color.BLACK
    g.fillRoundRect(0, 8, 32, 16, 12, 12)
    g.color = Color(0xA8, 0xD8, 0xB9)
    g.fillRoundRect(5, 13, 12, 6, 6, 6)
    g.dispose()
    return img
}

@Composable
private fun ApplicationScope.IslandWindow(controller: IslandController, reduceMotion: Boolean) {
    val ui by controller.state.collectAsState()
    val kind = ui.mode.kind
    val placement = remember(kind) { WindowGeometry.place(primaryScreen(), kind) }
    val windowState = rememberWindowState(
        position = WindowPosition(placement.x.dp, placement.y.dp),
        size = DpSize(placement.width.dp, placement.height.dp),
    )
    LaunchedEffect(placement) {
        windowState.position = WindowPosition(placement.x.dp, placement.y.dp)
        windowState.size = DpSize(placement.width.dp, placement.height.dp)
    }
    val expanded = kind == NotchState.Kind.EXPANDED
    Window(
        onCloseRequest = ::exitApplication,
        state = windowState,
        title = "Ufuq",
        undecorated = true,
        transparent = true,
        resizable = false,
        alwaysOnTop = true,
        // Only the expanded island takes focus; the pill and peeks never steal it from the app you are using.
        focusable = expanded,
    ) {
        LaunchedEffect(window) {
            delay(300)
            Windows.hideFromTaskbar(window)
        }
        LaunchedEffect(expanded) {
            if (expanded) {
                window.toFront()
                Windows.bringToForeground(window)
                window.requestFocus()
            }
        }
        CompositionLocalProvider(LocalReduceMotion provides reduceMotion) {
            IslandContent(
                mode = ui.mode,
                pill = ui.pill,
                pages = ui.pages,
                pageIndex = ui.pageIndex,
                strings = EnglishIslandStrings,
                onPillClick = controller::pillClicked,
                onPage = controller::selectPage,
                onAction = controller::onAction,
                onClose = controller::escape,
                onPeekDismiss = controller::peekDismiss,
                onPeekHold = controller::peekHold,
            )
        }
    }
}

fun main() = application {
    val store = remember { SettingsStore.default() }
    var settings by remember { mutableStateOf(store.load()) }
    var settingsOpen by remember { mutableStateOf(false) }
    val usage = remember { UsageRepository() }
    val foreground = remember { ForegroundKeeper() }
    val controller = remember {
        IslandController(
            initial = settings,
            loadUsage = { s: DesktopSettings, now -> withContext(Dispatchers.IO) { usage.load(s, now) } },
            beforeOpen = foreground::remember,
            afterClose = foreground::restore,
            onOpenSettings = { settingsOpen = true },
        )
    }
    val systemReduce = remember { !Windows.animationsEnabled() }
    val reduceMotion = settings.reduceMotion ?: systemReduce

    fun change(new: DesktopSettings) {
        val loginChanged = new.launchAtLogin != settings.launchAtLogin
        settings = new
        store.save(new)
        controller.updateSettings(new)
        if (loginChanged) Thread { LaunchAtLogin.set(new.launchAtLogin) }.apply { isDaemon = true }.start()
    }

    LaunchedEffect(Unit) { controller.run() }
    DisposableEffect(Unit) {
        val hotkey = GlobalHotkey { controller.toggleWithHotkey() }
        hotkey.start()
        onDispose { hotkey.close() }
    }

    IslandWindow(controller, reduceMotion)

    if (isTraySupported) {
        val icon = remember { BitmapPainter(trayImage().toComposeImageBitmap()) }
        Tray(icon = icon, tooltip = "Ufuq", onAction = controller::pillClicked) {
            Item("Open (Win+Alt+Space)", onClick = controller::pillClicked)
            Item("Settings", onClick = { settingsOpen = true })
            CheckboxItem("Launch at login", checked = settings.launchAtLogin, onCheckedChange = { change(settings.copy(launchAtLogin = it)) })
            Separator()
            Item("Quit", onClick = ::exitApplication)
        }
    }

    if (settingsOpen) {
        Window(
            onCloseRequest = { settingsOpen = false },
            title = "Ufuq settings",
            state = rememberWindowState(size = DpSize(520.dp, 720.dp)),
        ) {
            SettingsScreen(settings, ::change, launchAtLoginSupported = LaunchAtLogin.isSupported(), effectiveReduceMotion = reduceMotion)
        }
    }
}
