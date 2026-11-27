import XCTest
import UfuqCore
@testable import Ufuq

final class SyncKeyStoreTests: XCTestCase {
    private var root: URL!
    private var directory: URL { root.appendingPathComponent("Ufuq", isDirectory: true) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncKeyStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSaveLoadDeleteRoundTrip() throws {
        let store = SyncKeyStore(directory: directory)
        XCTAssertNil(store.loadKey())

        let key = try XCTUnwrap(SyncKeyStore.randomKey())
        XCTAssertTrue(store.saveKey(key))
        XCTAssertEqual(store.loadKey(), key)
        XCTAssertEqual(store.fileURL.lastPathComponent, "sync-key")

        let replacement = Data(repeating: 7, count: PairingPayload.keyLength)
        XCTAssertTrue(store.saveKey(replacement))
        XCTAssertEqual(store.loadKey(), replacement)

        store.deleteKey()
        XCTAssertNil(store.loadKey())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testKeyFileIsOwnerReadWriteOnly() throws {
        let store = SyncKeyStore(directory: directory)
        XCTAssertTrue(store.saveKey(Data(0..<32)))
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue, 0o600)
    }
}

final class PhoneStatusTextTests: XCTestCase {
    @MainActor
    func testStatusText() {
        let now = Date(timeIntervalSince1970: 1_795_856_400)
        XCTAssertEqual(PhoneStatusRow.text(phone: nil, lastSeen: nil, now: now), "No phone paired yet")
        XCTAssertEqual(
            PhoneStatusRow.text(phone: "Samsung SM-S928B", lastSeen: now.addingTimeInterval(-10), now: now),
            "Paired with Samsung SM-S928B · seen just now")
        XCTAssertTrue(
            PhoneStatusRow.text(phone: nil, lastSeen: now.addingTimeInterval(-120), now: now)
                .hasPrefix("Paired with a phone · seen "))
    }
}
