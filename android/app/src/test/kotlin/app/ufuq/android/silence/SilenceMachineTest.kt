package app.ufuq.android.silence

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SilenceMachineTest {
    private val min = 60_000L
    private val now = 1_000_000L

    @Test fun beginFromOpenPhoneSilencesAndSchedulesTheRestore() {
        val step = SilenceMachine.begin(SilenceState(), Filter.ALL, now, now + 15 * min)
        assertEquals(Filter.PRIORITY, step.setFilter)
        assertEquals(now + 15 * min, step.restoreAlarmAt)
        assertTrue(step.state.active)
        assertEquals(Filter.ALL, step.state.previousFilter)
    }

    @Test fun usersOwnDoNotDisturbIsLeftAloneAndNeverRestored() {
        val begin = SilenceMachine.begin(SilenceState(), Filter.ALARMS, now, now + 15 * min)
        assertNull(begin.setFilter)
        assertFalse(begin.state.active)
        val end = SilenceMachine.end(begin.state, Filter.ALARMS)
        assertNull(end.setFilter)
    }

    @Test fun endRestoresThePreviousFilter() {
        val s = SilenceMachine.begin(SilenceState(), Filter.ALL, now, now + 15 * min).state
        val end = SilenceMachine.end(s, Filter.PRIORITY)
        assertEquals(Filter.ALL, end.setFilter)
        assertTrue(end.cancelRestoreAlarm)
        assertFalse(end.state.active)
    }

    @Test fun endStandsDownWhenTheUserChangedTheFilterMeanwhile() {
        val s = SilenceMachine.begin(SilenceState(), Filter.ALL, now, now + 15 * min).state
        val end = SilenceMachine.end(s, Filter.NONE)
        assertNull(end.setFilter)
        assertFalse(end.state.active)
    }

    @Test fun beginningAgainExtendsAndNeverShortens() {
        val s = SilenceMachine.begin(SilenceState(), Filter.ALL, now, now + 15 * min).state
        val longer = SilenceMachine.begin(s, Filter.PRIORITY, now + min, now + 30 * min)
        assertEquals(now + 30 * min, longer.state.restoreAtMillis)
        assertNull(longer.setFilter)
        val shorter = SilenceMachine.begin(longer.state, Filter.PRIORITY, now + 2 * min, now + 5 * min)
        assertEquals(now + 30 * min, shorter.state.restoreAtMillis)
        assertEquals(Filter.ALL, shorter.state.previousFilter)
    }

    @Test fun anUntilInThePastDoesNothing() {
        val step = SilenceMachine.begin(SilenceState(), Filter.ALL, now, now - 1)
        assertNull(step.setFilter)
        assertFalse(step.state.active)
    }

    @Test fun recoverRestoresAfterTheEndTimeEvenAfterABoot() {
        val s = SilenceMachine.begin(SilenceState(), Filter.ALL, now, now + 15 * min).state
        val step = SilenceMachine.recover(s, Filter.PRIORITY, now + 16 * min)
        assertEquals(Filter.ALL, step.setFilter)
        assertFalse(step.state.active)
    }

    @Test fun recoverRearmsTheAlarmBeforeTheEndTime() {
        val s = SilenceMachine.begin(SilenceState(), Filter.ALL, now, now + 15 * min).state
        val step = SilenceMachine.recover(s, Filter.PRIORITY, now + 5 * min)
        assertNull(step.setFilter)
        assertEquals(now + 15 * min, step.restoreAlarmAt)
        assertTrue(step.state.active)
    }

    @Test fun recoverWhenInactiveDoesNothing() {
        val step = SilenceMachine.recover(SilenceState(), Filter.ALL, now)
        assertNull(step.setFilter)
        assertNull(step.restoreAlarmAt)
    }

    @Test fun geofenceEnterSilencesForTheSettingAndLeaveRestores() {
        val enter = SilenceMachine.geofence(SilenceState(), GeofenceEvent.ENTER, Filter.ALL, now, 20)
        assertEquals(Filter.PRIORITY, enter.setFilter)
        assertEquals(now + 20 * min, enter.restoreAlarmAt)
        val leave = SilenceMachine.geofence(enter.state, GeofenceEvent.LEAVE, Filter.PRIORITY, now + 3 * min, 20)
        assertEquals(Filter.ALL, leave.setFilter)
        assertFalse(leave.state.active)
    }

    @Test fun leaveWithoutEnterIsANoOp() {
        val leave = SilenceMachine.geofence(SilenceState(), GeofenceEvent.LEAVE, Filter.ALL, now, 20)
        assertNull(leave.setFilter)
    }

    @Test fun alarmChoiceIsExactOnlyWhenAllowed() {
        assertEquals(AlarmChoice.Exact, AlarmChoice.of(true))
        assertEquals(AlarmChoice.Window(AlarmChoice.WINDOW_MILLIS), AlarmChoice.of(false))
    }
}
