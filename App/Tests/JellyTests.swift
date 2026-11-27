import SwiftUI
import XCTest
@testable import Ufuq

/// Logic only: the spring table, the resting shape, the clamps, the neck and Reduce Motion.
final class JellyTests: XCTestCase {
    func testSpringTableMatchesSpec() {
        XCTAssertEqual(Jelly.touchSpring, Jelly.Spring(response: 0.28, damping: 0.55))
        XCTAssertEqual(Jelly.morphSpring, Jelly.Spring(response: 0.42, damping: 0.62))
        XCTAssertEqual(Jelly.openSpring, Jelly.Spring(response: 0.50, damping: 0.68))
        XCTAssertEqual(Jelly.closeSpring, Jelly.Spring(response: 0.36, damping: 0.80))
        XCTAssertEqual(Jelly.budSpring, Jelly.Spring(response: 0.45, damping: 0.50))
        XCTAssertEqual(Jelly.contentInDuration, 0.16)
        XCTAssertEqual(Jelly.contentInDelay, 0.08)
        XCTAssertEqual(Jelly.contentOutDuration, 0.10)
        XCTAssertEqual(Jelly.heightLag, 0.04)
        XCTAssertEqual(Jelly.overshootLimit(target: 100), 108)
        XCTAssertEqual(Jelly.overshootLimit(target: 400), 410)
    }

    func testSettleTimeCoversTheSpring() {
        for spring in [Jelly.touchSpring, Jelly.morphSpring, Jelly.openSpring, Jelly.closeSpring, Jelly.budSpring] {
            XCTAssertGreaterThanOrEqual(spring.settleTime, spring.response)
            XCTAssertLessThan(spring.settleTime, 2)
        }
        // Lower damping takes longer to settle.
        XCTAssertGreaterThan(Jelly.budSpring.settleTime, Jelly.closeSpring.settleTime)
    }

