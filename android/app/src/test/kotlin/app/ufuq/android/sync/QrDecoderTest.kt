package app.ufuq.android.sync

import app.ufuq.core.sync.PairingPayload
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class QrDecoderTest {
    private val json = """{"deviceId":"6f1d2c3a-0b4e-4f5a-9c7d-1a2b3c4d5e6f","host":"Mac-mini.local","key":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8","name":"Mac mini","port":49152,"v":1}"""

    private fun luma(text: String, size: Int): ByteArray {
        val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size, // Level M, like the Mac's CoreImage generator.
        mapOf(EncodeHintType.MARGIN to 4, EncodeHintType.ERROR_CORRECTION to com.google.zxing.qrcode.decoder.ErrorCorrectionLevel.M))
        return ByteArray(size * size) { if (matrix.get(it % size, it / size)) 0 else 0xFF.toByte() }
    }

    @Test fun decodesThePairingQrAndItParses() {
        val text = QrDecoder.decode(luma(json, 400), 400, 400)
        assertEquals(json, text)
        assertEquals("Mac mini", PairingPayload.parse(text!!).name)
    }

    @Test fun rowPaddingFromTheCameraIsRemoved() {
        val tight = luma(json, 400)
        val padded = ByteArray(448 * 400)
        for (row in 0 until 400) System.arraycopy(tight, row * 400, padded, row * 448, 400)
        assertEquals(json, QrDecoder.decode(QrDecoder.tight(padded, 400, 400, 448), 400, 400))
    }

    @Test fun noQrMeansNull() {
        assertNull(QrDecoder.decode(ByteArray(200 * 200) { 0x80.toByte() }, 200, 200))
    }
}
