import XCTest
@testable import UfuqCore

final class UsageThresholdTests: XCTestCase {
    let t = UsageThresholds.default
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testLevels() {
        XCTAssertEqual(t.level(for: 0), .normal)
        XCTAssertEqual(t.level(for: 0.7999), .normal)
        XCTAssertEqual(t.level(for: 0.80), .warning)
        XCTAssertEqual(t.level(for: 0.9499), .warning)
        XCTAssertEqual(t.level(for: 0.95), .critical)
        XCTAssertEqual(t.level(for: 1.0), .critical)
    }

    func testOutOfRangeIsClamped() {
        XCTAssertEqual(t.level(for: 1.7), .critical)
        XCTAssertEqual(t.level(for: -0.2), .normal)
        XCTAssertEqual(t.level(for: .nan), .normal)
    }

    func snap(_ f: Double, reset: TimeInterval? = nil) -> UsageSnapshot {
        UsageSnapshot(fraction: f, capturedAt: t0, resetsAt: reset.map { t0 + $0 })
    }

    func testAlertsFireOnceOnCrossingUp() {
        XCTAssertNil(t.alert(from: nil, to: snap(0.9)))
        XCTAssertNil(t.alert(from: snap(0.5), to: snap(0.79)))
        XCTAssertEqual(t.alert(from: snap(0.79), to: snap(0.80)), .reachedWarning)
        XCTAssertNil(t.alert(from: snap(0.81), to: snap(0.90)))
        XCTAssertEqual(t.alert(from: snap(0.90), to: snap(0.95)), .reachedCritical)
        XCTAssertEqual(t.alert(from: snap(0.5), to: snap(0.99)), .reachedCritical, "skipping amber goes straight to red")
        XCTAssertNil(t.alert(from: snap(0.96), to: snap(0.99)))
        XCTAssertNil(t.alert(from: snap(0.96), to: snap(0.85)), "falling never alerts")
    }

    func testResetAlert() {
        XCTAssertEqual(t.alert(from: snap(0.9, reset: 100), to: snap(0.0, reset: 18_100)), .reset)
        XCTAssertNil(t.alert(from: snap(0.1, reset: 100), to: snap(0.2, reset: 100)))
    }

    func testCriticalAlertJumpsPeekQueue() {
        XCTAssertEqual(UsageAlert.reachedCritical.peekPriority, .critical)
        XCTAssertEqual(UsageAlert.reachedWarning.peekPriority, .normal)
        XCTAssertEqual(UsageAlert.reset.peekPriority, .normal)
    }
}

final class BurnRateTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func s(_ minutes: Double, _ f: Double, resetIn: Double? = nil) -> UsageSnapshot {
        UsageSnapshot(fraction: f, capturedAt: t0 + minutes * 60, resetsAt: resetIn.map { t0 + $0 * 60 })
    }

    func testLinearBurn() throws {
        // 1% per minute; at 40% after 30 min → 60 min to the limit.
        let samples = stride(from: 0.0, through: 30, by: 5).map { s($0, 0.10 + $0 / 100) }
        let e = try XCTUnwrap(BurnRate.estimate(samples: samples))
        XCTAssertEqual(e.fractionPerHour, 0.60, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(e.timeToLimit), 60 * 60, accuracy: 1e-6)
        XCTAssertTrue(e.hitsLimitBeforeReset)
    }

    func testResetAfterLimitMeansNoHit() throws {
        let samples = [s(0, 0.10, resetIn: 60), s(30, 0.40, resetIn: 60)]
        let e = try XCTUnwrap(BurnRate.estimate(samples: samples))
        XCTAssertFalse(e.hitsLimitBeforeReset, "limit at 90 min, reset at 60 min")
        let early = [s(0, 0.10, resetIn: 120), s(30, 0.40, resetIn: 120)]
        XCTAssertTrue(try XCTUnwrap(BurnRate.estimate(samples: early)).hitsLimitBeforeReset)
    }

    func testFlatUsageHasNoTimeToLimit() throws {
        let e = try XCTUnwrap(BurnRate.estimate(samples: [s(0, 0.5), s(10, 0.5), s(20, 0.5)]))
        XCTAssertEqual(e.fractionPerHour, 0)
        XCTAssertNil(e.timeToLimit)
        XCTAssertFalse(e.hitsLimitBeforeReset)
    }

    func testNeedsTwoSamplesAndMinimumSpan() {
        XCTAssertNil(BurnRate.estimate(samples: []))
        XCTAssertNil(BurnRate.estimate(samples: [s(0, 0.1)]))
        XCTAssertNil(BurnRate.estimate(samples: [s(0, 0.1), s(4, 0.2)]), "under 5 min span")
        XCTAssertNotNil(BurnRate.estimate(samples: [s(0, 0.1), s(5, 0.2)]))
    }

    func testIgnoresSamplesBeforeReset() throws {
        // Old window climbed fast to 90%, then reset; new window climbs 0.5% per minute.
        let samples = [s(0, 0.50), s(10, 0.90), s(20, 0.00), s(30, 0.05), s(40, 0.10)]
        let e = try XCTUnwrap(BurnRate.estimate(samples: samples))
        XCTAssertEqual(e.fractionPerHour, 0.30, accuracy: 1e-9)
    }

    func testOnlyRecentPaceCounts() throws {
        // Slow for 2 h, then 2% per minute in the last hour.
        var samples = stride(from: 0.0, through: 120, by: 10).map { s($0, $0 / 1200) }
        samples += stride(from: 130.0, through: 180, by: 10).map { s($0, 0.10 + ($0 - 120) / 50) }
        let e = try XCTUnwrap(BurnRate.estimate(samples: samples))
        XCTAssertGreaterThan(e.fractionPerHour, 1.0)
    }

    func testUnsortedInputAndAlreadyAtLimit() throws {
        let e = try XCTUnwrap(BurnRate.estimate(samples: [s(10, 1.0), s(0, 0.9)]))
        XCTAssertEqual(e.timeToLimit, 0)
    }
}
