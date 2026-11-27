package app.ufuq.android.activities

import java.time.Instant

object TestActivityStrings : ActivityStrings {
    override fun minutes(value: Int) = "$value min"
    override fun minutesLeftSpoken(value: Int) = "$value minutes left"
    override fun minutesElapsedSpoken(value: Int) = "$value minutes elapsed"
    override fun percent(value: Int) = "$value%"
    override fun percentSpoken(value: Int) = "$value percent"
    override fun open(app: String) = "Open $app"
}

val NOW: Instant = Instant.parse("2026-11-26T08:00:00Z")

fun ongoing(
    key: String = "k1",
    pkg: String = "com.example.ride",
    label: String = "Ride app",
    category: String? = null,
    ongoing: Boolean = true,
    block: (OngoingNotification) -> OngoingNotification = { it },
) = block(OngoingNotification(key = key, packageName = pkg, appLabel = label, category = category, isOngoing = ongoing))
