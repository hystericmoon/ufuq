package app.ufuq.desktop.platform

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ChordDetectorTest {
    @Test fun winAltSpaceFiresOnce() {
        val d = ChordDetector()
        assertFalse(d.onKey(ChordKey.WIN, true))
        assertFalse(d.onKey(ChordKey.ALT, true))
        assertTrue(d.onKey(ChordKey.SPACE, true))
        // Auto-repeat while held does not fire again.
        assertFalse(d.onKey(ChordKey.SPACE, true))
        assertFalse(d.onKey(ChordKey.SPACE, false))
        assertTrue(d.onKey(ChordKey.SPACE, true))
    }

    @Test fun altSpaceAloneIsTheWindowMenuAndDoesNotFire() {
        val d = ChordDetector()
        d.onKey(ChordKey.ALT, true)
        assertFalse(d.onKey(ChordKey.SPACE, true))
    }

    @Test fun winSpaceAloneDoesNotFire() {
        val d = ChordDetector()
        d.onKey(ChordKey.WIN, true)
        assertFalse(d.onKey(ChordKey.SPACE, true))
    }

    @Test fun releasingAModifierStopsIt() {
        val d = ChordDetector()
        d.onKey(ChordKey.WIN, true)
        d.onKey(ChordKey.ALT, true)
        d.onKey(ChordKey.ALT, false)
        assertFalse(d.onKey(ChordKey.SPACE, true))
    }

    @Test fun otherKeysAreIgnored() {
        val d = ChordDetector()
        d.onKey(ChordKey.WIN, true)
        d.onKey(ChordKey.ALT, true)
        assertFalse(d.onKey(ChordKey.OTHER, true))
        assertTrue(d.onKey(ChordKey.SPACE, true))
    }
}

class PlatformGuardTest {
    @Test fun runKeyCommandsTargetTheCurrentUser() {
        val add = LaunchAtLogin.addCommand("C:\\Users\\me\\AppData\\Local\\Ufuq\\Ufuq.exe")
        assertEquals(listOf("reg", "add"), add.take(2))
        assertTrue(add.contains("HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"))
        assertTrue(add.contains("\"C:\\Users\\me\\AppData\\Local\\Ufuq\\Ufuq.exe\""))
        assertEquals("/f", add.last())
        assertEquals(listOf("reg", "delete"), LaunchAtLogin.removeCommand().take(2))
        assertEquals(listOf("reg", "query"), LaunchAtLogin.queryCommand().take(2))
    }

    @Test fun everythingIsANoOpOffWindows() {
        if (Windows.isWindows) return
        assertFalse(LaunchAtLogin.isSupported())
        assertFalse(LaunchAtLogin.set(true))
        assertTrue(Windows.animationsEnabled())
        assertEquals(null, Windows.foregroundWindow())
        Windows.restoreForeground(null)
        assertFalse(GlobalHotkey { }.start())
    }
}
