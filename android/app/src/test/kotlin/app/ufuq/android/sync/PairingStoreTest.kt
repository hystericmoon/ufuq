package app.ufuq.android.sync

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.test.ext.junit.runners.AndroidJUnit4
import app.ufuq.core.sync.PairingException
import app.ufuq.core.sync.PairingPayload
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.runner.RunWith

/** Stands in for the Android Keystore, which Robolectric does not provide. XOR is enough to prove nothing is stored in clear. */
class FakeKeyWrapper(var available: Boolean = true) : KeyWrapper {
    override fun wrap(plain: ByteArray) = byteArrayOf(0x7f) + ByteArray(plain.size) { (plain[it].toInt() xor 0x5a).toByte() }
    override fun unwrap(wrapped: ByteArray): ByteArray? =
        if (!available || wrapped.isEmpty()) null else ByteArray(wrapped.size - 1) { (wrapped[it + 1].toInt() xor 0x5a).toByte() }
}

@RunWith(AndroidJUnit4::class)
class PairingStoreTest {
    private val json = """{"deviceId":"6f1d2c3a-0b4e-4f5a-9c7d-1a2b3c4d5e6f","host":"Mac-mini.local","key":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8","name":"Mac mini","port":49152,"v":1}"""

    private fun dataStore() = PreferenceDataStoreFactory.create { Files.createTempFile("ufuq-sync", ".preferences_pb").also { Files.delete(it) }.toFile() }

    @Test fun pairingParsedFromTheQrTextRoundTripsThroughTheStore() = runBlocking {
        val store = PairingStore(dataStore(), FakeKeyWrapper())
        assertNull(store.current())
        val payload = PairingPayload.parse(json)
        store.save(payload)
        val back = store.current()
        assertEquals(payload, back)
        assertEquals(32, back?.keyBytes?.size)
        assertEquals("Mac mini", back?.name)
    }

    @Test fun theKeyIsNeverStoredInClear() = runBlocking {
        val ds = dataStore()
        PairingStore(ds, FakeKeyWrapper()).save(PairingPayload.parse(json))
        val raw: Preferences = ds.data.first()
        val dump = raw.asMap().values.joinToString("|")
        assertFalse("AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8" in dump, dump)
        assertTrue("Mac-mini.local" in dump)
    }

    @Test fun forgetClearsEverything() = runBlocking {
        val ds = dataStore()
        val store = PairingStore(ds, FakeKeyWrapper())
        store.save(PairingPayload.parse(json))
        store.forget()
        assertNull(store.current())
        assertTrue(ds.data.first().asMap().isEmpty())
    }

    @Test fun anUnopenableKeyCountsAsUnpaired() = runBlocking {
        val wrapper = FakeKeyWrapper()
        val store = PairingStore(dataStore(), wrapper)
        store.save(PairingPayload.parse(json))
        wrapper.available = false // e.g. restored on a new phone without the Keystore key
        assertNull(store.current())
    }

    @Test fun nameIsOptional() = runBlocking {
        val store = PairingStore(dataStore(), FakeKeyWrapper())
        store.save(PairingPayload.parse(json.replace("\"name\":\"Mac mini\",", "")))
        assertNull(store.current()?.name)
    }

    @Test fun badCodesAreRejectedWithTheRightError() {
        assertEquals(PairingError.INVALID, (PairingOutcome.of("hello") as PairingOutcome.Failed).error)
        assertEquals(PairingError.UNSUPPORTED, (PairingOutcome.of(json.replace("\"v\":1", "\"v\":2")) as PairingOutcome.Failed).error)
        assertTrue(PairingOutcome.of("  $json\n") is PairingOutcome.Ok)
        assertFailsWith<PairingException> { PairingPayload.parse("{}") }
    }
}
