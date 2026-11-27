package app.ufuq.core.prayer

import app.ufuq.core.ActivitySource
import app.ufuq.core.ModuleRegistry
import app.ufuq.core.ModuleStatus
import app.ufuq.core.PeekEvent
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runTest
import org.junit.Test
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class PrayerModuleTest {
    private val zone = ZoneId.of("Asia/Jakarta")

    private fun at(d: Int, h: Int, m: Int, s: Int = 0, month: Int = 10, z: ZoneId = zone): Instant =
        LocalDateTime.of(2026, month, d, h, m, s).atZone(z).toInstant()

    private fun module(now: Instant) = PrayerModule(location = PrayerLocation.JAKARTA, clock = { now })

    private fun schedule(d: Int) = PrayerCalculator().schedule(
        LocalDate.of(2026, 10, d), PrayerLocation.JAKARTA.latitude, PrayerLocation.JAKARTA.longitude,
        zone, CalculationSettings(),
    )

    @Test
    fun `id and defaults`() {
        val m = module(at(21, 12, 0))
        assertEquals("prayer", m.id)
        assertTrue(m.isEnabled)
        assertEquals(ModuleStatus.Ok, m.status)
    }

    @Test
    fun `activity shows next prayer with deadline`() {
        val now = at(21, 12, 0)
        val a = assertNotNull(module(now).collapsedActivity(now))
        val ashar = schedule(21).asr
        assertEquals(ActivitySource.PRAYER, a.source)
        assertEquals("prayer", a.moduleId)
        assertEquals(ashar, a.deadline)
        assertEquals("Ashar ${PrayerFormat.clock(ashar, zone)}", a.text)
        assertTrue(a.text.startsWith("Ashar "))
        assertFalse(a.isAlert)
    }

    @Test
    fun `accessibility label says time remaining`() {
        val now = schedule(21).asr.minusSeconds(72 * 60)
        val a = assertNotNull(module(now).collapsedActivity(now))
        assertEquals("Ashar in 1 hour 12 minutes", a.accessibilityLabel)
    }

    @Test
    fun `spoken formats`() {
        assertEquals("2 hours", PrayerFormat.spoken(Duration.ofHours(2)))
        assertEquals("1 minute", PrayerFormat.spoken(Duration.ofMinutes(1)))
        assertEquals("45 minutes", PrayerFormat.spoken(Duration.ofSeconds(45 * 60 - 10)))
        assertEquals("1 minute", PrayerFormat.spoken(Duration.ofSeconds(20)))
        assertEquals("less than a minute", PrayerFormat.spoken(Duration.ZERO))
    }

    @Test
    fun `Friday shows Jumat`() {
        val now = at(23, 9, 0)
        val a = assertNotNull(module(now).collapsedActivity(now))
        assertTrue(a.text.startsWith("Jumat "), a.text)
    }

    @Test
    fun `pre-adhan peek within the lead is normal`() {
        val now = schedule(21).asr.minusSeconds(9 * 60)
        val peek = assertNotNull(module(now).duePeek(now))
        assertEquals(PeekEvent.Priority.NORMAL, peek.priority)
        assertEquals("prayer", peek.moduleId)
        assertEquals("Ashar", peek.title)
        assertTrue(peek.announcement.contains("Ashar in 9 minutes"), peek.announcement)
    }

    @Test
    fun `no peek before the lead window`() {
        val now = schedule(21).asr.minusSeconds(11 * 60)
        assertNull(module(now).duePeek(now))
    }

    @Test
    fun `pre-adhan lead is configurable`() {
        val now = schedule(21).asr.minusSeconds(14 * 60)
        val m = PrayerModule(location = PrayerLocation.JAKARTA, preAdhanLead = Duration.ofMinutes(15), clock = { now })
        assertNotNull(m.duePeek(now))
    }

    @Test
    fun `adhan peek is critical and the activity is an alert`() {
        val now = schedule(21).asr.plusSeconds(5)
        val m = module(now)
        val peek = assertNotNull(m.duePeek(now))
        assertEquals(PeekEvent.Priority.CRITICAL, peek.priority)
        assertEquals("Ashar", peek.title)
        val a = assertNotNull(m.collapsedActivity(now))
        assertTrue(a.isAlert)
        assertEquals("Ashar now", a.text)
    }

    @Test
    fun `no adhan peek at sunrise and after the window`() {
        val s = schedule(21)
        val atSunrise = s.sunrise.plusSeconds(5)
        assertNull(module(atSunrise).duePeek(atSunrise))
        val late = s.asr.plus(PrayerPeeks.ADHAN_WINDOW).plusSeconds(1)
        assertNull(module(late).duePeek(late))
    }

    @Test
    fun `peek ids are stable per prayer and day`() {
        val asr = schedule(21).asr
        val t1 = asr.minusSeconds(9 * 60)
        val t2 = asr.minusSeconds(3 * 60)
        val m = module(t1)
        assertEquals(assertNotNull(m.duePeek(t1)).id, assertNotNull(m.duePeek(t2)).id)
    }

    @Test
    fun `unavailable when no times can be calculated`() {
        val utc = ZoneId.of("UTC")
        val now = at(21, 12, 0, month = 6, z = utc)
        val pole = PrayerLocation("Pole", 85.0, 0.0, utc)
        val m = PrayerModule(location = pole, settings = CalculationSettings(method = CalcMethod.MWL), clock = { now })
        assertTrue(m.status is ModuleStatus.Unavailable)
        assertFailsWith<PrayerTimesUnavailableException> { m.collapsedActivity(now) }
        assertNull(m.duePeek(now))
    }

    @Test
    fun `registry loads the module`() {
        val now = at(21, 12, 0)
        val registry = ModuleRegistry()
        registry.register(module(now))
        assertEquals(1, registry.activities(now).size)
    }

    @Test
    fun `registry skips the module when its times cannot be calculated`() {
        val utc = ZoneId.of("UTC")
        val now = at(21, 12, 0, month = 6, z = utc)
        val registry = ModuleRegistry()
        registry.register(PrayerModule(PrayerLocation("Pole", 85.0, 0.0, utc), CalculationSettings(method = CalcMethod.MWL), clock = { now }))
        assertEquals(0, registry.activities(now).size)
    }

    @Test
    fun `summary`() {
        val now = schedule(21).asr.minusSeconds(60 * 60)
        assertTrue(module(now).accessibilitySummary().contains("Next prayer Ashar"))
    }

    @Test
    fun `peek flow emits each due peek once`() = runTest {
        var now = schedule(21).asr.minusSeconds(9 * 60)
        val m = PrayerModule(location = PrayerLocation.JAKARTA, clock = { now }, pollInterval = Duration.ofMillis(1))
        val got = mutableListOf<PeekEvent>()
        val job = launch { m.peekEvents().toList(got) }
        advanceTimeBy(100)
        assertEquals(listOf(PeekEvent.Priority.NORMAL), got.map { it.priority }, "the pre-adhan peek is not repeated")
        now = schedule(21).asr.plusSeconds(1)
        advanceTimeBy(100)
        assertEquals(listOf(PeekEvent.Priority.NORMAL, PeekEvent.Priority.CRITICAL), got.map { it.priority })
        job.cancel()
    }
}
