package app.ufuq.android.sync

import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.NotFoundException
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer

/** Reads a QR code from an 8-bit luminance image. ZXing core only; no ML Kit or Play services. */
object QrDecoder {
    /** [luma] is [width] x [height] bytes, row by row with no padding. Returns the text, or null when there is no QR. */
    fun decode(luma: ByteArray, width: Int, height: Int): String? {
        val reader = MultiFormatReader().apply {
            setHints(mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE), DecodeHintType.TRY_HARDER to true))
        }
        return try {
            reader.decodeWithState(BinaryBitmap(HybridBinarizer(PlanarYUVLuminanceSource(luma, width, height, 0, 0, width, height, false)))).text
        } catch (e: NotFoundException) {
            null
        } catch (e: com.google.zxing.ReaderException) {
            null
        } finally {
            reader.reset()
        }
    }

    /** Copies a plane that may have row padding into a tight array. */
    fun tight(plane: ByteArray, width: Int, height: Int, rowStride: Int): ByteArray {
        if (rowStride == width) return plane.copyOf(width * height)
        val out = ByteArray(width * height)
        for (row in 0 until height) System.arraycopy(plane, row * rowStride, out, row * width, width)
        return out
    }
}

/** CameraX analyzer: decodes the Y plane of each frame and reports the first QR text. */
class QrAnalyzer(private val onText: (String) -> Unit) : ImageAnalysis.Analyzer {
    override fun analyze(image: ImageProxy) {
        try {
            val plane = image.planes[0]
            val buffer = plane.buffer.apply { rewind() }
            val bytes = ByteArray(buffer.remaining()).also(buffer::get)
            val luma = QrDecoder.tight(bytes, image.width, image.height, plane.rowStride)
            QrDecoder.decode(luma, image.width, image.height)?.let(onText)
        } finally {
            image.close()
        }
    }
}
