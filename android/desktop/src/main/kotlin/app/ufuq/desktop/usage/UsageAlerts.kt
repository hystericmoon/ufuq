package app.ufuq.desktop.usage

import app.ufuq.core.PeekEvent
import app.ufuq.core.UsageAlert
import app.ufuq.core.UsageSnapshot
import app.ufuq.core.UsageThresholds
import app.ufuq.desktop.island.AiUsageSample
import app.ufuq.desktop.island.IslandStrings
import java.time.Instant

/** Peek alerts when a real limit crosses amber (80%) or red (95%) or a window resets. Pure. */
object UsageAlerts {
    private fun key(s: AiUsageSample) = "${s.provider}|${s.window}"

    private fun snapshot(s: AiUsageSample, now: Instant) =
        UsageSnapshot(s.fraction, now, s.resetsIn?.let { now.plus(it) })

    fun peeks(
        previous: List<AiUsageSample>,
        current: List<AiUsageSample>,
        now: Instant,
        strings: IslandStrings,
        thresholds: UsageThresholds = UsageThresholds.DEFAULT,
    ): List<PeekEvent> {
        val before = previous.associateBy(::key)
        // Token counts have no limit, so nothing to cross.
        return current.filterNot { it.isTokenCount }.mapNotNull { sample ->
            val old = before[key(sample)] ?: return@mapNotNull null
            val alert = thresholds.alert(snapshot(old, now), snapshot(sample, now)) ?: return@mapNotNull null
            val percent = (sample.fraction * 100).toInt()
            val name = listOfNotNull(sample.provider, sample.window).joinToString(" ")
            val (title, message) = when (alert) {
                UsageAlert.REACHED_WARNING -> "$name at ${strings.percent(percent)}" to "Usage passed ${(thresholds.warning * 100).toInt()} percent"
                UsageAlert.REACHED_CRITICAL -> "$name at ${strings.percent(percent)}" to "Usage passed ${(thresholds.critical * 100).toInt()} percent"
                UsageAlert.RESET -> "$name reset" to "A new usage window started"
            }
            PeekEvent(
                id = "ai.${key(sample)}.$alert.${now.epochSecond}",
                moduleId = "ai",
                title = title,
                message = message,
                priority = alert.peekPriority,
                announcement = "$title. $message",
            )
        }
    }
}
