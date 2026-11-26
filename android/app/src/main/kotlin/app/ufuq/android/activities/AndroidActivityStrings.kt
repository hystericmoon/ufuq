package app.ufuq.android.activities

import android.content.Context
import app.ufuq.android.R

/** [ActivityStrings] from Android resources. */
class AndroidActivityStrings(private val context: Context) : ActivityStrings {
    override fun minutes(value: Int) = context.getString(R.string.other_minutes, value)
    override fun minutesLeftSpoken(value: Int) = context.resources.getQuantityString(R.plurals.other_minutes_left_spoken, value, value)
    override fun minutesElapsedSpoken(value: Int) = context.resources.getQuantityString(R.plurals.other_minutes_elapsed_spoken, value, value)
    override fun percent(value: Int) = context.getString(R.string.island_percent, value)
    override fun percentSpoken(value: Int) = context.getString(R.string.island_percent_spoken, value)
    override fun open(app: String) = context.getString(R.string.other_open, app)
}
