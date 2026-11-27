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
    /// Bumped when the key changes, so the pairing view redraws.
    @Published private(set) var pairingRevision = 0

    /// What to share: wired to the usage and agent modules when they exist (empty until then).
    var contentProvider: @Sendable () async -> SyncSnapshotContent = { SyncSnapshotContent() }

    private let log = SyncEventLog()
    private var server: SyncServer?

    private static let deviceIDKey = "syncDeviceID"

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
        let router = SyncRouter(sealer: sealer, log: log, content: { await provider() })
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
        KeychainStore.deleteKey()
        pairingRevision += 1
        if server != nil {
            stop()
            start()
        }
    }

    /// The QR contents, or nil while the server has no port yet or sharing is off.
    func pairingPayload() -> PairingPayload? {
        guard isRunning, let port, let keyData = KeychainStore.loadKey() else { return nil }
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

    private func ensureKey() -> Data? {
        if let existing = KeychainStore.loadKey(), existing.count == PairingPayload.keyLength { return existing }
        guard let fresh = KeychainStore.randomKey(), KeychainStore.saveKey(fresh) else { return nil }
        return fresh
    }
}
