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

    /// Design canvas option A with every tile this build has: Prayer, AI (four accounts), Battery.
    func testExpandedBentoAllTiles() throws {
        try renderBento(name: "expanded-bento-all", content: BentoContent(
            snapshot: jakarta, now: fixedNow, ai: Self.aiRows,
            battery: BatteryStatus(percent: 82, isCharging: true, isPluggedIn: true)))
    }

    /// What ships until the usage readers are wired: AI empty state, no battery (desktop Mac).
    func testExpandedBentoPrayerOnly() throws {
        try renderBento(name: "expanded-bento-empty-ai", content: BentoContent(snapshot: jakarta, now: fixedNow))
    }

    func testExpandedBentoUnavailable() throws {
        try renderBento(name: "expanded-bento-unavailable", content: BentoContent(
            snapshot: nil, now: fixedNow,
            battery: BatteryStatus(percent: 8, isCharging: false, isPluggedIn: false)))
    }

    private var jakarta: PrayerSnapshot? { PrayerSnapshots.at(fixedNow, location: AppSettings.defaultLocation) }

    private static let aiRows = [
        AIUsageRow(id: "c1", provider: .claude, name: "Claude · Work", fraction: 0.62, detail: "Week 41% · resets 2 h 10 min"),
        AIUsageRow(id: "c2", provider: .claude, name: "Claude · Personal", fraction: 0.18, detail: "In use by Claude Code"),
        AIUsageRow(id: "cx", provider: .codex, name: "Codex", fraction: 0.84, detail: "High · limit in ~38 min"),
        AIUsageRow(id: "ag", provider: .antigravity, name: "Antigravity", fraction: 0.23, detail: "Pro models", isBetaSource: true),
    ]

    /// Solid surface: ImageRenderer cannot draw glass or materials, and the layout is what is checked.
    private func renderBento(name: String, content: BentoContent) throws {
        let size = BentoLayout.size(smallTiles: content.smallTiles.count, stripHeight: 32)
        let view = ExpandedView(
            content: content, layout: wings, centerGap: 188, stripHeight: 32,
            focusedTile: .constant(.prayer), focusToken: 0, surface: .solid, focusable: false)
        try render(view, size: size, name: name, backdrop: Color(hex: 0x33445A))
    }

    private func render<V: View>(_ view: V, size: CGSize, name: String, backdrop: Color = .black) throws {
        let content = view
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(backdrop)
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
