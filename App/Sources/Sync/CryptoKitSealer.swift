import CryptoKit
import Foundation
import UfuqCore

enum SealerError: Error, Equatable {
    case invalidKey
    case invalidNonce
    case malformed
}

/// AES-256-GCM through CryptoKit. Layout: `nonce (12) || ciphertext || tag (16)`, which is
/// exactly `AES.GCM.SealedBox.combined`; associated data is `ufuq-sync-v1`.
/// The Kotlin side is `AesGcmSealer` (javax.crypto) and the two share a known-answer vector.
struct CryptoKitSealer: SyncSealer {
    private let keyData: Data
    /// Test hook: a fixed nonce. Nil (the default) means a fresh random nonce per seal.
    private let fixedNonce: Data?

    init(keyData: Data, fixedNonce: Data? = nil) throws {
        guard keyData.count == PairingPayload.keyLength else { throw SealerError.invalidKey }
        self.keyData = keyData
        self.fixedNonce = fixedNonce
    }

    private var key: SymmetricKey { SymmetricKey(data: keyData) }

    func seal(_ plaintext: Data) throws -> Data {
        let box: AES.GCM.SealedBox
        if let fixedNonce {
            guard fixedNonce.count == SyncProtocol.nonceLength else { throw SealerError.invalidNonce }
            box = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(data: fixedNonce),
                                   authenticating: SyncProtocol.associatedData)
        } else {
            box = try AES.GCM.seal(plaintext, using: key, authenticating: SyncProtocol.associatedData)
        }
        guard let combined = box.combined else { throw SealerError.malformed }
        return combined
    }

    func open(_ sealed: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: sealed)
        return try AES.GCM.open(box, using: key, authenticating: SyncProtocol.associatedData)
    }
}
