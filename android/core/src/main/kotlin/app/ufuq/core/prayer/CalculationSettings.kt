package app.ufuq.core.prayer

enum class CalcMethod { KEMENAG, MWL, UMM_AL_QURA, CUSTOM }

enum class AsrMethod { STANDARD, HANAFI }

data class PrayerOffsets(
    val fajr: Int = 0,
    val sunrise: Int = 0,
    val dhuhr: Int = 0,
    val asr: Int = 0,
    val maghrib: Int = 0,
    val isha: Int = 0,
)

data class CalculationSettings(
    val method: CalcMethod = CalcMethod.KEMENAG,
    val customFajrAngle: Double = 20.0,
    val customIshaAngle: Double = 18.0,
    val asr: AsrMethod = AsrMethod.STANDARD,
    val offsets: PrayerOffsets = PrayerOffsets(),
    /** Minutes after sunrise until the sun is considered fully risen. */
    val sunriseRiseMinutes: Int = 15,
    /** Length of the prohibited window before Dhuhr at zawal. */
    val zawalMinutes: Int = 10,
)
