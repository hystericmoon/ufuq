package app.ufuq.android.sync

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import app.ufuq.core.sync.PairingPayload
import app.ufuq.core.sync.SyncProtocol
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull

/** Finds where the paired Mac is now. Never throws: on any trouble the QR's host and port are the answer. */
fun interface MacLocator {
    suspend fun locate(pairing: PairingPayload): PairingPayload
}

/** Service name the Mac advertises: `ufuq-<deviceId>` (lower-case UUID). */
fun serviceNameFor(deviceId: String) = "ufuq-${deviceId.lowercase()}"

/** True for the Mac's own service name; NSD may append " (2)" when names collide. */
fun matchesService(serviceName: String, deviceId: String): Boolean {
    val wanted = serviceNameFor(deviceId)
    val name = serviceName.lowercase()
    return name == wanted || name.startsWith("$wanted (")
}

/** Browses `_ufuq._tcp` with NSD and resolves the paired Mac; falls back to the QR host and port. */
class NsdMacLocator(context: Context, private val timeoutMillis: Long = 4_000) : MacLocator {
    private val app = context.applicationContext

    override suspend fun locate(pairing: PairingPayload): PairingPayload =
        runCatching { withTimeoutOrNull(timeoutMillis) { browse(pairing) } }.getOrNull() ?: pairing

    @Suppress("DEPRECATION") // resolveService works on every API level; the replacement needs API 34.
    private suspend fun browse(pairing: PairingPayload): PairingPayload? {
        val nsd = app.getSystemService(Context.NSD_SERVICE) as? NsdManager ?: return null
        val lock = (app.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager)
            ?.createMulticastLock("ufuq-nsd")?.apply { setReferenceCounted(false); acquire() }
        var listener: NsdManager.DiscoveryListener? = null
        try {
            return suspendCancellableCoroutine { cont ->
                val resolve = object : NsdManager.ResolveListener {
                    override fun onResolveFailed(info: NsdServiceInfo, errorCode: Int) {
                        if (cont.isActive) cont.resume(null)
                    }

                    override fun onServiceResolved(info: NsdServiceInfo) {
                        val address = info.host?.hostAddress
                        if (cont.isActive) cont.resume(if (address == null) null else pairing.copy(host = address, port = info.port))
                    }
                }
                val discovery = object : NsdManager.DiscoveryListener {
                    override fun onDiscoveryStarted(serviceType: String) {}
                    override fun onDiscoveryStopped(serviceType: String) {}
                    override fun onServiceLost(info: NsdServiceInfo) {}
                    override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                        if (cont.isActive) cont.resume(null)
                    }

                    override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
                    override fun onServiceFound(info: NsdServiceInfo) {
                        if (matchesService(info.serviceName, pairing.deviceId)) {
                            runCatching { nsd.resolveService(info, resolve) }.onFailure { if (cont.isActive) cont.resume(null) }
                        }
                    }
                }
                listener = discovery
                runCatching { nsd.discoverServices(SyncProtocol.BONJOUR_TYPE, NsdManager.PROTOCOL_DNS_SD, discovery) }
                    .onFailure { if (cont.isActive) cont.resume(null) }
            }
        } finally {
            listener?.let { runCatching { nsd.stopServiceDiscovery(it) } }
            lock?.let { runCatching { if (it.isHeld) it.release() } }
        }
    }
}
