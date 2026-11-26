import XCTest
@testable import UfuqCore

final class PeekQueueTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func peek(_ id: String, _ priority: PeekEvent.Priority = .normal, module: String = "m") -> PeekEvent {
        PeekEvent(id: id, moduleID: module, title: id, message: "", priority: priority)
    }

    func testShowsOneAtATimeFIFO() {
        var q = PeekQueue()
        q.enqueue(peek("a"), at: t0)
        q.enqueue(peek("b"), at: t0)
        q.enqueue(peek("c"), at: t0)
        XCTAssertEqual(q.current?.id, "a")
        XCTAssertEqual(q.pending.map(\.id), ["b", "c"])
    }

    func testAutoDismissAfterSixSeconds() {
        var q = PeekQueue()
        q.enqueue(peek("a"), at: t0)
        q.enqueue(peek("b"), at: t0)
        q.tick(at: t0 + 5.9)
        XCTAssertEqual(q.current?.id, "a")
        q.tick(at: t0 + 6)
        XCTAssertEqual(q.current?.id, "b")
        q.tick(at: t0 + 12)
        XCTAssertNil(q.current)
    }

    func testCriticalJumpsWaitingNormals() {
        var q = PeekQueue()
        q.enqueue(peek("n0", .critical), at: t0)   // showing
        q.enqueue(peek("a"), at: t0)
        q.enqueue(peek("b"), at: t0)
        q.enqueue(peek("c1", .critical), at: t0)
        q.enqueue(peek("c2", .critical), at: t0)
        XCTAssertEqual(q.current?.id, "n0", "critical does not preempt critical")
        XCTAssertEqual(q.pending.map(\.id), ["c1", "c2", "a", "b"])
    }

    func testCriticalPreemptsShowingNormalWhichReturnsFirst() {
        var q = PeekQueue()
        q.enqueue(peek("a"), at: t0)
        q.enqueue(peek("b"), at: t0)
        q.enqueue(peek("adhan", .critical), at: t0 + 2)
        XCTAssertEqual(q.current?.id, "adhan")
        XCTAssertEqual(q.pending.map(\.id), ["a", "b"])
        q.tick(at: t0 + 8)
        XCTAssertEqual(q.current?.id, "a")
        q.tick(at: t0 + 13.9)
        XCTAssertEqual(q.current?.id, "a", "returns with its full duration")
        q.tick(at: t0 + 14)
        XCTAssertEqual(q.current?.id, "b")
    }

    func testHoverHoldsAndResumesRemainingTime() {
        var q = PeekQueue()
        q.enqueue(peek("a"), at: t0)
        q.enqueue(peek("b"), at: t0)
        q.setHovering(true, at: t0 + 4)
        XCTAssertTrue(q.isHeld)
        q.tick(at: t0 + 60)
        XCTAssertEqual(q.current?.id, "a")
        q.setHovering(false, at: t0 + 60)
        q.tick(at: t0 + 61.9)
        XCTAssertEqual(q.current?.id, "a")
        q.tick(at: t0 + 62)
        XCTAssertEqual(q.current?.id, "b")
        XCTAssertFalse(q.isHeld)
    }

    func testDismissShowsNext() {
        var q = PeekQueue()
        q.enqueue(peek("a"), at: t0)
        q.enqueue(peek("b"), at: t0)
        q.dismissCurrent(at: t0 + 1)
        XCTAssertEqual(q.current?.id, "b")
        q.tick(at: t0 + 6.9)
        XCTAssertEqual(q.current?.id, "b")
        q.tick(at: t0 + 7)
        XCTAssertNil(q.current)
    }

    func testSameIDReplacesInsteadOfDuplicating() {
        var q = PeekQueue()
        q.enqueue(peek("a"), at: t0)
        q.enqueue(peek("b"), at: t0)
        q.enqueue(peek("b"), at: t0)
        q.enqueue(peek("a"), at: t0)
        XCTAssertEqual(q.current?.id, "a")
        XCTAssertEqual(q.pending.map(\.id), ["b"])
    }

    func testRemoveAllFromModule() {
        var q = PeekQueue()
        q.enqueue(peek("a", module: "ai"), at: t0)
        q.enqueue(peek("b", module: "prayer"), at: t0)
        q.enqueue(peek("c", module: "ai"), at: t0)
        q.removeAll(fromModule: "ai", at: t0)
        XCTAssertEqual(q.current?.id, "b")
        XCTAssertTrue(q.pending.isEmpty)
    }

    func testAnnouncementDefault() {
        let p = PeekEvent(id: "x", moduleID: "ai", title: "Claude Work at 95%", message: "Resets in 40 minutes", priority: .critical)
        XCTAssertEqual(p.announcement, "Claude Work at 95%. Resets in 40 minutes")
        XCTAssertEqual(p.duration, 6)
    }
}
