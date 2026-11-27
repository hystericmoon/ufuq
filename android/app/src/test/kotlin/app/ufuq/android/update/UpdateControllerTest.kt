package app.ufuq.android.update

import app.ufuq.core.update.AvailableDownload
import app.ufuq.core.update.ReleaseAsset
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Test
import java.io.File
import java.io.IOException
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class UpdateControllerTest {
    private val update = AvailableDownload("0.2.0", "Fixes", ReleaseAsset("ufuq-0.2.0.apk", "https://github.com/x/ufuq-0.2.0.apk", 10, null))

    private class FakeSource(var found: AvailableDownload? = null, var fail: Boolean = false) : UpdateSource {
        override var enabled = true
        override var autoCheck = true
        override var betaChannel = false
        override var lastCheckMillis = 0L
        var checks = 0
        var downloadFails = false
        var gate: CompletableDeferred<Unit>? = null
        override suspend fun check(nowMillis: Long): AvailableDownload? {
            checks++
            if (fail) throw IOException("offline")
            lastCheckMillis = nowMillis
            return found
        }
        override suspend fun download(update: AvailableDownload, onProgress: (Float) -> Unit): File {
            onProgress(0.5f)
            gate?.await()
            if (downloadFails) throw IOException("digest")
            return File("ufuq-${update.version}.apk")
        }
    }

    private fun TestScope.controller(source: UpdateSource, now: Long = DAY * 3) = UpdateController(source, this, clock = { now })

    @Test fun autoCheckPromptsOnlyWhenNewerAndOncePerDay() = runTest {
        val source = FakeSource(found = update)
        val c = controller(source)
        c.autoCheck(); advanceUntilIdle()
        assertTrue(c.state.value.prompt)
        assertIs<UpdateStatus.Available>(c.state.value.status)
        assertEquals(DAY * 3, c.state.value.lastCheckMillis)
        c.dismissPrompt()
        c.autoCheck(); advanceUntilIdle()
        assertEquals(1, source.checks) // not due again for 20 h
        assertFalse(c.state.value.prompt)
    }

    @Test fun autoCheckIsSilentWhenOffOrOfflineOrUpToDate() = runTest {
        val off = FakeSource(found = update).apply { autoCheck = false }
        controller(off).apply { autoCheck(); advanceUntilIdle() }
        assertEquals(0, off.checks)

        val offline = FakeSource(fail = true)
        val c = controller(offline)
        c.autoCheck(); advanceUntilIdle()
        assertEquals(UpdateStatus.Idle, c.state.value.status)
        assertFalse(c.state.value.prompt)

        val dev = FakeSource(found = update).apply { enabled = false }
        controller(dev).apply { autoCheck(); checkNow(); advanceUntilIdle() }
        assertEquals(0, dev.checks)
    }

    @Test fun manualCheckReportsEachOutcome() = runTest {
        val source = FakeSource()
        val c = controller(source)
        c.checkNow(); advanceUntilIdle()
        assertEquals(UpdateStatus.UpToDate, c.state.value.status)
        source.fail = true
        c.checkNow(); advanceUntilIdle()
        assertEquals(UpdateStatus.Failed(null), c.state.value.status)
        source.fail = false; source.found = update
        c.checkNow(); advanceUntilIdle()
        assertEquals(UpdateStatus.Available(update), c.state.value.status)
        assertFalse(c.state.value.prompt) // a manual check shows on the screen, not as a dialog
    }

    @Test fun downloadProgressThenReadyOrRetry() = runTest {
        val source = FakeSource(found = update).apply { gate = CompletableDeferred() }
        val c = controller(source)
        c.checkNow(); advanceUntilIdle()
        c.download(); advanceUntilIdle()
        assertEquals(UpdateStatus.Downloading(update, 0.5f), c.state.value.status)
        assertNull(c.readyApk())
        source.gate!!.complete(Unit); advanceUntilIdle()
        assertEquals("ufuq-0.2.0.apk", c.readyApk()?.name)

        val bad = FakeSource(found = update).apply { downloadFails = true }
        val c2 = controller(bad)
        c2.checkNow(); advanceUntilIdle()
        c2.download(); advanceUntilIdle()
        assertEquals(UpdateStatus.Failed(update), c2.state.value.status)
        bad.downloadFails = false
        c2.download(); advanceUntilIdle() // retry keeps the found update
        assertIs<UpdateStatus.Ready>(c2.state.value.status)
    }

    @Test fun betaSwitchChecksAgain() = runTest {
        val source = FakeSource(found = update)
        val c = controller(source)
        c.setBetaChannel(true); advanceUntilIdle()
        assertTrue(source.betaChannel)
        assertEquals(1, source.checks)
        c.setAutoCheck(false)
        assertFalse(source.autoCheck)
        assertFalse(c.state.value.autoCheck)
    }

    @Test fun digestAndAssetName() {
        val bytes = java.security.MessageDigest.getInstance("SHA-256").digest("apk".toByteArray())
        val hex = bytes.joinToString("") { "%02x".format(it) }
        assertTrue(UpdateRepository.digestMatches(null, bytes))
        assertTrue(UpdateRepository.digestMatches(hex.uppercase(), bytes))
        assertFalse(UpdateRepository.digestMatches("0".repeat(64), bytes))
        assertEquals("ufuq-1.2.3.apk", UpdateRepository.apkName("1.2.3"))
    }

    private companion object { const val DAY = 24L * 60 * 60 * 1000 }
}
