import Foundation

/// The JSON in the pairing QR code.
public struct PairingPayload: Codable, Equatable, Sendable {
    public static let keyLength = 32

    public enum PairingError: Error, Equatable {
        case malformed
        case unsupportedVersion(Int)
        case invalidKey
        case invalidPort
    }

    /// Payload format version (`v` on the wire).
    public var v: Int
    /// A hint only (the Mac's `.local` name); the phone prefers the Bonjour-resolved address.
    public var host: String
    public var port: Int
    public var deviceId: String
    /// 32 random bytes, base64url without padding.
    public var key: String
    /// The Mac's display name, for the phone's list.
    public var name: String?

    public init(v: Int = SyncProtocol.version, host: String, port: Int, deviceId: String, key: String, name: String? = nil) {
        self.v = v
        self.host = host
        self.port = port
        self.deviceId = deviceId
        self.key = key
        self.name = name
    }

    public init(host: String, port: Int, deviceId: String, keyData: Data, name: String? = nil) {
        self.init(host: host, port: port, deviceId: deviceId, key: SyncCoding.base64URLEncode(keyData), name: name)
    }

    public var keyData: Data? { SyncCoding.base64URLDecode(key) }

    public func encoded() throws -> Data { try SyncCoding.encode(self) }

    public func encodedString() throws -> String {
        String(decoding: try encoded(), as: UTF8.self)
    }

    /// Parses and validates a scanned QR string.
    public static func decode(_ text: String) throws -> PairingPayload {
        try decode(Data(text.utf8))
    }

    public static func decode(_ data: Data) throws -> PairingPayload {
        let payload: PairingPayload
        do { payload = try SyncCoding.decode(PairingPayload.self, from: data) } catch { throw PairingError.malformed }
        guard payload.v == SyncProtocol.version else { throw PairingError.unsupportedVersion(payload.v) }
        guard payload.keyData?.count == keyLength else { throw PairingError.invalidKey }
        guard (1...65535).contains(payload.port) else { throw PairingError.invalidPort }
        guard !payload.deviceId.isEmpty else { throw PairingError.malformed }
        return payload
    }
}
