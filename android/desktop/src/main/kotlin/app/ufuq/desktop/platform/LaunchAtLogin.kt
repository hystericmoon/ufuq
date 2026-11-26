package app.ufuq.desktop.platform

/**
 * "Launch at login" through the current user's Run key
 * (`HKCU\Software\Microsoft\Windows\CurrentVersion\Run`), written with the built-in `reg` tool.
 * Only an installed app (a jpackage launcher) registers itself; a dev run from Gradle does not.
 */
object LaunchAtLogin {
    const val KEY = "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"
    const val VALUE_NAME = "Ufuq"

    /** The installed launcher's path: jpackage sets `jpackage.app-path`. Null in a dev run. */
    fun appPath(): String? = System.getProperty("jpackage.app-path")?.takeIf { it.isNotBlank() }

    fun addCommand(exePath: String): List<String> =
        listOf("reg", "add", KEY, "/v", VALUE_NAME, "/t", "REG_SZ", "/d", "\"$exePath\"", "/f")

    fun removeCommand(): List<String> = listOf("reg", "delete", KEY, "/v", VALUE_NAME, "/f")

    fun queryCommand(): List<String> = listOf("reg", "query", KEY, "/v", VALUE_NAME)

    /** Whether launching at login is available here (Windows, installed). */
    fun isSupported(): Boolean = Windows.isWindows && appPath() != null

    fun isEnabled(): Boolean {
        if (!Windows.isWindows) return false
        return run(queryCommand())
    }

    /** Returns true when the registry now matches [enabled]. */
    fun set(enabled: Boolean): Boolean {
        if (!Windows.isWindows) return false
        if (!enabled) return run(removeCommand()) || !isEnabled()
        val path = appPath() ?: return false
        return run(addCommand(path))
    }

    private fun run(command: List<String>): Boolean = try {
        val process = ProcessBuilder(command).redirectErrorStream(true).start()
        process.inputStream.readBytes()
        process.waitFor() == 0
    } catch (e: Exception) {
        false
    }
}
