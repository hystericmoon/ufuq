import XCTest
@testable import UfuqCore

final class ActivityArbiterTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func act(_ id: String, _ source: ActivitySource, alert: Bool = false, deadline: Date? = nil, usage: Double? = nil) -> LiveActivity {
        LiveActivity(id: id, moduleID: id, source: source, text: id, accessibilityLabel: id,
                     isAlert: alert, deadline: deadline, usageFraction: usage)
    }

    // MARK: Priority

    func testPriorityOrderMatchesSpec() {
        let arbiter = ActivityArbiter()
        XCTAssertEqual(arbiter.priority(of: act("a", .agent, alert: true), at: t0), .alert)
        XCTAssertEqual(arbiter.priority(of: act("p", .prayer, deadline: t0 + 9 * 60), at: t0), .prayerSoon)
        XCTAssertEqual(arbiter.priority(of: act("ai", .aiUsage, usage: 0.80), at: t0), .aiUsageHigh)
        XCTAssertEqual(arbiter.priority(of: act("g", .agent), at: t0), .agentRunning)
        XCTAssertEqual(arbiter.priority(of: act("m", .nowPlaying), at: t0), .nowPlaying)
        XCTAssertEqual(arbiter.priority(of: act("o", .other), at: t0), .other)
        XCTAssertTrue(WingPriority.alert > .prayerSoon)
        XCTAssertTrue(WingPriority.prayerSoon > .aiUsageHigh)
        XCTAssertTrue(WingPriority.aiUsageHigh > .agentRunning)
        XCTAssertTrue(WingPriority.agentRunning > .nowPlaying)
        XCTAssertTrue(WingPriority.nowPlaying > .other)
    }

    func testPrayerSoonOnlyUnderTenMinutes() {
        let arbiter = ActivityArbiter()
        XCTAssertEqual(arbiter.priority(of: act("p", .prayer, deadline: t0 + 10 * 60), at: t0), .other)
        XCTAssertEqual(arbiter.priority(of: act("p", .prayer, deadline: t0 + 599), at: t0), .prayerSoon)
        XCTAssertEqual(arbiter.priority(of: act("p", .prayer, deadline: t0 - 1), at: t0), .other)
        XCTAssertEqual(arbiter.priority(of: act("p", .prayer), at: t0), .other)
    }

    func testAIHighOnlyFromEightyPercent() {
        let arbiter = ActivityArbiter()
        XCTAssertEqual(arbiter.priority(of: act("ai", .aiUsage, usage: 0.799), at: t0), .other)
        XCTAssertEqual(arbiter.priority(of: act("ai", .aiUsage, usage: 0.97), at: t0), .aiUsageHigh)
    }

    func testRankedIsStableForTies() {
        let arbiter = ActivityArbiter()
        let ranked = arbiter.ranked([act("m1", .nowPlaying), act("g", .agent), act("m2", .nowPlaying),
                                     act("x", .other, alert: true)], at: t0)
        XCTAssertEqual(ranked.map(\.id), ["x", "g", "m1", "m2"])
    }

    // MARK: Wings

    func testPrayerLeftAIRightRegardlessOfPriority() {
        var arbiter = ActivityArbiter()
        let layout = arbiter.layout(for: [act("g", .agent), act("ai", .aiUsage, usage: 0.1), act("p", .prayer)], at: t0)
        XCTAssertEqual(layout.left?.id, "p")
        XCTAssertEqual(layout.right?.id, "ai")
        XCTAssertNil(layout.rotating, "AI takes the first turn")
        XCTAssertEqual(layout.rightWingShown?.id, "ai")
        XCTAssertEqual(arbiter.layout(for: [act("g", .agent), act("ai", .aiUsage), act("p", .prayer)], at: t0 + 8).rotating?.id, "g")
    }

    func testEmptyHomeWingFilledByHighestPriority() {
        var arbiter = ActivityArbiter()
        let layout = arbiter.layout(for: [act("m", .nowPlaying), act("p", .prayer), act("g", .agent)], at: t0)
        XCTAssertEqual(layout.left?.id, "p")
        XCTAssertEqual(layout.right?.id, "g")
        XCTAssertNil(layout.rotating)
        XCTAssertEqual(arbiter.layout(for: [act("m", .nowPlaying), act("p", .prayer), act("g", .agent)], at: t0 + 8).rotating?.id, "m")
    }

    func testEmptyInput() {
        var arbiter = ActivityArbiter()
        XCTAssertEqual(arbiter.layout(for: [], at: t0), WingLayout())
    }

    // MARK: Rotation

    func testSharedRightWingCycle() {
        var arbiter = ActivityArbiter()
        let all = [act("p", .prayer), act("ai", .aiUsage), act("m", .nowPlaying), act("o", .other), act("g", .agent)]
        XCTAssertNil(arbiter.layout(for: all, at: t0).rotating)
        XCTAssertNil(arbiter.layout(for: all, at: t0 + 7.9).rotating)
        XCTAssertEqual(arbiter.layout(for: all, at: t0 + 8).rotating?.id, "g")
        XCTAssertEqual(arbiter.layout(for: all, at: t0 + 15).rotating?.id, "g")
        XCTAssertEqual(arbiter.layout(for: all, at: t0 + 16).rotating?.id, "m")
        XCTAssertEqual(arbiter.layout(for: all, at: t0 + 24).rotating?.id, "o")
        let wrapped = arbiter.layout(for: all, at: t0 + 32)
        XCTAssertNil(wrapped.rotating, "wraps back to AI")
        XCTAssertEqual(wrapped.rightWingShown?.id, "ai")
    }

    func testNoPoolMeansAIAlways() {
        var arbiter = ActivityArbiter()
        let all = [act("p", .prayer), act("ai", .aiUsage)]
        for s in stride(from: 0.0, through: 40, by: 4) {
            let layout = arbiter.layout(for: all, at: t0 + s)
            XCTAssertNil(layout.rotating)
            XCTAssertEqual(layout.rightWingShown?.id, "ai")
        }
    }

    func testWithoutAIPoolRotatesAlone() {
        // No AI: the highest-priority leftover (g) fills the right wing and the pool cycles with it.
        var arbiter = ActivityArbiter()
        let all = [act("g", .agent), act("m", .nowPlaying), act("o", .other), act("p", .prayer)]
        XCTAssertNil(arbiter.layout(for: all, at: t0).rotating)
        XCTAssertEqual(arbiter.layout(for: all, at: t0 + 8).rotating?.id, "m")
        XCTAssertEqual(arbiter.layout(for: all, at: t0 + 16).rotating?.id, "o")
        XCTAssertNil(arbiter.layout(for: all, at: t0 + 24).rotating)
        // Only a pinned alert and no right wing: the pool is just the alert.
        var b = ActivityArbiter()
        let layout = b.layout(for: [act("p", .prayer), act("bat", .other, alert: true)], at: t0)
        XCTAssertNil(layout.right)
        XCTAssertEqual(layout.rightWingShown?.id, "bat")
    }

    func testRemovedRotatingItemIsReplaced() {
        var arbiter = ActivityArbiter()
        let p = act("p", .prayer), ai = act("ai", .aiUsage)
        XCTAssertNil(arbiter.layout(for: [p, ai, act("g", .agent), act("m", .nowPlaying)], at: t0).rotating)
        XCTAssertEqual(arbiter.layout(for: [p, ai, act("g", .agent), act("m", .nowPlaying)], at: t0 + 8).rotating?.id, "g")
        // g goes away mid-turn: the cycle restarts without resetting to a stale item.
        XCTAssertNotEqual(arbiter.layout(for: [p, ai, act("m", .nowPlaying)], at: t0 + 10).rotating?.id, "g")
        XCTAssertNil(arbiter.layout(for: [p, ai], at: t0 + 11).rotating)
    }

    func testNewItemDoesNotResetTurn() {
        var arbiter = ActivityArbiter()
        let p = act("p", .prayer), ai = act("ai", .aiUsage), g = act("g", .agent)
        XCTAssertNil(arbiter.layout(for: [p, ai, g], at: t0).rotating)
        let m = act("m", .nowPlaying)
        XCTAssertNil(arbiter.layout(for: [p, ai, g, m], at: t0 + 5).rotating, "still AI's turn")
        XCTAssertEqual(arbiter.layout(for: [p, ai, g, m], at: t0 + 8).rotating?.id, "g")
    }

    func testAlertPinsRightWingAndHidesAI() {
        var arbiter = ActivityArbiter()
        let base = [act("p", .prayer), act("ai", .aiUsage), act("g", .agent), act("m", .nowPlaying)]
        let withAlert = base + [act("bat", .other, alert: true)]
        for s in [0.0, 8, 30] {
            let layout = arbiter.layout(for: withAlert, at: t0 + s)
            XCTAssertEqual(layout.rotating?.id, "bat")
            XCTAssertEqual(layout.rightWingShown?.id, "bat")
        }
        // Alert cleared: the cycle resumes from AI.
        XCTAssertNil(arbiter.layout(for: base, at: t0 + 31).rotating)
        XCTAssertEqual(arbiter.layout(for: base, at: t0 + 39).rotating?.id, "g")
    }

    func testAlertNeverTakesHomeWing() {
        var arbiter = ActivityArbiter()
        let layout = arbiter.layout(for: [act("p", .prayer), act("bat", .other, alert: true)], at: t0)
        XCTAssertEqual(layout.left?.id, "p")
        XCTAssertNil(layout.right)
        XCTAssertEqual(layout.rotating?.id, "bat")
    }

    func testCustomInterval() {
        var arbiter = ActivityArbiter(rotationInterval: 2)
        let all = [act("p", .prayer), act("ai", .aiUsage), act("g", .agent), act("m", .nowPlaying)]
        XCTAssertNil(arbiter.layout(for: all, at: t0).rotating)
        XCTAssertEqual(arbiter.layout(for: all, at: t0 + 2).rotating?.id, "g")
        XCTAssertEqual(arbiter.layout(for: all, at: t0 + 4).rotating?.id, "m")
    }

    func testAdvanceRotationAdvancesImmediatelyAndRespectsAlerts() {
        var arbiter = ActivityArbiter()
        let all = [act("p", .prayer), act("ai", .aiUsage), act("g", .agent), act("m", .nowPlaying)]
        XCTAssertNil(arbiter.layout(for: all, at: t0).rotating)
        arbiter.advanceRotation()
        XCTAssertEqual(arbiter.layout(for: all, at: t0 + 1).rotating?.id, "g")
        arbiter.advanceRotation()
        XCTAssertEqual(arbiter.layout(for: all, at: t0 + 2).rotating?.id, "m")

        // Pinned alert stays pinned even if advanceRotation() is called.
        let withAlert = all + [act("bat", .other, alert: true)]
        XCTAssertEqual(arbiter.layout(for: withAlert, at: t0 + 3).rotating?.id, "bat")
        arbiter.advanceRotation()
        XCTAssertEqual(arbiter.layout(for: withAlert, at: t0 + 4).rotating?.id, "bat")
    }
}
