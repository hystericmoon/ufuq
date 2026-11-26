package app.ufuq.android.live

import android.app.Notification
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.ufuq.android.Fixtures
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import java.time.ZoneId
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@RunWith(AndroidJUnit4::class)
class LiveUpdateTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val content = LiveUpdateContent(Fixtures.oneHourTwelve, ZoneId.of("Asia/Jakarta"))

    @Test fun chipTextIsNameAndTime() {
        assertEquals("Ashar 15:12", content.chipText)
    }

    @Test @Config(sdk = [36])
    fun api36IsAnOngoingProgressStyleNotificationEvenWithoutThePromotionSetters() {
        val n = LiveUpdate.build(context, content)
        assertTrue(n.flags and Notification.FLAG_ONGOING_EVENT != 0)
        assertEquals("Ashar 15:12", n.extras.getCharSequence(Notification.EXTRA_TITLE).toString())
        assertEquals(Fixtures.ashar.toEpochMilli(), n.`when`)
        assertTrue(n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
        assertTrue(n.extras.getBoolean(Notification.EXTRA_CHRONOMETER_COUNT_DOWN))
        // Robolectric's API 36 is 36.0, which has no promotion setters: the build must survive that.
        // The promotion flags themselves are checked on a device (see the A2 report).
        assertEquals(Notification.ProgressStyle::class.java.name, n.extras.getString(Notification.EXTRA_TEMPLATE))
    }

    @Test @Config(sdk = [34])
    fun belowApi36IsANormalOngoingNotificationWithACountdown() {
        val n = LiveUpdate.build(context, content)
        assertTrue(n.flags and Notification.FLAG_ONGOING_EVENT != 0)
        assertEquals(Fixtures.ashar.toEpochMilli(), n.`when`)
        assertTrue(n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
        assertTrue(n.extras.getBoolean(Notification.EXTRA_CHRONOMETER_COUNT_DOWN))
        assertEquals(Notification.VISIBILITY_PUBLIC, n.visibility)
        assertTrue(n.extras.getInt(Notification.EXTRA_PROGRESS_MAX) > 0)
    }
}
