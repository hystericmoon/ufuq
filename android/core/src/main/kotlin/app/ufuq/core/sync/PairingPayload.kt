package app.ufuq.core.sync

import java.util.Base64
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException

class PairingException(message: String) : Exception(message)

/** The JSON in the Mac's pairing QR code. */
@Serializable
data class PairingPayload(
    val v: Int,
    /** A hint only; prefer the address Bonjour/NSD resolves. */
    val host: String,
    val port: Int,
    val deviceId: String,
    /** 32 random bytes, base64url without padding. */
    val key: String,
    val name: String? = null,
) {
    val keyBytes: ByteArray get() = Base64.getUrlDecoder().decode(key)

    companion object {
        /** Parses and validates a scanned QR string. */
        fun parse(text: String): PairingPayload {
            val payload = try {
                SyncJson.decodeFromString(serializer(), text.trim())
            } catch (e: SerializationException) {
                throw PairingException("Not a Ufuq pairing code")
            } catch (e: IllegalArgumentException) {
                throw PairingException("Not a Ufuq pairing code")
            }
            if (payload.v != SyncProtocol.VERSION) throw PairingException("Unsupported pairing version ${payload.v}")
            val key = try {
                Base64.getUrlDecoder().decode(payload.key)
            } catch (e: IllegalArgumentException) {
                throw PairingException("Invalid key")
            }
            if (key.size != SyncProtocol.KEY_LENGTH) throw PairingException("Invalid key")
            if (payload.port !in 1..65535) throw PairingException("Invalid port")
            if (payload.deviceId.isEmpty()) throw PairingException("Not a Ufuq pairing code")
            return payload
        }
    }
}
