package app.ufuq.android.silence

import android.content.Context
import android.content.Intent
import android.location.LocationManager
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.ufuq.android.settings.AppSettings
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private class FakeDnd(var access: Boolean = true, var current: Int = Filter.ALL) : DndGateway {
    override fun hasAccess() = access
    override fun currentFilter() = current
    override fun setFilter(filter: Int) { current = filter }
}

private class FakeAlarms : SilenceAlarms {
    val scheduled = mutableMapOf<AlarmKind, Long>()
    override fun schedule(kind: AlarmKind, atMillis: Long) { scheduled[kind] = atMillis }
    override fun cancel(kind: AlarmKind) { scheduled.remove(kind) }
    override fun canScheduleExact() = false
}

private class FakeProximity : ProximityRegistrar {
    var last: List<Mosque>? = null
    override fun sync(mosques: List<Mosque>) { last = mosques }
}

@RunWith(AndroidJUnit4::class)
class SilenceControllerTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val now = Instant.parse("2026-11-26T05:00:00Z")
    private val adhan = now.plusSeconds(3600)
    private val on = AppSettings(silenceEnabled = true, silenceMinutes = 15)

    private fun fixtures(dnd: FakeDnd = FakeDnd()): Triple<SilenceController, FakeDnd, FakeAlarms> {
        context.getSharedPreferences("ufuq_silence", Context.MODE_PRIVATE).edit().clear().commit()
        val alarms = FakeAlarms()
        return Triple(SilenceController(SilenceStore(context), dnd, alarms, FakeProximity()) { _, _ -> adhan }, dnd, alarms)
    }

    @Test fun refreshSchedulesTheNextAdhan() {
        val (c, _, alarms) = fixtures()
        c.onRefresh(on, now)
        assertEquals(adhan.toEpochMilli(), alarms.scheduled[AlarmKind.ADHAN])
    }

    @Test fun adhanSilencesFromTheAdhanTimeAndTheRestoreAlarmRestores() {
        val (c, dnd, alarms) = fixtures()
        c.onAdhan(on, adhan.toEpochMilli(), adhan.plusSeconds(30))
        assertEquals(Filter.PRIORITY, dnd.current)
        assertEquals(adhan.toEpochMilli() + 15 * 60_000L, alarms.scheduled[AlarmKind.RESTORE])
        c.onRestore(adhan.plusSeconds(15 * 60 + 5))
        assertEquals(Filter.ALL, dnd.current)
        assertNull(alarms.scheduled[AlarmKind.RESTORE])
    }

    @Test fun aKilledProcessIsRecoveredFromThePersistedFlagAtTheNextRefresh() {
        val (c, dnd, _) = fixtures()
        c.onAdhan(on, adhan.toEpochMilli(), adhan)
        // New controller on the same store, as after a reboot: the flag is read back and the filter restored.
        val reborn = SilenceController(SilenceStore(context), dnd, FakeAlarms(), FakeProximity()) { _, _ -> adhan }
        reborn.onRefresh(on, adhan.plusSeconds(20 * 60))
        assertEquals(Filter.ALL, dnd.current)
    }

    @Test fun switchingTheSettingOffWhileSilencedRestores() {
        val (c, dnd, alarms) = fixtures()
        c.onAdhan(on, adhan.toEpochMilli(), adhan)
        c.onRefresh(on.copy(silenceEnabled = false), adhan.plusSeconds(60))
        assertEquals(Filter.ALL, dnd.current)
        assertNull(alarms.scheduled[AlarmKind.ADHAN])
    }

    @Test fun withoutDoNotDisturbAccessNothingIsChanged() {
        val (c, dnd, _) = fixtures(FakeDnd(access = false))
        c.onAdhan(on, adhan.toEpochMilli(), adhan)
        assertEquals(Filter.ALL, dnd.current)
    }

    @Test fun geofenceEnterAndLeave() {
        val (c, dnd, _) = fixtures()
        c.onGeofence(on, GeofenceEvent.ENTER, now)
        assertEquals(Filter.PRIORITY, dnd.current)
        c.onGeofence(on, GeofenceEvent.LEAVE, now.plusSeconds(120))
        assertEquals(Filter.ALL, dnd.current)
    }

    @Test fun geofenceEnterIsIgnoredWhenSilenceIsOff() {
        val (c, dnd, _) = fixtures()
        c.onGeofence(on.copy(silenceEnabled = false), GeofenceEvent.ENTER, now)
        assertEquals(Filter.ALL, dnd.current)
    }

    @Test fun proximityBroadcastMapsToEnterAndLeave() {
        assertEquals(GeofenceEvent.ENTER, GeofenceMapping.event(Intent().putExtra(LocationManager.KEY_PROXIMITY_ENTERING, true)))
        assertEquals(GeofenceEvent.LEAVE, GeofenceMapping.event(Intent().putExtra(LocationManager.KEY_PROXIMITY_ENTERING, false)))
        assertNull(GeofenceMapping.event(Intent()))
    }

    @Test fun mosquesPersistWithNameAndHundredMetreRadius() {
        val (c, _, _) = fixtures()
        val m = c.addMosque("Istiqlal\tMosque", -6.17, 106.83)
        assertEquals("Istiqlal Mosque", m.name)
        assertEquals(100f, m.radiusMeters)
        assertEquals(listOf(m), SilenceStore(context).mosques.value)
        c.removeMosque(m.id)
        assertTrue(SilenceStore(context).mosques.value.isEmpty())
        assertFalse(c.mosques.value.contains(m))
    }
}
