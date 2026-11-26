import Foundation
import Security

/// The pairing key, kept in the login keychain as a generic password.
enum KeychainStore {
    static let service = "app.ufuq.mac.sync"
    static let account = "pairing-key"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func loadKey() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    static func saveKey(_ data: Data) -> Bool {
        SecItemDelete(baseQuery as CFDictionary)
        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func deleteKey() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    static func randomKey() -> Data? {
        var bytes = [UInt8](repeating: 0, count: PairingPayload.keyLength)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        return Data(bytes)
    }
}
