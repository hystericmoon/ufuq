package app.ufuq.core.sync

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class AesGcmSealerTest {
    private val vector = Json.parseToJsonElement(SyncFixtures.text("seal_vector.json")).jsonObject
    private fun field(name: String) = vector.getValue(name).jsonPrimitive.content

    @Test fun matchesSharedKnownAnswerVector() {
        assertEquals("ufuq-sync-v1", field("aad"))
        val nonce = unhex(field("nonceHex"))
        val sealer = AesGcmSealer(unhex(field("keyHex"))) { nonce }
        val sealed = sealer.seal(field("plaintextUtf8").toByteArray())
        assertEquals(field("sealedHex"), hex(sealed))
        assertEquals(field("plaintextUtf8"), sealer.open(unhex(field("sealedHex"))).toString(Charsets.UTF_8))
    }

    @Test fun roundTripWithRandomNonces() {
        val sealer = AesGcmSealer(SyncFixtures.KEY)
        val a = sealer.seal("hello".toByteArray())
        val b = sealer.seal("hello".toByteArray())
        assertEquals(12 + 5 + 16, a.size)
        assert(!a.contentEquals(b)) { "nonce must differ" }
        assertContentEquals("hello".toByteArray(), sealer.open(a))
        assertContentEquals(ByteArray(0), sealer.open(sealer.seal(ByteArray(0))))
    }

    @Test fun rejectsTamperWrongKeyAndShortBoxes() {
        val sealer = AesGcmSealer(SyncFixtures.KEY)
        val sealed = sealer.seal("secret".toByteArray())
        val tampered = sealed.copyOf().also { it[it.size - 1] = (it.last().toInt() xor 1).toByte() }
        assertFailsWith<SealException> { sealer.open(tampered) }
        assertFailsWith<SealException> { AesGcmSealer(ByteArray(32) { 9 }).open(sealed) }
        assertFailsWith<SealException> { sealer.open(ByteArray(10)) }
    }

    @Test fun rejectsBadKeyLength() {
        assertFailsWith<IllegalArgumentException> { AesGcmSealer(ByteArray(16)) }
    }
}
