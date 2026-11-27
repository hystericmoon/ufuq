package app.ufuq.android.live

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import app.ufuq.android.R
import app.ufuq.android.prayer.PrayerProgress
import app.ufuq.android.ui.MainActivity
import app.ufuq.core.prayer.PrayerFormat
import java.time.Duration
import java.time.ZoneId

/**
 * What the next-prayer notification says. With [ticking] (the island service is running and
 * reposts it every minute) the title counts down in words: "Ashar in 2 h 3 min", text
 * "15:08 · Bogor". Without it nothing updates between prayer boundaries, so it says only what
 * stays true: "Ashar at 15:08", text "Bogor". No progress bar and no system chronometer (owner,
 * 27 Nov: the chronometer ran into the title on One UI).
 */
data class LiveUpdateContent(val progress: PrayerProgress, val zone: ZoneId, val ticking: Boolean = false) {
    private val clock: String get() = PrayerFormat.clock(progress.next, zone)

    /** "Ashar 15:12": short enough for the status-bar chip, and still right until the next boundary. */
    val chipText: String get() = "${progress.name} $clock"
    val title: String get() = if (ticking) "${progress.name} in ${inWords(progress.remaining)}" else "${progress.name} at $clock"
    val text: String get() = if (ticking) listOf(clock, progress.location).filter { it.isNotBlank() }.joinToString(" · ") else progress.location

    companion object {
        /** "2 h 3 min", "45 min", "1 min"; minutes round up, so it never claims more time has passed than has. */
        fun inWords(remaining: Duration): String {
            val minutes = (remaining.seconds + 59).coerceAtLeast(0) / 60
            val h = minutes / 60
            val m = minutes % 60
            return when {
                minutes < 1 -> "less than a minute"
                h == 0L -> "$m min"
                m == 0L -> "$h h"
                else -> "$h h $m min"
            }
        }
    }
}

/**
 * The next-prayer notification. It is the accessible default surface: system-owned, so TalkBack,
 * the lock screen and the always-on display handle it. On Android 16 it asks to be promoted to a
 * Live Update chip with a [Notification.ProgressStyle] bar; before that it is a normal quiet
 * ongoing notification with the same countdown chronometer.
 */
object LiveUpdate {
    const val CHANNEL = "next_prayer"
    const val NOTIFICATION_ID = 1

    fun ensureChannel(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, context.getString(R.string.channel_live_update), NotificationManager.IMPORTANCE_LOW).apply {
                description = context.getString(R.string.channel_live_update_description)
                setShowBadge(false)
            },
        )
    }

    fun build(context: Context, content: LiveUpdateContent): Notification =
        if (Build.VERSION.SDK_INT >= 36) buildPromoted(context, content) else buildCompat(context, content)

    private fun openIntent(context: Context): PendingIntent = PendingIntent.getActivity(
        context, 0,
        Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /** API 26..35: a normal ongoing notification; the compat setters for promotion are no-ops here. */
    private fun buildCompat(context: Context, c: LiveUpdateContent): Notification =
        NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(ContextCompat.getColor(context, R.color.notification_accent))
            .setContentTitle(c.title)
            .setContentText(c.text)
            .setContentIntent(openIntent(context))
            .setShowWhen(false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setRequestPromotedOngoing(true)
            .setShortCriticalText(c.chipText)
            .build()

    /** Android 16+: the platform builder, so the Live Update chip setters are reachable. */
    @androidx.annotation.RequiresApi(36)
    @android.annotation.SuppressLint("NewApi") // setRequestPromotedOngoing is 36.1; guarded below
    private fun buildPromoted(context: Context, c: LiveUpdateContent): Notification {
        val builder = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(ContextCompat.getColor(context, R.color.notification_accent))
            .setContentTitle(c.title)
            .setContentText(c.text)
            .setContentIntent(openIntent(context))
            .setShowWhen(false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_PROGRESS)
        // The chip setters arrived in Android 16 QPR (API 36.1); on 36.0 they are missing, and the
        // notification is then simply an ongoing one.
        try {
            builder.setShortCriticalText(c.chipText).setRequestPromotedOngoing(true)
        } catch (_: NoSuchMethodError) {
        }
        return builder.build()
    }

    /** Shown by the island service when there is no prayer to show (no location yet). */
    fun fallback(context: Context): Notification =
        NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(ContextCompat.getColor(context, R.color.notification_accent))
            .setContentTitle(context.getString(R.string.island_notification_title))
            .setContentText(context.getString(R.string.island_notification_text))
            .setContentIntent(openIntent(context))
            .setOngoing(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
}