    func testRestingShapeMatchesNotchShape() {
        let cases: [(CGSize, CGFloat)] = [
            (CGSize(width: 368, height: 32), Tokens.Radius.collapsed),
            (CGSize(width: 352, height: 92), Tokens.Radius.peek),
            (CGSize(width: 520, height: 320), Tokens.Radius.expanded),
        ]
        for (size, radius) in cases {
            let rect = CGRect(origin: .zero, size: size)
            let jelly = JellyShape(width: size.width, height: size.height, bottomRadius: radius).path(in: rect)
            let plain = UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: radius,
                bottomTrailingRadius: radius, topTrailingRadius: 0).path(in: rect)
            let a = jelly.boundingRect
            let b = plain.boundingRect
            XCTAssertEqual(a.minX, b.minX, accuracy: 0.5)
            XCTAssertEqual(a.minY, b.minY, accuracy: 0.5)
            XCTAssertEqual(a.width, b.width, accuracy: 0.5)
            XCTAssertEqual(a.height, b.height, accuracy: 0.5)
            // Same corners: every sampled point is inside both paths or outside both.
            var x: CGFloat = 0.37
            while x < size.width {
                var y: CGFloat = 0.41
                while y < size.height {
                    let point = CGPoint(x: x, y: y)
                    XCTAssertEqual(jelly.contains(point), plain.contains(point), "\(point) in \(size)")
                    y += 3
                }
                x += 3
            }
        }
    }

    func testTopEdgeNeverMoves() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 40)
        let shape = JellyShape(width: 300, height: 40, bottomRadius: 14, lean: 6, skew: 4, bulge: 5)
        XCTAssertEqual(shape.path(in: rect).boundingRect.minY, 0, accuracy: 0.01)
        XCTAssertTrue(shape.path(in: rect).contains(CGPoint(x: 150, y: 0.5)))
        XCTAssertTrue(shape.path(in: rect).contains(CGPoint(x: 1, y: 0.5)))
        XCTAssertTrue(shape.path(in: rect).contains(CGPoint(x: 299, y: 0.5)))
    }

    func testLeanAndSkewAreClamped() {
        XCTAssertEqual(JellyShape.clampLean(20), 6)
        XCTAssertEqual(JellyShape.clampLean(-20), -6)
        XCTAssertEqual(JellyShape.clampLean(2), 2)
        XCTAssertEqual(JellyShape.clampSkew(10), 4)
        XCTAssertEqual(JellyShape.clampSkew(-10), -4)
        let shape = JellyShape(width: 100, height: 40, bottomRadius: 14, lean: 50, skew: 30)
        XCTAssertEqual(shape.lean, 6)
        XCTAssertEqual(shape.skew, 4)
    }

    func testAnimatableDataRoundTrips() {
        var shape = JellyShape(width: 10, height: 20, bottomRadius: 3, lean: 1, skew: 2, bulge: 4)
        let data = shape.animatableData
        shape.width = 0
        shape.bulge = 0
        shape.animatableData = data
        XCTAssertEqual(shape.width, 10)
        XCTAssertEqual(shape.height, 20)
        XCTAssertEqual(shape.bottomRadius, 3)
        XCTAssertEqual(shape.lean, 1)
        XCTAssertEqual(shape.skew, 2)
        XCTAssertEqual(shape.bulge, 4)
    }

    func testNeckLengthMapsFromDistance() {
        XCTAssertEqual(Jelly.neckLength(distance: 160), 0, accuracy: 0.001)
        XCTAssertEqual(Jelly.neckLength(distance: 400), 0, accuracy: 0.001)
        XCTAssertEqual(Jelly.neckLength(distance: 60), Jelly.neckMaxLength, accuracy: 0.001)
        XCTAssertEqual(Jelly.neckLength(distance: 10), Jelly.neckMaxLength, accuracy: 0.001)
        XCTAssertEqual(Jelly.neckLength(distance: 110), Jelly.neckMaxLength / 2, accuracy: 0.001)
    }

    func testReduceMotionReturnsCrossFade() {
        XCTAssertEqual(Jelly.resolved(Jelly.open, reduceMotion: true), Jelly.crossFade)
        XCTAssertEqual(Jelly.resolved(Jelly.bud, reduceMotion: true), Jelly.crossFade)
        XCTAssertEqual(Jelly.resolved(Jelly.open, reduceMotion: false), Jelly.open)
        let still = Jelly.touchShape(
            pointer: JellyPointer(hovering: true, x: 100, pressed: true), width: 300, reduceMotion: true)
        XCTAssertEqual(still.scaleX, 1)
        XCTAssertEqual(still.scaleY, 1)
        XCTAssertEqual(still.lean, 0)
    }

    func testHoverAndPressShapes() {
        let hover = Jelly.touchShape(
            pointer: JellyPointer(hovering: true, x: 500, pressed: false), width: 300, reduceMotion: false)
        XCTAssertEqual(hover.scaleX, 1.03, accuracy: 0.0001)
        XCTAssertEqual(hover.lean, 6, accuracy: 0.0001)
        let press = Jelly.touchShape(
            pointer: JellyPointer(hovering: true, x: 0, pressed: true), width: 300, reduceMotion: false)
        XCTAssertEqual(press.scaleX, 0.96, accuracy: 0.0001)
        XCTAssertEqual(press.scaleY, 0.92, accuracy: 0.0001)
    }

    func testPaddedWindowFrameKeepsTopEdgeAndCentre() {
        let metrics = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
            safeAreaTop: 32, auxLeftWidth: 660, auxRightWidth: 660)
        let plain = NotchGeometry.windowFrame(for: .collapsed, metrics: metrics)
        let padded = NotchGeometry.paddedWindowFrame(for: .collapsed, metrics: metrics)
        XCTAssertEqual(padded.maxY, plain.maxY)
        XCTAssertEqual(padded.midX, plain.midX, accuracy: 0.001)
        XCTAssertGreaterThan(padded.width, plain.width)
        XCTAssertGreaterThan(NotchGeometry.paddedWindowFrame(for: .collapsed, metrics: metrics, neck: true).height, padded.height)
    }
}
