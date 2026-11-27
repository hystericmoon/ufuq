import XCTest
import UfuqCore
@testable import Ufuq

final class SyncSealerTests: XCTestCase {
    // Shared with android/core/src/test/resources/fixtures/sync/seal_vector.json (AesGcmSealerTest).
    private let keyHex = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
    private let nonceHex = "a0a1a2a3a4a5a6a7a8a9aaab"
    private let plaintext = "ufuq sync known answer"
    private let sealedHex = "a0a1a2a3a4a5a6a7a8a9aaab937e095c65b87bd10145ecbd680daefe11c22a67f7c5886e3a61175eaec0816c3e087a453091"

    private func data(hex: String) -> Data {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return Data(bytes)
    }

    private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    func testKnownAnswerVector() throws {
        let sealer = try CryptoKitSealer(keyData: data(hex: keyHex), fixedNonce: data(hex: nonceHex))
        XCTAssertEqual(hex(try sealer.seal(Data(plaintext.utf8))), sealedHex)
        XCTAssertEqual(try sealer.open(data(hex: sealedHex)), Data(plaintext.utf8))
    }

    func testRoundTripUsesFreshNonces() throws {
        let sealer = try CryptoKitSealer(keyData: Data(0..<32))
        let a = try sealer.seal(Data("hello".utf8))
        let b = try sealer.seal(Data("hello".utf8))
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.count, SyncProtocol.nonceLength + 5 + SyncProtocol.tagLength)
        XCTAssertEqual(try sealer.open(a), Data("hello".utf8))
        XCTAssertEqual(try sealer.open(try sealer.seal(Data())), Data())
    }

    func testRejectsTamperingWrongKeyAndShortBoxes() throws {
        let sealer = try CryptoKitSealer(keyData: Data(0..<32))
        var sealed = try sealer.seal(Data("secret".utf8))
        let original = sealed
        sealed[sealed.count - 1] ^= 1
        XCTAssertThrowsError(try sealer.open(sealed))
        XCTAssertThrowsError(try CryptoKitSealer(keyData: Data(repeating: 9, count: 32)).open(original))
        XCTAssertThrowsError(try sealer.open(Data(count: 10)))
    }

    func testRejectsBadKeyAndNonceLength() {
        XCTAssertThrowsError(try CryptoKitSealer(keyData: Data(count: 16))) { XCTAssertEqual($0 as? SealerError, .invalidKey) }
        XCTAssertThrowsError(try CryptoKitSealer(keyData: Data(0..<32), fixedNonce: Data(count: 8)).seal(Data())) {
            XCTAssertEqual($0 as? SealerError, .invalidNonce)
        }
    }

    func testRouterWorksWithCryptoKitSealer() async throws {
        let now = Date(timeIntervalSince1970: 1_795_856_400)
        let sealer = try CryptoKitSealer(keyData: Data(0..<32))
        let router = SyncRouter(sealer: sealer, log: SyncEventLog(), content: { SyncSnapshotContent() }, now: { now })

        let unpaired = await router.handle(HTTPRequest(method: "GET", path: "/v1/snapshot"))
        XCTAssertEqual(unpaired, HTTPResponse(status: 401))

        let token = try SyncAuth.token(sealer: sealer, now: now)
        let response = await router.handle(HTTPRequest(method: "GET", path: "/v1/snapshot", headers: ["x-ufuq-auth": token]))
        XCTAssertEqual(response.status, 200)
        let snapshot = try SyncCoding.decode(SyncSnapshot.self, from: try sealer.open(response.body))
        XCTAssertEqual(snapshot.generatedAt, now)
    }

    func testPairingPayloadKeyMatchesSealerKeyLength() throws {
        let key = try XCTUnwrap(SyncKeyStore.randomKey())
        XCTAssertEqual(key.count, PairingPayload.keyLength)
        XCTAssertNoThrow(try CryptoKitSealer(keyData: key))
    }
}
