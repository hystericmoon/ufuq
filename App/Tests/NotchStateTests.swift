import XCTest
import UfuqCore
@testable import Ufuq

final class NotchStateTests: XCTestCase {
    private let peek = PeekEvent(id: "p1", moduleID: "prayer", title: "Ashar", message: "in 10 minutes")

    func testOtherDisplaysStayCollapsedWhileOneIsExpanded() {
        XCTAssertEqual(NotchState.shown(.expanded, onActiveDisplay: true), .expanded)
        XCTAssertEqual(NotchState.shown(.expanded, onActiveDisplay: false), .collapsed)
        XCTAssertEqual(NotchState.shown(.expanded, onActiveDisplay: false, peek: peek), .peek(peek))
        // Collapsed and peek are the same on every display.
        XCTAssertEqual(NotchState.shown(.peek(peek), onActiveDisplay: false), .peek(peek))
        XCTAssertEqual(NotchState.shown(.collapsed, onActiveDisplay: false), .collapsed)
    }

    func testStartsCollapsed() {
        XCTAssertEqual(NotchStateMachine().state, .collapsed)
    }

    func testHotkeyTogglesExpanded() {
        var m = NotchStateMachine()
        m.toggleWithHotkey()
        XCTAssertEqual(m.state, .expanded)
        XCTAssertEqual(m.origin, .hotkey)
        m.toggleWithHotkey()
        XCTAssertEqual(m.state, .collapsed)
    }

    func testEscapeClosesExpanded() {
        var m = NotchStateMachine()
        m.toggleWithHotkey()
        XCTAssertEqual(m.escape(), .collapsed)
        XCTAssertEqual(m.state, .collapsed)
    }

    func testEscapeDismissesPeekThenIgnores() {
        var m = NotchStateMachine()
        m.setPeek(peek)
        XCTAssertEqual(m.state, .peek(peek))
        XCTAssertEqual(m.escape(), .dismissedPeek)
        XCTAssertEqual(m.state, .collapsed)
        XCTAssertEqual(m.escape(), .ignored)
    }

    func testExpandedWinsOverPeekAndPeekReturnsAfter() {
        var m = NotchStateMachine()
        m.setPeek(peek)
        m.toggleWithHotkey()
        XCTAssertEqual(m.state, .expanded)
        m.toggleWithHotkey()
        XCTAssertEqual(m.state, .peek(peek))
    }

    func testPeekEndsWhenQueueEmpties() {
        var m = NotchStateMachine()
        m.setPeek(peek)
        m.setPeek(nil)
        XCTAssertEqual(m.state, .collapsed)
    }

    func testHoverOpensOnlyWhenEnabled() {
        var m = NotchStateMachine()
        m.mouseEntered(hoverEnabled: false)
        XCTAssertEqual(m.state, .collapsed)
        m.mouseEntered(hoverEnabled: true)
        XCTAssertEqual(m.state, .expanded)
        XCTAssertEqual(m.origin, .hover)
    }

    func testMouseExitCollapsesOnlyHoverOpened() {
        var hover = NotchStateMachine()
        hover.mouseEntered(hoverEnabled: true)
        hover.mouseExited()
        XCTAssertEqual(hover.state, .collapsed)

        var hotkey = NotchStateMachine()
        hotkey.toggleWithHotkey()
        hotkey.mouseExited()
        XCTAssertEqual(hotkey.state, .expanded)
    }

    func testHotkeyAfterHoverKeepsPanelOpenOnExit() {
        var m = NotchStateMachine()
        m.mouseEntered(hoverEnabled: true)
        m.open(origin: .hotkey)
        m.mouseExited()
        XCTAssertEqual(m.state, .expanded)
    }

    func testPeekQueueDrivesPeekAutoReturn() {
        var queue = PeekQueue()
        var m = NotchStateMachine()
        let t0 = Date(timeIntervalSince1970: 1_000)
        queue.enqueue(peek, at: t0)
        m.setPeek(queue.current)
        XCTAssertEqual(m.state, .peek(peek))
        queue.tick(at: t0.addingTimeInterval(PeekEvent.defaultDuration + 0.1))
        m.setPeek(queue.current)
        XCTAssertEqual(m.state, .collapsed)
    }
}
