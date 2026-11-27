import XCTest
@testable import UfuqCore

final class SyncModelTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/sync/\(name)", withExtension: nil))
        return try Data(contentsOf: url)
    }

    private func trimmed(_ data: Data) -> Data {
        Data(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    }


    static var snapshot: SyncSnapshot {
        let generated = Date(timeIntervalSince1970: 1_795_856_400)
        return SyncSnapshot(
            generatedAt: generated,
            readings: [
                SyncReading(accountId: "claude-work", accountName: "Claude Work", provider: .claude,
                            kind: "session5h", fraction: 0.82, capturedAt: generated.addingTimeInterval(-30),
                            resetsAt: generated.addingTimeInterval(4320)),
                SyncReading(accountId: "claude-work", accountName: "Claude Work", provider: .claude,
                            kind: "weekly", fraction: 0.4, capturedAt: generated.addingTimeInterval(-30),
                            isEstimated: true),
                SyncReading(accountId: "ag", accountName: "Antigravity", provider: .antigravity,
                            kind: "modelGroup", group: "Gemini Pro", fraction: 0.05,
                            capturedAt: generated.addingTimeInterval(-60)),
            ],
            agents: [
                SyncAgent(id: "a1", title: "Refactor sync", state: .waiting, updatedAt: generated.addingTimeInterval(-10)),
                SyncAgent(id: "a2", title: "Fix tests", state: .running, updatedAt: generated.addingTimeInterval(-90)),
            ])
    }

    func testSnapshotMatchesGoldenJSON() throws {
        let golden = try fixture("snapshot.json")
        XCTAssertEqual(trimmed(try SyncCoding.encode(Self.snapshot)), trimmed(golden))
        XCTAssertEqual(try SyncCoding.decode(SyncSnapshot.self, from: golden), Self.snapshot)
    }

    func testSnapshotEncodingIsStable() throws {
        XCTAssertEqual(try SyncCoding.encode(Self.snapshot), try SyncCoding.encode(Self.snapshot))
    }

    func testReadingFromUsageWindowReading() {
        let account = UsageAccount(id: "x", provider: .antigravity, displayName: "AG")
        let snap = UsageSnapshot(fraction: 0.5, capturedAt: Date(timeIntervalSince1970: 100), resetsAt: nil)
        let reading = SyncReading(account: account, reading: UsageWindowReading(kind: .modelGroup("Flash"), snapshot: snap, isEstimated: true))
        XCTAssertEqual(reading.kind, "modelGroup")
        XCTAssertEqual(reading.group, "Flash")
        XCTAssertTrue(reading.isEstimated)
        XCTAssertEqual(reading.accountName, "AG")
    }

    func testPairingMatchesGoldenJSON() throws {
        let golden = try fixture("pairing.json")
        let payload = PairingPayload(host: "Mac-mini.local", port: 49152, deviceId: "6f1d2c3a-0b4e-4f5a-9c7d-1a2b3c4d5e6f",
                                     keyData: Data(0..<32), name: "Mac mini")
        XCTAssertEqual(trimmed(try payload.encoded()), trimmed(golden))
        XCTAssertEqual(try PairingPayload.decode(golden), payload)
        XCTAssertEqual(payload.keyData, Data(0..<32))
    }

    func testPairingRejectsBadInput() throws {
        func make(v: Int = 1, port: Int = 1000, key: String = SyncCoding.base64URLEncode(Data(0..<32)), device: String = "d") throws -> Data {
            try PairingPayload(v: v, host: "h", port: port, deviceId: device, key: key).encoded()
        }
        XCTAssertThrowsError(try PairingPayload.decode("not json")) { XCTAssertEqual($0 as? PairingPayload.PairingError, .malformed) }
        XCTAssertThrowsError(try PairingPayload.decode(try make(v: 2))) { XCTAssertEqual($0 as? PairingPayload.PairingError, .unsupportedVersion(2)) }
        XCTAssertThrowsError(try PairingPayload.decode(try make(key: "AAAA"))) { XCTAssertEqual($0 as? PairingPayload.PairingError, .invalidKey) }
        XCTAssertThrowsError(try PairingPayload.decode(try make(port: 0))) { XCTAssertEqual($0 as? PairingPayload.PairingError, .invalidPort) }
        XCTAssertThrowsError(try PairingPayload.decode(try make(device: ""))) { XCTAssertEqual($0 as? PairingPayload.PairingError, .malformed) }
    }

    func testBase64URL() {
        let data = Data([0xfb, 0xff, 0xfe, 0x00])
        let text = SyncCoding.base64URLEncode(data)
        XCTAssertEqual(text, "-__-AA")
        XCTAssertEqual(SyncCoding.base64URLDecode(text), data)
    }

    func testSealVectorFixtureShape() throws {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("seal_vector.json")) as? [String: String])
        let sealed = try XCTUnwrap(json["sealedHex"])
        let plain = try XCTUnwrap(json["plaintextUtf8"])
        XCTAssertEqual(sealed.count / 2, SyncProtocol.nonceLength + plain.utf8.count + SyncProtocol.tagLength)
        XCTAssertTrue(sealed.hasPrefix(try XCTUnwrap(json["nonceHex"])))
        XCTAssertEqual(json["aad"], String(decoding: SyncProtocol.associatedData, as: UTF8.self))
    }
}
