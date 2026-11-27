import AppKit
import SwiftUI
import XCTest
import UfuqCore
@testable import Ufuq

/// Renders the views with fixed data. PNGs go to `$SNAPSHOT_DIR` when it is set (CI uploads them).
@MainActor
final class SnapshotTests: XCTestCase {
    /// Fixed instant: 2026-11-26 08:00:00 UTC = 15:00 in Jakarta (before Ashar).
    private let fixedNow = Date(timeIntervalSince1970: 1_795_680_000)

    private let wings = WingLayout(
        left: LiveActivity(
            id: "prayer.next", moduleID: "prayer", source: .prayer,
            text: "Ashar 15:12", accessibilityLabel: "Ashar in 12 minutes"),
        right: LiveActivity(
            id: "ai.worst", moduleID: "ai", source: .aiUsage,
            text: "82%", accessibilityLabel: "Claude Work, 82 percent of session",
            usageFraction: 0.82),
        rotating: LiveActivity(
            id: "agent.1", moduleID: "agent", source: .agent,
            text: "Task", accessibilityLabel: "Agent task running"))

    func testCollapsedNotch() throws {
        try render(CollapsedView(layout: wings, centerGap: 188), size: CGSize(width: 368, height: 32), name: "collapsed-notch")
    }

    func testCollapsedPill() throws {
        try render(CollapsedView(layout: wings, centerGap: 16), size: CGSize(width: 300, height: 32), name: "collapsed-pill")
    }

    func testPeekNormal() throws {
        let event = PeekEvent(id: "p", moduleID: "prayer", title: "Ashar", message: "in 10 minutes, at 15:12")
        try render(PeekView(event: event, topInset: 32), size: CGSize(width: 352, height: 92), name: "peek-normal")
    }

    func testPeekCritical() throws {
        let event = PeekEvent(
            id: "c", moduleID: "prayer", title: "Ashar", message: "Time for Ashar, 15:12", priority: .critical)
        try render(PeekView(event: event, topInset: 32), size: CGSize(width: 352, height: 92), name: "peek-critical")
    }

    func testExpandedPrayer() throws {
        let snapshot = PrayerSnapshots.at(fixedNow, location: AppSettings.defaultLocation)
        let view = ExpandedView(
            snapshot: snapshot, now: fixedNow, topInset: 32,
            selectedTab: .constant(.prayer), focusToken: 0)
        try render(view, size: CGSize(width: 640, height: 360), name: "expanded-prayer")
    }

    func testExpandedAIEmptyState() throws {
        let view = ExpandedView(
            snapshot: nil, now: fixedNow, topInset: 32,
            selectedTab: .constant(.ai), focusToken: 0)
        try render(view, size: CGSize(width: 640, height: 360), name: "expanded-ai")
    }

    private func render<V: View>(_ view: V, size: CGSize, name: String) throws {
        let content = view
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage, "\(name): no image")
        XCTAssertGreaterThan(image.size.width, 0)

        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let tiff = try XCTUnwrap(image.tiffRepresentation, "\(name): no tiff")
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff), "\(name): no bitmap")
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]), "\(name): no png")
        try png.write(to: url.appendingPathComponent("\(name).png"))
    }
}
