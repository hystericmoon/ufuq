package app.ufuq.android.sync

import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Wraps the pairing key before it is stored. The real one keeps an AES key inside the Android
 * Keystore (the app never sees that key's bytes); tests use a fake because Robolectric has no
 * AndroidKeyStore.
 */
interface KeyWrapper {
    fun wrap(plain: ByteArray): ByteArray

    /** Null when the box cannot be opened (for example the Keystore key is gone after a restore). */
    fun unwrap(wrapped: ByteArray): ByteArray?
}

/** AES-256-GCM with a non-exportable Keystore key. Layout: `iv (12) || ciphertext || tag`. */
class KeystoreKeyWrapper(private val alias: String = "ufuq_sync_wrap") : KeyWrapper {
    override fun wrap(plain: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORM).apply { init(Cipher.ENCRYPT_MODE, key()) }
        return cipher.iv + cipher.doFinal(plain)
    }

    override fun unwrap(wrapped: ByteArray): ByteArray? {
        if (wrapped.size <= IV_BYTES) return null
        return try {
            val cipher = Cipher.getInstance(TRANSFORM).apply {
                init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, wrapped, 0, IV_BYTES))
            }
            cipher.doFinal(wrapped, IV_BYTES, wrapped.size - IV_BYTES)
        } catch (e: Exception) {
            null
        }
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance(PROVIDER).apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(android.security.keystore.KeyProperties.KEY_ALGORITHM_AES, PROVIDER)
        generator.init(
            android.security.keystore.KeyGenParameterSpec.Builder(
                alias,
                android.security.keystore.KeyProperties.PURPOSE_ENCRYPT or android.security.keystore.KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(android.security.keystore.KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val PROVIDER = "AndroidKeyStore"
        const val TRANSFORM = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
    }
}
