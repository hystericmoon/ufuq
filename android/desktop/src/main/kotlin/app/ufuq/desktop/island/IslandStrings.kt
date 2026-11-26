package app.ufuq.desktop.island

/** English texts (the desktop app has no localisation yet; Indonesian comes with the Android strings later). */
object EnglishIslandStrings : IslandStrings {
    override val openSettings = "Settings"
    override val refreshUsage = "Refresh usage"
    override val noUsageTitle = "AI usage"
    override val noUsageHint = "No Claude or Codex logs found"
    override val noUsageDescription = "AI usage unavailable. No Claude or Codex logs found. Open Settings to add a Claude folder."
    override val estimated = "estimated"
    override val expand = "Open Ufuq"
    override val close = "Close"
    override val dismiss = "Dismiss"
    override fun pageOf(index: Int, count: Int) = "Page $index of $count"
    override fun percent(value: Int) = "$value%"
    override fun percentSpoken(value: Int) = "$value percent"
    override fun prayerDescription(name: String, spoken: String, percent: Int) =
        "$name in $spoken, $percent percent of the time since the previous prayer"
    override fun usageDescription(provider: String, window: String?, percent: Int, estimated: Boolean, resetsSpoken: String?): String {
        val windowText = window?.let { " ${spokenWindow(it)}" }.orEmpty()
        val estimate = if (estimated) ", estimated" else ""
        val resets = resetsSpoken?.let { ", resets in $it" }.orEmpty()
        return "$provider$windowText, $percent percent used$estimate$resets"
    }

    private fun spokenWindow(window: String) = when (window) {
        "5h" -> "5-hour session"
        "week" -> "weekly limit"
        else -> window
    }
}
