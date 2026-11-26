package app.ufuq.desktop.platform

import com.sun.jna.Native
import com.sun.jna.Pointer
import com.sun.jna.ptr.IntByReference
import com.sun.jna.win32.StdCallLibrary
import java.awt.Window

/**
 * Windows-only helpers behind JNA. Every call is guarded: off Windows they do nothing, and a
 * failure (a missing export, a locked-down machine) is swallowed, because the island must keep
 * working without them. Nothing here can be verified on Linux CI; see the W1 notes.
 */
object Windows {
    val isWindows: Boolean = System.getProperty("os.name").orEmpty().startsWith("Windows", ignoreCase = true)

    @Suppress("FunctionName")
    private interface User32Lib : StdCallLibrary {
        fun GetForegroundWindow(): Pointer?
        fun SetForegroundWindow(hwnd: Pointer?): Boolean
        fun IsWindow(hwnd: Pointer?): Boolean
        fun GetWindowLongW(hwnd: Pointer?, index: Int): Int
        fun SetWindowLongW(hwnd: Pointer?, index: Int, value: Int): Int
        fun ShowWindow(hwnd: Pointer?, cmd: Int): Boolean
        fun SystemParametersInfoW(action: Int, param: Int, value: IntByReference, winIni: Int): Boolean
    }

    private val user32: User32Lib? by lazy {
        if (!isWindows) null else runCatching { Native.load("user32", User32Lib::class.java) }.getOrNull()
    }

    private const val GWL_EXSTYLE = -20
    private const val WS_EX_TOOLWINDOW = 0x00000080
    private const val WS_EX_APPWINDOW = 0x00040000
    private const val SW_HIDE = 0
    private const val SW_SHOWNA = 8
    private const val SPI_GETCLIENTAREAANIMATION = 0x1042

    /** The window that has focus right now, to give it back on Esc. Null off Windows. */
    fun foregroundWindow(): Pointer? = runCatching { user32?.GetForegroundWindow() }.getOrNull()

    /** Gives focus back to [hwnd] if it still exists. */
    fun restoreForeground(hwnd: Pointer?) {
        if (hwnd == null) return
        runCatching {
            val lib = user32 ?: return
            if (lib.IsWindow(hwnd)) lib.SetForegroundWindow(hwnd)
        }
    }

    /** Brings our own window to the foreground after the hotkey (a plain toFront() is often refused by Windows). */
    fun bringToForeground(window: Window) {
        runCatching {
            val lib = user32 ?: return
            lib.SetForegroundWindow(Native.getComponentPointer(window))
        }
    }

    /**
     * Keeps the window out of the taskbar and Alt+Tab: a tool window (the closest to "type utility").
     * The style change only takes effect on a shown window after a hide and show.
     */
    fun hideFromTaskbar(window: Window) {
        runCatching {
            val lib = user32 ?: return
            val hwnd = Native.getComponentPointer(window) ?: return
            val style = lib.GetWindowLongW(hwnd, GWL_EXSTYLE)
            val wanted = (style or WS_EX_TOOLWINDOW) and WS_EX_APPWINDOW.inv()
            if (wanted != style) {
                lib.ShowWindow(hwnd, SW_HIDE)
                lib.SetWindowLongW(hwnd, GWL_EXSTYLE, wanted)
                lib.ShowWindow(hwnd, SW_SHOWNA)
            }
        }
    }

    /** Windows "Animation effects" (Settings > Accessibility > Visual effects). True when it cannot be read. */
    fun animationsEnabled(): Boolean {
        if (!isWindows) return true
        return runCatching {
            val lib = user32 ?: return true
            val enabled = IntByReference(1)
            if (lib.SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, enabled, 0)) enabled.value != 0 else true
        }.getOrDefault(true)
    }
}
