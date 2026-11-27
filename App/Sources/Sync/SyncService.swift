import Foundation
import SwiftUI
import UfuqCore

/// Owns the sync server, the pairing key and the event log. Off unless the user turns on
/// "Share with phone on this network".
@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    @Published private(set) var isRunning = false
    @Published private(set) var port: UInt16?
    /// Bumped when the key changes, so the pairing view shows the new code.
    @Published private(set) var pairingRevision = 0
    /// The paired phone's name (from `X-Ufuq-Client`), or nil when none has connected since
    /// pairing or the phone is too old to send it. Survives restarts.
    @Published private(set) var connectedPhone: String?
    /// When the paired phone last made an authenticated request.
    @Published private(set) var lastSeen: Date?
    /// True right after "Forget phone", until a phone pairs again.
    @Published private(set) var phoneWasForgotten = false

    /// What to share: wired to the usage and agent modules when they exist (empty until then).
    var contentProvider: @Sendable () async -> SyncSnapshotContent = { SyncSnapshotContent() }

    /// True once a phone has connected with the current key.
    var hasPairedPhone: Bool { lastSeen != nil }

    private let log = SyncEventLog()
    private let keyStore: SyncKeyStore
    private var server: SyncServer?

    private static let deviceIDKey = "syncDeviceID"
    private static let phoneNameKey = "syncConnectedPhone"
    private static let lastSeenKey = "syncLastSeen"

    init(keyStore: SyncKeyStore = .standard) {
        self.keyStore = keyStore
        let defaults = UserDefaults.standard
        connectedPhone = defaults.string(forKey: Self.phoneNameKey)
        if let seen = defaults.object(forKey: Self.lastSeenKey) as? Date { lastSeen = seen }
    }

    private var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: Self.deviceIDKey) { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: Self.deviceIDKey)
        return id
    }

    /// Starts or stops the server to match the setting.
    func apply() {
        if AppSettings.syncEnabled { start() } else { stop() }
    }

    func start() {
        guard server == nil else { return }
        guard let keyData = ensureKey(), let sealer = try? CryptoKitSealer(keyData: keyData) else {
            NSLog("Ufuq sync: no pairing key available")
            return
        }
        let provider = contentProvider
        // Requests still in flight with a forgotten key must not mark the phone as seen again.
        let revision = pairingRevision
        // Strong on purpose: the router lives in `server`, which `stop()` releases.
        let service = self
        let router = SyncRouter(
            sealer: sealer, log: log, content: { await provider() },
            onAuthenticated: { name, at in
                Task { @MainActor in service.markSeen(name: name, at: at, revision: revision) }
            })
        let server = SyncServer(router: router, serviceName: "ufuq-\(deviceID)")
        server.onPortChange = { [weak self] port in
            self?.port = port
            self?.isRunning = port != nil
        }
        do {
            try server.start()
            self.server = server
        } catch {
            NSLog("Ufuq sync: could not start: \(error)")
        }
    }

    func stop() {
        server?.stop()
        server = nil
        port = nil
        isRunning = false
    }

    /// Deletes the key. A running server restarts with a new one, so the old phone gets 401.
    func forgetPhone() {
        keyStore.deleteKey()
        connectedPhone = nil
        lastSeen = nil
        UserDefaults.standard.removeObject(forKey: Self.phoneNameKey)
        UserDefaults.standard.removeObject(forKey: Self.lastSeenKey)
        phoneWasForgotten = true
        pairingRevision += 1
        if server != nil {
            stop()
            start()
        }
    }

    /// The QR contents, or nil while the server has no port yet or sharing is off.
    func pairingPayload() -> PairingPayload? {
        guard isRunning, let port, let keyData = keyStore.loadKey() else { return nil }
        let host = ProcessInfo.processInfo.hostName
        return PairingPayload(host: host, port: Int(port), deviceId: deviceID, keyData: keyData,
                              name: Host.current().localizedName)
    }

    /// Queues a peek for the phone. No-op while sharing is off.
    func publish(_ event: PeekEvent) {
        guard isRunning else { return }
        let log = log
        Task { await log.append(event, at: Date()) }
    }

    private func markSeen(name: String?, at: Date, revision: Int) {
        guard revision == pairingRevision else { return }
        phoneWasForgotten = false
        lastSeen = at
        UserDefaults.standard.set(at, forKey: Self.lastSeenKey)
        if let name, name != connectedPhone {
            connectedPhone = name
            UserDefaults.standard.set(name, forKey: Self.phoneNameKey)
        }
    }

    private func ensureKey() -> Data? {
        if let existing = keyStore.loadKey(), existing.count == PairingPayload.keyLength { return existing }
        guard let fresh = SyncKeyStore.randomKey(), keyStore.saveKey(fresh) else { return nil }
        return fresh
    }
}
