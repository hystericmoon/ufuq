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

    /** The QR text the Mac shows: [LINK_PREFIX] + base64url of the JSON. */
    fun toLink(): String =
        LINK_PREFIX + Base64.getUrlEncoder().withoutPadding().encodeToString(SyncJson.encodeToString(serializer(), this).toByteArray(Charsets.UTF_8))

    companion object {
        /** A phone camera opens Ufuq with this link; the app still asks before pairing. */
        const val LINK_PREFIX = "ufuq://pair#"

        /** Parses and validates a scanned or pasted code: the link, or the bare JSON (older Macs). */
        fun parse(text: String): PairingPayload {
            val trimmed = text.trim()
            val json = if (trimmed.startsWith(LINK_PREFIX)) {
                try {
                    String(Base64.getUrlDecoder().decode(trimmed.removePrefix(LINK_PREFIX)), Charsets.UTF_8)
                } catch (e: IllegalArgumentException) {
                    throw PairingException("Not a Ufuq pairing code")
                }
            } else {
                trimmed
            }
            val payload = try {
                SyncJson.decodeFromString(serializer(), json)
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
