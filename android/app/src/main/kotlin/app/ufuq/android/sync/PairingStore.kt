package app.ufuq.android.sync

import android.content.Context
import android.util.Base64
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import app.ufuq.core.sync.PairingPayload
import app.ufuq.core.sync.SyncProtocol
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.syncStore: DataStore<Preferences> by preferencesDataStore(name = "ufuq_sync")

/** Where the pairing lives. The sync loop only needs to watch it. */
interface PairingSource {
    /** The paired Mac, or null when unpaired (or the stored key can no longer be opened). */
    val pairing: Flow<PairingPayload?>
}

/**
 * The paired Mac in a DataStore. The key is stored only as ciphertext from [KeyWrapper]; host,
 * port, device id and name are not secret. "Forget Mac" removes everything.
 */
class PairingStore(
    private val store: DataStore<Preferences>,
    private val wrapper: KeyWrapper,
) : PairingSource {
    constructor(context: Context) : this(context.applicationContext.syncStore, KeystoreKeyWrapper())

    override val pairing: Flow<PairingPayload?> = store.data.map(::read)

    suspend fun current(): PairingPayload? = pairing.first()

    suspend fun save(payload: PairingPayload) {
        val wrapped = wrapper.wrap(payload.keyBytes)
        store.edit { p ->
            p[DEVICE_ID] = payload.deviceId
            p[HOST] = payload.host
            p[PORT] = payload.port
            p[WRAPPED_KEY] = Base64.encodeToString(wrapped, Base64.NO_WRAP)
            val name = payload.name
            if (name != null) p[NAME] = name else p.remove(NAME)
        }
    }

    suspend fun forget() {
        store.edit { it.clear() }
    }

    private fun read(p: Preferences): PairingPayload? {
        val deviceId = p[DEVICE_ID] ?: return null
        val host = p[HOST] ?: return null
        val port = p[PORT] ?: return null
        val wrapped = p[WRAPPED_KEY]?.let { runCatching { Base64.decode(it, Base64.NO_WRAP) }.getOrNull() } ?: return null
        val key = wrapper.unwrap(wrapped)?.takeIf { it.size == SyncProtocol.KEY_LENGTH } ?: return null
        return PairingPayload(
            v = SyncProtocol.VERSION,
            host = host,
            port = port,
            deviceId = deviceId,
            key = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(key),
            name = p[NAME],
        )
    }

    private companion object {
        val DEVICE_ID = stringPreferencesKey("device_id")
        val HOST = stringPreferencesKey("host")
        val PORT = intPreferencesKey("port")
        val NAME = stringPreferencesKey("name")
        val WRAPPED_KEY = stringPreferencesKey("wrapped_key")
    }
}
