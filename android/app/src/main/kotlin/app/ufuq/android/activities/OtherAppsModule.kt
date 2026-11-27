package app.ufuq.android.activities

import app.ufuq.android.island.ButtonAction
import app.ufuq.android.island.IslandIcon
import app.ufuq.android.island.IslandPageId
import app.ufuq.android.island.IslandPageModel
import app.ufuq.android.island.SliderModel
import app.ufuq.core.LiveActivity
import app.ufuq.core.ModuleStatus
import app.ufuq.core.UfuqModule
import java.time.Instant

/**
 * Other apps' ongoing notifications as one island activity (the newest allowed one). Off until the
 * user turns it on and allows apps; in-memory only.
 */
class OtherAppsModule(private val strings: ActivityStrings, private val ownPackage: String) : UfuqModule {
    override val id = OngoingMapper.MODULE_ID
    override val title = "Other apps"
    override var isEnabled: Boolean = false
    override val status: ModuleStatus = ModuleStatus.Ok

    @Volatile private var shown: List<OngoingNotification> = emptyList()

    /** Feeds the latest notifications and settings. Cheap; call on every change. */
    fun update(all: List<OngoingNotification>, enabled: Boolean, allowed: Set<String>) {
        shown = ActivityAllowList.filter(all, enabled, allowed, ownPackage)
        isEnabled = enabled
    }

    fun current(): OngoingNotification? = shown.firstOrNull()

    override fun collapsedActivity(now: Instant): LiveActivity? = current()?.let { OngoingMapper.toActivity(it, now, strings) }

    override fun accessibilitySummary(): String = current()?.let { OngoingMapper.toActivity(it, Instant.now(), strings).accessibilityLabel }.orEmpty()

    /** The expanded page for the current activity, or null. */
    fun page(now: Instant): IslandPageModel? = current()?.let { ActivityPages.page(it, now, strings) }

    /** Opens the current activity's source app. */
    fun openCurrent() {
        runCatching { current()?.open?.invoke() }
    }
}

object ActivityPages {
    /** A determinate bar fills by current/max; an indeterminate one is label-only (empty track). */
    fun page(n: OngoingNotification, now: Instant, s: ActivityStrings): IslandPageModel {
        val detail = OngoingMapper.detail(n, now, s)
        val fraction = OngoingMapper.progressFraction(n)
        val percent = fraction?.let { (it * 100).toInt() }
        val description = listOfNotNull(n.appLabel, detail?.spoken, percent?.takeIf { detail?.short != s.percent(it) }?.let(s::percentSpoken))
            .joinToString(", ")
        return IslandPageModel(
            id = IslandPageId.OTHER,
            slider = SliderModel(
                fraction = fraction?.toFloat() ?: 0f,
                label = n.appLabel,
                secondary = detail?.short,
                trailing = percent?.takeIf { detail?.short != s.percent(it) }?.let(s::percent),
                description = description,
                stateText = percent?.let(s::percentSpoken) ?: detail?.spoken ?: n.appLabel,
            ),
            buttonIcon = IslandIcon.PHONE,
            buttonLabel = s.open(n.appLabel),
            buttonAction = ButtonAction.OPEN_SOURCE,
            showBar = fraction != null,
        )
    }
}
