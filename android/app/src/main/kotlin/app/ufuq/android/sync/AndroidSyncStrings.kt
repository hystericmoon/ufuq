package app.ufuq.android.sync

import android.content.Context
import app.ufuq.android.R
import java.time.Duration

/** [SyncStrings] from Android resources. */
class AndroidSyncStrings(private val context: Context) : SyncStrings {
    override val connectingTitle get() = context.getString(R.string.sync_connecting_title)
    override val connectingHint get() = context.getString(R.string.sync_connecting_hint)
    override val connectingDescription get() = context.getString(R.string.sync_connecting_description)
    override val pairAgainTitle get() = context.getString(R.string.sync_pair_again_title)
    override val pairAgainHint get() = context.getString(R.string.sync_pair_again_hint)
    override val pairAgainDescription get() = context.getString(R.string.sync_pair_again_description)
    override val pairButton get() = context.getString(R.string.sync_pair_button)
    override val unreachableTitle get() = context.getString(R.string.sync_unreachable_title)
    override val unreachableHint get() = context.getString(R.string.sync_unreachable_hint)
    override val unreachableDescription get() = context.getString(R.string.sync_unreachable_description)
    override fun staleTrailing(age: Duration) = context.getString(R.string.sync_stale_trailing)
    override fun staleDescription(usageDescription: String, age: Duration) =
        context.getString(R.string.sync_stale_description, usageDescription, ago(age, spoken = true))
    override fun problemDescription(reason: String) = context.getString(R.string.sync_problem_description, reason)
    override val agentWorking get() = context.getString(R.string.sync_agent_working)
    override val agentNeedsInput get() = context.getString(R.string.sync_agent_needs_input)
    override fun agentWorkingLabel(title: String) = context.getString(R.string.sync_agent_working_label, title)
    override fun agentNeedsInputLabel(title: String) = context.getString(R.string.sync_agent_needs_input_label, title)
    override val agentNeedsInputPeekTitle get() = context.getString(R.string.sync_peek_needs_input)
    override val agentDonePeekTitle get() = context.getString(R.string.sync_peek_task_done)

    private fun ago(age: Duration, spoken: Boolean): String {
        val minutes = age.toMinutes().toInt()
        val hours = minutes / 60
        return when {
            minutes < 1 -> context.getString(R.string.sync_just_now)
            hours < 1 -> context.resources.getQuantityString(R.plurals.sync_minutes_ago_spoken, minutes, minutes)
            else -> context.resources.getQuantityString(R.plurals.sync_hours_ago_spoken, hours, hours)
        }
    }
}
