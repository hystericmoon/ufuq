import XCTest
import UfuqCore
@testable import Ufuq

final class TrayTests: XCTestCase {
    // MARK: - ShakeDetector

    private func feed(_ xs: [CGFloat], step: TimeInterval) -> Bool {
        var detector = ShakeDetector()
        var shook = false
        for (i, x) in xs.enumerated() {
            if detector.add(x: x, at: Double(i) * step) { shook = true }
        }
        return shook
    }

    func testThreeReversalsInHalfASecondShake() {
        // right, left, right, left: the last three moves each reverse the one before.
        XCTAssertTrue(feed([0, 30, 0, 30, 0], step: 0.1))
    }

    func testSlowMovesDoNotShake() {
        XCTAssertFalse(feed([0, 30, 0, 30, 0], step: 0.3))
    }

    func testSmallMovesDoNotShake() {
        XCTAssertFalse(feed([0, 10, 0, 10, 0, 10, 0], step: 0.05))
    }

    func testSteadyDragDoesNotShake() {
        XCTAssertFalse(feed([0, 40, 80, 120, 160, 200, 240], step: 0.05))
    }

    func testDetectorResetsAfterShake() {
        var detector = ShakeDetector()
        var count = 0
        for (i, x) in ([0, 30, 0, 30, 0, 30, 0] as [CGFloat]).enumerated() {
            if detector.add(x: x, at: Double(i) * 0.1) { count += 1 }
        }
        XCTAssertEqual(count, 1)
    }

    // MARK: - FileDragState

    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func testDistanceAndXAreMeasuredFromTopEdgeAndBodyCentre() {
        let state = FileDragState.make(pointer: CGPoint(x: 800, y: 982 - 100), screenFrame: screen, bodyMidX: 756)
        XCTAssertEqual(state, FileDragState(distance: 100, x: 44))
        XCTAssertEqual(state?.overDropZone, false)
    }

    func testDropZoneIsWithinSixtyPoints() {
        XCTAssertEqual(FileDragState(distance: 59, x: 0).overDropZone, true)
        XCTAssertEqual(FileDragState(distance: 60, x: 0).overDropZone, false)
    }

    func testNoStateBeyondReach() {
        XCTAssertNil(FileDragState.make(pointer: CGPoint(x: 756, y: 982 - 161), screenFrame: screen, bodyMidX: 756))
        XCTAssertNotNil(FileDragState.make(pointer: CGPoint(x: 756, y: 982 - 160), screenFrame: screen, bodyMidX: 756))
    }

    func testNoStateFarFromTheBody() {
        XCTAssertNil(FileDragState.make(pointer: CGPoint(x: 100, y: 960), screenFrame: screen, bodyMidX: 756))
    }

    func testAtTopEdgeDistanceIsZero() {
        XCTAssertEqual(FileDragState.make(pointer: CGPoint(x: 756, y: 982), screenFrame: screen, bodyMidX: 756)?.distance, 0)
    }

    // MARK: - .drag origin

    func testDragOpensWithDragOrigin() {
        var m = NotchStateMachine()
        m.dragEntered()
        XCTAssertEqual(m.state, .expanded)
        XCTAssertEqual(m.origin, .drag)
    }

    func testDragDoesNotChangeAnOpenPanelsOrigin() {
        var m = NotchStateMachine()
        m.open(origin: .hotkey)
        m.dragEntered()
        XCTAssertEqual(m.origin, .hotkey)
        m.dragLeft(hasItems: false)
        XCTAssertEqual(m.state, .expanded)
    }

    func testDragOpenedPanelClosesWhenTheDragLeavesEmpty() {
        var m = NotchStateMachine()
        m.dragEntered()
        m.dragLeft(hasItems: false)
        XCTAssertEqual(m.state, .collapsed)
    }

    func testDragOpenedPanelStaysWhenTheTrayHasItems() {
        var m = NotchStateMachine()
        m.dragEntered()
        m.dragLeft(hasItems: true)
        XCTAssertEqual(m.state, .expanded)
    }

    func testMouseExitDoesNotCloseADragOpenedPanel() {
        var m = NotchStateMachine()
        m.dragEntered()
        m.mouseExited()
        XCTAssertEqual(m.state, .expanded)
    }

    // MARK: - Tray row height

    func testTrayRowHeightIsAddedOnlyWhenShown() {
        let without = BentoLayout.height(stripHeight: 32)
        let with = BentoLayout.height(stripHeight: 32, trayRow: true)
        XCTAssertEqual(with - without, BentoLayout.gap + BentoLayout.trayRowHeight)
        XCTAssertEqual(BentoLayout.size(smallTiles: 1, stripHeight: 32).height, without)
    }

    func testPanelFrameGrowsDownwardWithTheTrayRow() {
        let m = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
            safeAreaTop: 32, auxLeftWidth: 656, auxRightWidth: 656)
        let plain = NotchGeometry.windowFrame(for: .expanded, metrics: m)
        let withTray = NotchGeometry.windowFrame(for: .expanded, metrics: m, trayRow: true)
        XCTAssertEqual(withTray.maxY, plain.maxY)
        XCTAssertEqual(withTray.height - plain.height, BentoLayout.gap + BentoLayout.trayRowHeight)
        // Other states ignore the flag.
        XCTAssertEqual(
            NotchGeometry.windowFrame(for: .collapsed, metrics: m, trayRow: true),
            NotchGeometry.windowFrame(for: .collapsed, metrics: m))
    }

    // MARK: - Actions

    func testImageItemsOfferConversions() {
        let image = TrayItem(path: "/tmp/a.png")
        let text = TrayItem(path: "/tmp/a.txt")
        XCTAssertTrue(TrayAction.available(for: image).contains(.png))
        XCTAssertFalse(TrayAction.available(for: text).contains(.png))
        XCTAssertTrue(TrayAction.available(for: TrayItem(path: "/tmp/d", kind: .folder)).contains(.pinFolder))
    }
}
