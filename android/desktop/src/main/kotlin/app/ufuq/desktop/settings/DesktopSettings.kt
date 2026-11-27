package app.ufuq.desktop.settings

import app.ufuq.core.prayer.CalcMethod
import app.ufuq.core.prayer.CalculationSettings
import app.ufuq.core.prayer.PrayerLocation
import java.io.File
import java.time.ZoneId
import java.util.Properties

/** Everything the user can change on desktop. Defaults: Jakarta, Kemenag, `%USERPROFILE%\.claude`. */
data class DesktopSettings(
    val cityName: String = Cities.DEFAULT.name,
    val method: CalcMethod = CalcMethod.KEMENAG,
    /** Claude config folders, one per account. Empty means the default (`CLAUDE_CONFIG_DIR` or `%USERPROFILE%\.claude`). */
    val claudeDirs: List<String> = emptyList(),
    val launchAtLogin: Boolean = false,
    /** null follows Windows "Animation effects"; true or false is the user's choice. */
    val reduceMotion: Boolean? = null,
    /** Ask GitHub once a day for a new version. */
    val autoCheckUpdates: Boolean = true,
    /** Also offer pre-releases. */
    val betaUpdates: Boolean = false,
    /** Epoch millis of the last update check; 0 means never. */
    val lastUpdateCheck: Long = 0L,
) {
    val location: PrayerLocation get() = Cities.byName(cityName) ?: Cities.DEFAULT

    val calculation: CalculationSettings get() = CalculationSettings(method = method)

    companion object {
        val METHODS = listOf(CalcMethod.KEMENAG, CalcMethod.MWL, CalcMethod.UMM_AL_QURA)
    }
}

// Copied from :app (app.ufuq.android.settings.Cities); the same 12 cities.
/** The manual city list. Jakarta first and the default. */
object Cities {
    val DEFAULT = PrayerLocation.JAKARTA

    val ALL: List<PrayerLocation> = listOf(
        PrayerLocation.JAKARTA,
        PrayerLocation("Bandung", -6.9175, 107.6191, ZoneId.of("Asia/Jakarta"), elevation = 768),
        PrayerLocation("Surabaya", -7.2575, 112.7521, ZoneId.of("Asia/Jakarta")),
        PrayerLocation("Yogyakarta", -7.7956, 110.3695, ZoneId.of("Asia/Jakarta")),
        PrayerLocation("Medan", 3.5952, 98.6722, ZoneId.of("Asia/Jakarta")),
        PrayerLocation("Makassar", -5.1477, 119.4327, ZoneId.of("Asia/Makassar")),
        PrayerLocation("Denpasar", -8.6705, 115.2126, ZoneId.of("Asia/Makassar")),
        PrayerLocation("Jayapura", -2.5337, 140.7181, ZoneId.of("Asia/Jayapura")),
        PrayerLocation("Kuala Lumpur", 3.1390, 101.6869, ZoneId.of("Asia/Kuala_Lumpur")),
        PrayerLocation("Singapore", 1.3521, 103.8198, ZoneId.of("Asia/Singapore")),
        PrayerLocation("Makkah", 21.4225, 39.8262, ZoneId.of("Asia/Riyadh")),
        PrayerLocation("Madinah", 24.4672, 39.6111, ZoneId.of("Asia/Riyadh")),
    )

    fun byName(name: String): PrayerLocation? = ALL.firstOrNull { it.name == name }
}

/** Settings in a small `.properties` file: `%APPDATA%\Ufuq\settings.properties` on Windows, `~/.config/ufuq` elsewhere. */
class SettingsStore(private val file: File) {
    fun load(): DesktopSettings = try {
        if (file.isFile) file.inputStream().use { fromProperties(Properties().apply { load(it) }) } else DesktopSettings()
    } catch (e: Exception) {
        DesktopSettings()
    }

    fun save(settings: DesktopSettings) {
        try {
            file.parentFile?.mkdirs()
            file.outputStream().use { toProperties(settings).store(it, "Ufuq settings") }
        } catch (_: Exception) {
            // A read-only profile must not crash the app; the settings simply do not persist.
        }
    }

    companion object {
        fun default(env: Map<String, String> = System.getenv(), home: String = System.getProperty("user.home") ?: "."): SettingsStore {
            val dir = env["APPDATA"]?.takeIf { it.isNotBlank() }?.let { File(it, "Ufuq") } ?: File(home, ".config/ufuq")
            return SettingsStore(File(dir, "settings.properties"))
        }

        fun toProperties(s: DesktopSettings): Properties = Properties().apply {
            setProperty("city", s.cityName)
            setProperty("method", s.method.name)
            setProperty("launchAtLogin", s.launchAtLogin.toString())
            s.reduceMotion?.let { setProperty("reduceMotion", it.toString()) }
            setProperty("autoCheckUpdates", s.autoCheckUpdates.toString())
            setProperty("betaUpdates", s.betaUpdates.toString())
            setProperty("lastUpdateCheck", s.lastUpdateCheck.toString())
            setProperty("claudeDirs.count", s.claudeDirs.size.toString())
            s.claudeDirs.forEachIndexed { i, d -> setProperty("claudeDirs.$i", d) }
        }

        fun fromProperties(p: Properties): DesktopSettings {
            val d = DesktopSettings()
            val count = p.getProperty("claudeDirs.count")?.toIntOrNull()?.coerceIn(0, 32) ?: 0
            return DesktopSettings(
                cityName = p.getProperty("city")?.takeIf { Cities.byName(it) != null } ?: d.cityName,
                method = p.getProperty("method")?.let { m -> DesktopSettings.METHODS.firstOrNull { it.name == m } } ?: d.method,
                claudeDirs = (0 until count).mapNotNull { p.getProperty("claudeDirs.$it")?.takeIf(String::isNotBlank) },
                launchAtLogin = p.getProperty("launchAtLogin")?.toBooleanStrictOrNull() ?: d.launchAtLogin,
                reduceMotion = p.getProperty("reduceMotion")?.toBooleanStrictOrNull(),
                autoCheckUpdates = p.getProperty("autoCheckUpdates")?.toBooleanStrictOrNull() ?: d.autoCheckUpdates,
                betaUpdates = p.getProperty("betaUpdates")?.toBooleanStrictOrNull() ?: d.betaUpdates,
                lastUpdateCheck = p.getProperty("lastUpdateCheck")?.toLongOrNull()?.takeIf { it >= 0 } ?: d.lastUpdateCheck,
            )
        }
    }
}
