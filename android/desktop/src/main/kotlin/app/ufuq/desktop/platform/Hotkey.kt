package app.ufuq.desktop.platform

import com.github.kwhat.jnativehook.GlobalScreen
import com.github.kwhat.jnativehook.keyboard.NativeKeyEvent
import com.github.kwhat.jnativehook.keyboard.NativeKeyListener
import java.util.logging.Level
import java.util.logging.Logger

/** The keys the chord cares about; everything else is [OTHER]. */
enum class ChordKey { WIN, ALT, SPACE, OTHER }

/**
 * Detects Win+Alt+Space from a stream of key events. Pure, so it is unit-tested. (Alt+Space is the
 * window menu, so the chord needs the Windows key.) It fires once per press of Space and again only
 * after Space was released, so key auto-repeat does not toggle the island repeatedly.
 */
class ChordDetector {
    private var win = false
    private var alt = false
    private var spaceDown = false

    /** Returns true when this event completes the chord. */
    fun onKey(key: ChordKey, pressed: Boolean): Boolean {
        when (key) {
            ChordKey.WIN -> win = pressed
            ChordKey.ALT -> alt = pressed
            ChordKey.SPACE -> {
                if (!pressed) {
                    spaceDown = false
                } else if (!spaceDown) {
                    spaceDown = true
                    return win && alt
                }
            }
            ChordKey.OTHER -> Unit
        }
        return false
    }
}

/**
 * The global hotkey, through JNativeHook's keyboard hook (it sees Win combinations that
 * RegisterHotKey would refuse). A no-op off Windows, so Linux CI and dev machines never load the native library.
 */
class GlobalHotkey(private val onChord: () -> Unit) : AutoCloseable {
    private var listener: NativeKeyListener? = null

    /** Returns false when the hook could not start (not Windows, or the OS refused). */
    fun start(): Boolean {
        if (!Windows.isWindows) return false
        return try {
            Logger.getLogger(GlobalScreen::class.java.`package`.name).apply {
                level = Level.OFF
                useParentHandlers = false
            }
            val detector = ChordDetector()
            val l = object : NativeKeyListener {
                override fun nativeKeyPressed(e: NativeKeyEvent) {
                    if (detector.onKey(map(e.keyCode), true)) onChord()
                }

                override fun nativeKeyReleased(e: NativeKeyEvent) {
                    detector.onKey(map(e.keyCode), false)
                }
            }
            GlobalScreen.registerNativeHook()
            GlobalScreen.addNativeKeyListener(l)
            listener = l
            true
        } catch (e: Throwable) {
            false
        }
    }

    override fun close() {
        if (!Windows.isWindows) return
        runCatching {
            listener?.let { GlobalScreen.removeNativeKeyListener(it) }
            GlobalScreen.unregisterNativeHook()
        }
        listener = null
    }

    private fun map(code: Int): ChordKey = when (code) {
        NativeKeyEvent.VC_META -> ChordKey.WIN
        NativeKeyEvent.VC_ALT -> ChordKey.ALT
        NativeKeyEvent.VC_SPACE -> ChordKey.SPACE
        else -> ChordKey.OTHER
    }
}
