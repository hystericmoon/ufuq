package app.ufuq.desktop.update

import java.io.File
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.PublicKey
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

/** Ed25519 and SHA-256 checks on a downloaded installer. Pure java.security, no platform calls. */
object SignatureVerifier {
    // ASN.1 SubjectPublicKeyInfo header for an Ed25519 key; the 32 raw key bytes follow.
    private val SPKI_PREFIX = byteArrayOf(0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00)

    /** Null when [base64Raw] is not a base64 raw 32-byte Ed25519 key. */
    fun publicKeyFromRaw(base64Raw: String): PublicKey? = try {
        val raw = Base64.getDecoder().decode(base64Raw.trim())
        if (raw.size != 32) null
        else KeyFactory.getInstance("Ed25519").generatePublic(X509EncodedKeySpec(SPKI_PREFIX + raw))
    } catch (_: Exception) {
        null
    }

    /** True only when [signatureText] (base64 of the raw 64-byte signature) is valid for the bytes of [file]. */
    fun verifyFile(file: File, signatureText: String, key: PublicKey): Boolean = try {
        val sig = Base64.getMimeDecoder().decode(signatureText.trim())
        if (sig.size != 64) false
        else {
            val v = Signature.getInstance("Ed25519")
            v.initVerify(key)
            file.inputStream().use { input ->
                val buf = ByteArray(64 * 1024)
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    v.update(buf, 0, n)
                }
            }
            v.verify(sig)
        }
    } catch (_: Exception) {
        false
    }

    fun sha256Hex(file: File): String {
        val md = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buf = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                md.update(buf, 0, n)
            }
        }
        return md.digest().joinToString("") { "%02x".format(it) }
    }
}
