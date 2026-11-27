package app.ufuq.desktop.update

import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertRangeInfoEquals
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.v2.runDesktopComposeUiTest
import app.ufuq.core.update.AvailableUpdate
import app.ufuq.core.update.ReleaseAsset
import java.io.File
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.Signature
import java.util.Base64
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private class TestKey {
    val pair = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()

    /** Raw 32 bytes are the tail of the X.509 encoding. */
    val rawBase64: String = Base64.getEncoder().encodeToString(pair.public.encoded.takeLast(32).toByteArray())

    fun sign(bytes: ByteArray): String {
        val s = Signature.getInstance("Ed25519")
        s.initSign(pair.private)
        s.update(bytes)
        return Base64.getEncoder().encodeToString(s.sign())
    }
}

private fun sha(b: ByteArray) = MessageDigest.getInstance("SHA-256").digest(b).joinToString("") { "%02x".format(it) }

class SignatureVerifierTest {
    private val dir = kotlin.io.path.createTempDirectory("ufuq-sig").toFile()
    private fun file(bytes: ByteArray) = File(dir, "f.msi").also { it.writeBytes(bytes) }

    @Test fun validTamperedAndWrongKey() {
        val k = TestKey()
        val data = ByteArray(300_000) { (it % 251).toByte() }
        val sig = k.sign(data)
        val pub = assertNotNull(SignatureVerifier.publicKeyFromRaw(k.rawBase64))
        assertTrue(SignatureVerifier.verifyFile(file(data), sig, pub))
        assertTrue(SignatureVerifier.verifyFile(file(data), "$sig\n", pub))

        val tampered = data.clone().also { it[12345] = (it[12345] + 1).toByte() }
        assertFalse(SignatureVerifier.verifyFile(file(tampered), sig, pub))

        val other = assertNotNull(SignatureVerifier.publicKeyFromRaw(TestKey().rawBase64))
        assertFalse(SignatureVerifier.verifyFile(file(data), sig, other))

        assertFalse(SignatureVerifier.verifyFile(file(data), "not base64 !!", pub))
        assertFalse(SignatureVerifier.verifyFile(file(data), Base64.getEncoder().encodeToString(ByteArray(10)), pub))
        dir.deleteRecursively()
    }

    @Test fun badKeysAreRejected() {
        assertNull(SignatureVerifier.publicKeyFromRaw(""))
        assertNull(SignatureVerifier.publicKeyFromRaw("AAAA"))
        assertNull(SignatureVerifier.publicKeyFromRaw("%%%"))
    }
}

private class FakeHttp(val files: Map<String, ByteArray>, val json: String = "{}") : UpdateHttp {
    var downloads = 0
    override fun getString(url: String) = json
    override fun download(url: String, dest: File, onProgress: (Long, Long) -> Unit) {
        downloads++
        val b = files[url] ?: error("404")
        dest.writeBytes(b)
        onProgress(b.size.toLong(), b.size.toLong())
    }
}

class UpdateManagerTest {
    private val tmp = kotlin.io.path.createTempDirectory("ufuq-upd").toFile()
    private val key = TestKey()
    private val msiBytes = ByteArray(5000) { it.toByte() }

    private fun releaseJson(version: String, digest: String? = sha(msiBytes)) = """
        [{"tag_name":"v$version","body":"n","draft":false,"prerelease":false,"assets":[
        {"name":"Ufuq-$version.msi","browser_download_url":"https://x/m","size":5000,"digest":${digest?.let { "\"sha256:$it\"" } ?: "null"}},
        {"name":"Ufuq-$version.msi.sig","browser_download_url":"https://x/s","size":88}]}]"""

    private fun manager(http: UpdateHttp, publicKey: String = key.rawBase64, launched: MutableList<File> = mutableListOf(), exited: MutableList<Boolean> = mutableListOf(), launchOk: Boolean = true) =
        UpdateManager("0.1.0", publicKey, http, tmp, { launched += it; launchOk }, { exited += true })

    @Test fun disabledWithoutKeyNeverTouchesNetwork() {
        val http = FakeHttp(emptyMap(), releaseJson("0.2.0"))
        val m = manager(http, publicKey = "")
        assertFalse(m.enabled)
        assertEquals(UpdateState.Disabled, m.state.value)
        m.check(true)
        m.download()
        m.install()
        assertEquals(UpdateState.Disabled, m.state.value)
        assertEquals(0, http.downloads)
        assertEquals("Updates are off in development builds", updateStatusText(UpdateState.Disabled, "0.1.0"))
        assertFalse(manager(http, publicKey = "garbage").enabled)
    }

    @Test fun happyPathVerifiesThenInstalls() {
        val http = FakeHttp(mapOf("https://x/m" to msiBytes, "https://x/s" to key.sign(msiBytes).toByteArray()), releaseJson("0.2.0"))
        val launched = mutableListOf<File>()
        val exited = mutableListOf<Boolean>()
        val m = manager(http, launched = launched, exited = exited)
        m.check(true)
        assertIs<UpdateState.Available>(m.state.value)
        m.download()
        val ready = assertIs<UpdateState.Ready>(m.state.value)
        assertEquals("Ufuq-0.2.0.msi", ready.file.name)
        assertEquals(File(tmp, "Ufuq"), ready.file.parentFile)
        assertTrue(launched.isEmpty())
        m.install()
        assertEquals(listOf(ready.file), launched)
        assertEquals(listOf(true), exited)
    }

    @Test fun upToDate() {
        val m = manager(FakeHttp(emptyMap(), releaseJson("0.1.0")))
        m.check(true)
        assertIs<UpdateState.UpToDate>(m.state.value)
    }

