import XCTest
@testable import Ufuq

final class UpdatePolicyTests: XCTestCase {
    func testDisabledWhenKeyMissing() {
        XCTAssertFalse(UpdatePolicy.isEnabled(publicKey: nil))
        XCTAssertFalse(UpdatePolicy.isEnabled(publicKey: ""))
        XCTAssertFalse(UpdatePolicy.isEnabled(publicKey: "  \n"))
        XCTAssertFalse(UpdatePolicy.isEnabled(publicKey: "$(SPARKLE_PUBLIC_KEY)"))
    }

    func testEnabledWithKey() {
        XCTAssertTrue(UpdatePolicy.isEnabled(publicKey: "abc123+/=="))
    }

    func testVersionString() {
        XCTAssertEqual(UpdatePolicy.versionString(short: "0.1.0", build: "12"), "0.1.0 (12)")
        XCTAssertEqual(UpdatePolicy.versionString(short: "0.1.0", build: nil), "0.1.0")
        XCTAssertEqual(UpdatePolicy.versionString(short: "0.1.0", build: ""), "0.1.0")
        XCTAssertEqual(UpdatePolicy.versionString(short: "1.0", build: "1.0"), "1.0")
        XCTAssertEqual(UpdatePolicy.versionString(short: nil, build: nil), "0")
    }
}
