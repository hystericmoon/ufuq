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

/** What the Live Update chip shows. */
data class LiveUpdateContent(val progress: PrayerProgress, val zone: ZoneId) {
    /** "Ashar 15:12": short enough for the status-bar chip, and still right until the next boundary. */
    val chipText: String get() = "${progress.name} ${PrayerFormat.clock(progress.next, zone)}"
    val title: String get() = "${progress.name} ${PrayerFormat.clock(progress.next, zone)}"
    val text: String get() = progress.location
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
    private fun buildCompat(context: Context, c: LiveUpdateContent): Notification {
        val p = c.progress
        return NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(ContextCompat.getColor(context, R.color.notification_accent))
            .setContentTitle(c.title)
            .setContentText(c.text)
            .setContentIntent(openIntent(context))
            .setWhen(p.next.toEpochMilli())
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setProgress(PROGRESS_MAX, (p.fraction * PROGRESS_MAX).toInt(), false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setRequestPromotedOngoing(true)
            .setShortCriticalText(c.chipText)
            .build()
    }

    /** Android 16+: platform builder, so the real ProgressStyle (previous prayer to next) is used. */
    @androidx.annotation.RequiresApi(36)
    @android.annotation.SuppressLint("NewApi") // setRequestPromotedOngoing is 36.1; guarded below
    private fun buildPromoted(context: Context, c: LiveUpdateContent): Notification {
        val p = c.progress
        val total = Duration.between(p.previous, p.next).seconds.toInt().coerceAtLeast(1)
        val elapsed = Duration.between(p.previous, p.now).seconds.toInt().coerceIn(0, total)
        val accent = ContextCompat.getColor(context, R.color.notification_accent)
        val style = Notification.ProgressStyle()
            .setStyledByProgress(false)
            .addProgressSegment(Notification.ProgressStyle.Segment(total).setColor(accent))
            .setProgress(elapsed)
        val builder = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(accent)
            .setContentTitle(c.title)
            .setContentText(c.text)
            .setContentIntent(openIntent(context))
            .setWhen(p.next.toEpochMilli())
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setStyle(style)
        // The chip setters arrived in Android 16 QPR (API 36.1); on 36.0 they are missing, and the
        // notification is then simply the ongoing ProgressStyle one.
        try {
            builder.setShortCriticalText(c.chipText).setRequestPromotedOngoing(true)
        } catch (_: NoSuchMethodError) {
        }
        return builder.build()
    }

    private const val PROGRESS_MAX = 1000
}
