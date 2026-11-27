import XCTest
@testable import UfuqCore

final class Phase7bTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_700_000)

    func testHUDReadingClampingIconsAndAccessibility() {
        let high = HUDReading(kind: .volume, level: 1.4, isMuted: false, timestamp: t0)
        XCTAssertEqual(high.level, 1.0)
        XCTAssertEqual(high.percent, 100)
        XCTAssertEqual(high.iconName, "speaker.wave.3.fill")
        XCTAssertEqual(high.accessibilityLabel, "Volume 100 percent")

        let muted = HUDReading(kind: .volume, level: 0.5, isMuted: true, timestamp: t0)
        XCTAssertEqual(muted.percent, 0)
        XCTAssertEqual(muted.iconName, "speaker.slash.fill")
        XCTAssertEqual(muted.accessibilityLabel, "Volume muted")

        let bright = HUDReading(kind: .brightness, level: 0.25, timestamp: t0)
        XCTAssertEqual(bright.iconName, "sun.min.fill")
        XCTAssertEqual(bright.accessibilityLabel, "Brightness 25 percent")

        let kbd = HUDReading(kind: .keyboardBacklight, level: 0.8, timestamp: t0)
        XCTAssertEqual(kbd.iconName, "light.max")
        XCTAssertEqual(kbd.accessibilityLabel, "Keyboard backlight 80 percent")
    }

    func testHUDStateTrackerBaselineDeltaAndExpiry() {
        var tracker = HUDStateTracker(displayDuration: 1.6)

        // Initial baseline never flashes HUD.
        XCTAssertNil(tracker.ingest(HUDReading(kind: .volume, level: 0.50, timestamp: t0)))
        XCTAssertNil(tracker.active)

        // Sub-threshold jitter ignored.
        XCTAssertNil(tracker.ingest(HUDReading(kind: .volume, level: 0.502, timestamp: t0.addingTimeInterval(0.2))))
        XCTAssertNil(tracker.active)

        // Real change triggers active HUD.
        let active = tracker.ingest(HUDReading(kind: .volume, level: 0.56, timestamp: t0.addingTimeInterval(0.4)))
        XCTAssertEqual(active?.percent, 56)
        XCTAssertEqual(tracker.active?.percent, 56)

        // Not expired before 1.6s.
        XCTAssertFalse(tracker.expire(at: t0.addingTimeInterval(1.9)))
        XCTAssertNotNil(tracker.active)

        // Expires at >= 1.6s.
        XCTAssertTrue(tracker.expire(at: t0.addingTimeInterval(2.0)))
        XCTAssertNil(tracker.active)
    }

    func testClipboardHistoryRecordDedupePinTrimAndIgnore() {
        XCTAssertTrue(ClipboardHistory.shouldIgnore(pasteboardTypes: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertTrue(ClipboardHistory.shouldIgnore(pasteboardTypes: ["com.agilebits.onepassword"]))
        XCTAssertFalse(ClipboardHistory.shouldIgnore(pasteboardTypes: ["public.utf8-plain-text"]))

        var history = ClipboardHistory(maxItems: 3)
        XCTAssertFalse(history.record(text: "   \n\t  ", at: t0))

        XCTAssertTrue(history.record(text: "first", sourceApp: "Notes", at: t0))
        XCTAssertTrue(history.record(text: "second", sourceApp: "Safari", at: t0.addingTimeInterval(1)))
        XCTAssertTrue(history.record(text: "third", sourceApp: "Terminal", at: t0.addingTimeInterval(2)))

        // Pin "first" so it stays at the top and is never evicted.
        let firstID = history.items.first(where: { $0.text == "first" })!.id
        history.togglePin(id: firstID)
        XCTAssertEqual(history.items.first?.text, "first")
        XCTAssertTrue(history.items.first?.isPinned == true)

        // Adding "fourth" trims oldest unpinned ("second"), keeping pinned "first".
        XCTAssertTrue(history.record(text: "fourth", sourceApp: "Xcode", at: t0.addingTimeInterval(3)))
        XCTAssertEqual(history.items.map(\.text), ["first", "fourth", "third"])

        // Re-copying "first" preserves pin and updates timestamp.
        XCTAssertTrue(history.record(text: "first", sourceApp: "Notes", at: t0.addingTimeInterval(4)))
        XCTAssertTrue(history.items.first?.isPinned == true)

        // Filtering.
        XCTAssertEqual(history.filtered(query: "xcode").map(\.text), ["fourth"])

        // Clear unpinned leaves only pinned.
        history.clearUnpinned()
        XCTAssertEqual(history.items.map(\.text), ["first"])
    }
}