    @Test fun tamperedDownloadIsDiscardedAndNeverRun() {
        val tampered = msiBytes.clone().also { it[7] = 99 }
        // GitHub digest absent so that the signature check is what catches it.
        val http = FakeHttp(mapOf("https://x/m" to tampered, "https://x/s" to key.sign(msiBytes).toByteArray()), releaseJson("0.2.0", digest = null))
        val launched = mutableListOf<File>()
        val m = manager(http, launched = launched)
        m.check(true)
        m.download()
        val failed = assertIs<UpdateState.Failed>(m.state.value)
        assertTrue(failed.message.contains("not signed"))
        assertFalse(File(tmp, "Ufuq/Ufuq-0.2.0.msi").exists())
        m.install()
        assertTrue(launched.isEmpty())
    }

    @Test fun checksumMismatchIsDiscarded() {
        val http = FakeHttp(mapOf("https://x/m" to msiBytes, "https://x/s" to key.sign(msiBytes).toByteArray()), releaseJson("0.2.0", digest = "0".repeat(64)))
        val m = manager(http)
        m.check(true)
        m.download()
        assertTrue(assertIs<UpdateState.Failed>(m.state.value).message.contains("checksum"))
    }

    @Test fun signatureFromAnotherKeyIsRejected() {
        val http = FakeHttp(mapOf("https://x/m" to msiBytes, "https://x/s" to TestKey().sign(msiBytes).toByteArray()), releaseJson("0.2.0"))
        val m = manager(http)
        m.check(true)
        m.download()
        assertIs<UpdateState.Failed>(m.state.value)
    }

    @Test fun fileSwappedAfterVerificationIsCaughtAtInstall() {
        val http = FakeHttp(mapOf("https://x/m" to msiBytes, "https://x/s" to key.sign(msiBytes).toByteArray()), releaseJson("0.2.0"))
        val launched = mutableListOf<File>()
        val m = manager(http, launched = launched)
        m.check(true)
        m.download()
        val ready = assertIs<UpdateState.Ready>(m.state.value)
        ready.file.writeBytes(ByteArray(5000) { 1 })
        m.install()
        assertIs<UpdateState.Failed>(m.state.value)
        assertTrue(launched.isEmpty())
    }

    @Test fun networkErrorsBecomeFailed() {
        val m = manager(object : UpdateHttp {
            override fun getString(url: String): String = error("offline")
            override fun download(url: String, dest: File, onProgress: (Long, Long) -> Unit) = error("offline")
        })
        m.check(false)
        assertIs<UpdateState.Failed>(m.state.value)
    }

    @Test fun autoCheckSchedule() {
        val day = 24L * 3600 * 1000
        assertTrue(autoCheckDue(true, true, 0, 1000))
        assertFalse(autoCheckDue(true, true, 1000, 1000 + day - 1))
        assertTrue(autoCheckDue(true, true, 1000, 1000 + day))
        assertFalse(autoCheckDue(false, true, 0, day))
        assertFalse(autoCheckDue(true, false, 0, day))
    }
}

@OptIn(ExperimentalTestApi::class)
class UpdateScreenTest {
    private val update = AvailableUpdate("0.2.0", "Faster", ReleaseAsset("Ufuq-0.2.0.msi", "https://x/m", 100, null), ReleaseAsset("Ufuq-0.2.0.msi.sig", "https://x/s", 88, null))

    @Test fun availableOffersDownloadAndAnnounces() {
        var downloaded = 0
        runDesktopComposeUiTest(460, 380) {
            setContent { UpdateScreen(UpdateState.Available(update), "0.1.0", {}, { downloaded++ }, {}, {}) }
            onNodeWithText("Ufuq 0.2.0 is available. You have 0.1.0.").assertExists()
            onNodeWithText("Faster").assertExists()
            onNodeWithText("Download and verify").assertIsEnabled().performClick()
        }
        assertEquals(1, downloaded)
    }

    @Test fun downloadingExposesProgressRange() {
        runDesktopComposeUiTest(460, 380) {
            setContent { UpdateScreen(UpdateState.Downloading(update, 50, 100), "0.1.0", {}, {}, {}, {}) }
            onNodeWithContentDescription("Download progress").assertRangeInfoEquals(ProgressBarRangeInfo(0.5f, 0f..1f))
            onNodeWithText("Downloading Ufuq 0.2.0, 50 percent").assertExists()
            onNodeWithText("Close").assertDoesNotExist()
        }
    }

    @Test fun readyShowsRestartButton() {
        var restarted = 0
        runDesktopComposeUiTest(460, 380) {
            setContent { UpdateScreen(UpdateState.Ready(update, File("x.msi")), "0.1.0", {}, {}, { restarted++ }, {}) }
            onNodeWithText("Restart to update").performClick()
            onNodeWithText("Later").assertExists()
        }
        assertEquals(1, restarted)
    }

    @Test fun disabledShowsDevelopmentMessage() {
        runDesktopComposeUiTest(460, 380) {
            setContent { UpdateScreen(UpdateState.Disabled, "0.1.0", {}, {}, {}, {}) }
            onNodeWithText("Updates are off in development builds").assertExists()
            onNodeWithText("Download and verify").assertDoesNotExist()
        }
    }

    @Test fun failedOffersRetry() {
        runDesktopComposeUiTest(460, 380) {
            setContent { UpdateScreen(UpdateState.Failed("Could not check for updates: offline"), "0.1.0", {}, {}, {}, {}) }
            onNodeWithText("Try again").assertExists()
        }
    }
}
