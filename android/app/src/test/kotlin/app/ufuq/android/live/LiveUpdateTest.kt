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
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@RunWith(AndroidJUnit4::class)
class LiveUpdateTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val content = LiveUpdateContent(Fixtures.oneHourTwelve, ZoneId.of("Asia/Jakarta"))

    @Test fun chipTextIsNameAndTime() {
        assertEquals("Ashar 15:12", content.chipText)
    }

    @Test fun withoutTheIslandItSaysOnlyWhatStaysTrue() {
        assertEquals("Ashar at 15:12", content.title)
        assertEquals("Jakarta", content.text)
    }

    @Test fun withTheIslandItCountsDownInWords() {
        val ticking = content.copy(ticking = true)
        assertEquals("Ashar in 1 h 12 min", ticking.title)
        assertEquals("15:12 · Jakarta", ticking.text)
    }

    @Test fun inWordsRoundsMinutesUp() {
        assertEquals("2 h 3 min", LiveUpdateContent.inWords(java.time.Duration.ofMinutes(122).plusSeconds(20)))
        assertEquals("45 min", LiveUpdateContent.inWords(java.time.Duration.ofMinutes(45)))
        assertEquals("2 h", LiveUpdateContent.inWords(java.time.Duration.ofHours(2)))
        assertEquals("1 min", LiveUpdateContent.inWords(java.time.Duration.ofSeconds(5)))
        assertEquals("less than a minute", LiveUpdateContent.inWords(java.time.Duration.ZERO))
    }

    @Test @Config(sdk = [36])
    fun api36IsAnOngoingNotificationWithNoBarAndNoChronometer() {
        val n = LiveUpdate.build(context, content)
        assertTrue(n.flags and Notification.FLAG_ONGOING_EVENT != 0)
        assertEquals("Ashar at 15:12", n.extras.getCharSequence(Notification.EXTRA_TITLE).toString())
        // Robolectric's API 36 is 36.0, which has no promotion setters: the build must survive that.
        assertFalse(n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
        assertEquals(null, n.extras.getString(Notification.EXTRA_TEMPLATE))
    }

    @Test @Config(sdk = [34])
    fun belowApi36IsANormalOngoingNotificationWithNoBar() {
        val n = LiveUpdate.build(context, content.copy(ticking = true))
        assertTrue(n.flags and Notification.FLAG_ONGOING_EVENT != 0)
        assertEquals("Ashar in 1 h 12 min", n.extras.getCharSequence(Notification.EXTRA_TITLE).toString())
        assertFalse(n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER))
        assertEquals(Notification.VISIBILITY_PUBLIC, n.visibility)
        assertEquals(0, n.extras.getInt(Notification.EXTRA_PROGRESS_MAX))
    }
}
