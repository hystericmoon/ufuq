package app.ufuq.core.sync

import java.util.Base64
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class PairingPayloadTest {
    @Test fun parsesGoldenPairing() {
        val p = PairingPayload.parse(SyncFixtures.text("pairing.json"))
        assertEquals(1, p.v)
        assertEquals("Mac-mini.local", p.host)
        assertEquals(49152, p.port)
        assertEquals("6f1d2c3a-0b4e-4f5a-9c7d-1a2b3c4d5e6f", p.deviceId)
        assertEquals("Mac mini", p.name)
        assertContentEquals(SyncFixtures.KEY, p.keyBytes)
    }

    private fun json(v: Int = 1, port: Int = 1000, key: String = Base64.getUrlEncoder().withoutPadding().encodeToString(SyncFixtures.KEY), device: String = "d") =
        """{"v":$v,"host":"h","port":$port,"deviceId":"$device","key":"$key"}"""

    @Test fun acceptsMissingName() {
        assertEquals(null, PairingPayload.parse(json()).name)
    }

    @Test fun rejectsBadInput() {
        assertFailsWith<PairingException> { PairingPayload.parse("not json") }
        assertFailsWith<PairingException> { PairingPayload.parse("""{"v":1}""") }
        assertFailsWith<PairingException> { PairingPayload.parse(json(v = 2)) }
        assertFailsWith<PairingException> { PairingPayload.parse(json(key = "AAAA")) }
        assertFailsWith<PairingException> { PairingPayload.parse(json(key = "***")) }
        assertFailsWith<PairingException> { PairingPayload.parse(json(port = 0)) }
        assertFailsWith<PairingException> { PairingPayload.parse(json(port = 70000)) }
        assertFailsWith<PairingException> { PairingPayload.parse(json(device = "")) }
    }
}
