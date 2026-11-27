import Foundation
import Security
import UfuqCore

/// The pairing key, kept in a 0600 file: `~/Library/Application Support/Ufuq/sync-key`.
///
/// It used to live in the login keychain, but the app is ad-hoc signed, so every update changes
/// the code signature and macOS asked for keychain access again. The first load after updating
/// moves a keychain key into the file (that one read may prompt one last time).
struct SyncKeyStore {
    static let fileName = "sync-key"

    /// `~/Library/Application Support/Ufuq`.
    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Ufuq", isDirectory: true)
    }

    static let standard = SyncKeyStore(directory: defaultDirectory, migratesFromKeychain: true)

    let directory: URL
    /// Off in tests, so they never touch the login keychain.
    let migratesFromKeychain: Bool

    init(directory: URL, migratesFromKeychain: Bool = false) {
        self.directory = directory
        self.migratesFromKeychain = migratesFromKeychain
    }

    var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    func loadKey() -> Data? {
        if let data = try? Data(contentsOf: fileURL) { return data }
        guard migratesFromKeychain, let legacy = LegacyKeychainKey.readOnce() else { return nil }
        guard saveKey(legacy) else { return legacy }
        LegacyKeychainKey.delete()
        return legacy
    }

    @discardableResult
    func saveKey(_ data: Data) -> Bool {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try data.write(to: fileURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return true
        } catch {
            NSLog("Ufuq sync: could not save the pairing key: \(error)")
            return false
        }
    }

    func deleteKey() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func randomKey() -> Data? {
        var bytes = [UInt8](repeating: 0, count: PairingPayload.keyLength)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        return Data(bytes)
    }
}

/// The key as versions up to 0.1.1 stored it. Read at most once, then deleted.
private enum LegacyKeychainKey {
    static let service = "app.ufuq.mac.sync"
    static let account = "pairing-key"
    /// Set on the one attempt, so a denied prompt is never shown again.
    static let attemptedFlag = "syncKeyKeychainMigrationAttempted"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func readOnce() -> Data? {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: attemptedFlag) else { return nil }
        defaults.set(true, forKey: attemptedFlag)

        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
