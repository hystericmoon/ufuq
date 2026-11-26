package app.ufuq.core.sync

import java.security.GeneralSecurityException
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class SealException(message: String, cause: Throwable? = null) : Exception(message, cause)

/** Seals and opens sync payloads. Layout: `nonce (12) || ciphertext || tag (16)`, AAD `ufuq-sync-v1`. */
interface SyncSealer {
    fun seal(plaintext: ByteArray): ByteArray

    /** @throws SealException when the box is malformed or the key or AAD do not match. */
    fun open(sealed: ByteArray): ByteArray
}

/** AES-256-GCM through `javax.crypto`; the Mac side is CryptoKit `AES.GCM`. */
class AesGcmSealer(
    key: ByteArray,
    private val nonceSource: () -> ByteArray = ::randomNonce,
) : SyncSealer {
    private val keySpec: SecretKeySpec

    init {
        require(key.size == SyncProtocol.KEY_LENGTH) { "key must be 32 bytes" }
        keySpec = SecretKeySpec(key, "AES")
    }

    override fun seal(plaintext: ByteArray): ByteArray {
        val nonce = nonceSource()
        require(nonce.size == SyncProtocol.NONCE_LENGTH) { "nonce must be 12 bytes" }
        val cipher = cipher(Cipher.ENCRYPT_MODE, nonce)
        return nonce + cipher.doFinal(plaintext)
    }

    override fun open(sealed: ByteArray): ByteArray {
        if (sealed.size < SyncProtocol.NONCE_LENGTH + SyncProtocol.TAG_LENGTH) throw SealException("Sealed box too short")
        val nonce = sealed.copyOfRange(0, SyncProtocol.NONCE_LENGTH)
        return try {
            cipher(Cipher.DECRYPT_MODE, nonce).doFinal(sealed, SyncProtocol.NONCE_LENGTH, sealed.size - SyncProtocol.NONCE_LENGTH)
        } catch (e: GeneralSecurityException) {
            throw SealException("Could not open sealed box", e)
        }
    }

    private fun cipher(mode: Int, nonce: ByteArray): Cipher =
        Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(mode, keySpec, GCMParameterSpec(SyncProtocol.TAG_LENGTH * 8, nonce))
            updateAAD(SyncProtocol.AAD.toByteArray(Charsets.UTF_8))
        }

    companion object {
        private val random = SecureRandom()

        fun randomNonce(): ByteArray = ByteArray(SyncProtocol.NONCE_LENGTH).also(random::nextBytes)
    }
}
