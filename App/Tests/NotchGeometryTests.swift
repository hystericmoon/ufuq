import XCTest
@testable import Ufuq

final class NotchGeometryTests: XCTestCase {
    /// 14-inch MacBook Pro style: 188 pt camera housing, 32 pt tall.
    private let notchScreen = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
        safeAreaTop: 32, auxLeftWidth: 662, auxRightWidth: 662)

    private let plainScreen = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
        safeAreaTop: 0, auxLeftWidth: 0, auxRightWidth: 0)

    func testNotchRect() {
        XCTAssertEqual(NotchGeometry.notchRect(notchScreen), CGRect(x: 662, y: 950, width: 188, height: 32))
        XCTAssertNil(NotchGeometry.notchRect(plainScreen))
    }

    func testNotchCollapsedFrameIsCenteredAndFlushWithTop() {
        let f = NotchGeometry.windowFrame(for: .collapsed, metrics: notchScreen)
        // 188 + 2 * 90 wing width = 368.
        XCTAssertEqual(f, CGRect(x: 572, y: 950, width: 368, height: 32))
        XCTAssertEqual(f.midX, 756)
        XCTAssertEqual(f.maxY, notchScreen.frame.maxY)
    }

    func testNotchPeekAndExpandedFrames() {
        XCTAssertEqual(
            NotchGeometry.windowFrame(for: .peek, metrics: notchScreen),
            CGRect(x: 580, y: 890, width: 352, height: 92))
        XCTAssertEqual(
            NotchGeometry.windowFrame(for: .expanded, metrics: notchScreen),
            CGRect(x: 436, y: 622, width: 640, height: 360))
    }

    func testPlainScreenIslandIsFlushWithTopOverMenuBar() {
        // Menu bar = 1080 - 1055 = 25 pt.
        let collapsed = NotchGeometry.windowFrame(for: .collapsed, metrics: plainScreen)
        XCTAssertEqual(collapsed, CGRect(x: 810, y: 1055, width: 300, height: 25))
        XCTAssertEqual(collapsed.maxY, plainScreen.frame.maxY)
        XCTAssertEqual(collapsed.minY, plainScreen.visibleFrame.maxY)

        let peek = NotchGeometry.windowFrame(for: .peek, metrics: plainScreen)
        XCTAssertEqual(peek, CGRect(x: 784, y: 988, width: 352, height: 92))

        let expanded = NotchGeometry.windowFrame(for: .expanded, metrics: plainScreen)
        XCTAssertEqual(expanded, CGRect(x: 640, y: 720, width: 640, height: 360))
    }

    func testPlainScreenCollapsedHeightIsClampedWhenMenuBarIsHiddenOrShort() {
        let hidden = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            safeAreaTop: 0, auxLeftWidth: 0, auxRightWidth: 0)
        XCTAssertEqual(
            NotchGeometry.windowFrame(for: .collapsed, metrics: hidden),
            CGRect(x: 810, y: 1056, width: 300, height: 24))

        let short = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1060),
            safeAreaTop: 0, auxLeftWidth: 0, auxRightWidth: 0)
        XCTAssertEqual(NotchGeometry.size(for: .collapsed, metrics: short).height, 24)
    }

    func testPillOnSecondaryDisplayWithOffsetOrigin() {
        let m = ScreenMetrics(
            frame: CGRect(x: 1512, y: 100, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1512, y: 100, width: 1920, height: 1055),
            safeAreaTop: 0, auxLeftWidth: 0, auxRightWidth: 0)
        let f = NotchGeometry.windowFrame(for: .collapsed, metrics: m)
        XCTAssertEqual(f.midX, 1512 + 960)
        XCTAssertEqual(f.maxY, 100 + 1080)
        XCTAssertEqual(f.height, 25)
    }

    func testNotchWithoutAuxiliaryAreasFallsBack() {
        let m = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
            safeAreaTop: 32, auxLeftWidth: 0, auxRightWidth: 0)
        XCTAssertEqual(NotchGeometry.notchWidth(m), NotchGeometry.fallbackNotchWidth)
        XCTAssertEqual(NotchGeometry.windowFrame(for: .collapsed, metrics: m).midX, 756)
    }

    func testCollapsedNeverSmallerThanSpecSize() {
        XCTAssertGreaterThanOrEqual(NotchGeometry.size(for: .collapsed, metrics: notchScreen).width, 300)
        XCTAssertEqual(NotchGeometry.size(for: .collapsed, metrics: plainScreen), CGSize(width: 300, height: 25))
    }
}
