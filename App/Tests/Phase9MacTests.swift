import XCTest
@testable import Ufuq
import UfuqCore

@MainActor
final class Phase9MacTests: XCTestCase {
    func testStayAwakeToggleAndStop() {
        let controller = StayAwakeController.shared
        controller.stop()
        XCTAssertFalse(controller.isActive)

        controller.toggle()
        XCTAssertTrue(controller.isActive)

        controller.stop()
        XCTAssertFalse(controller.isActive)
    }

    func testSystemStatsReaderBounds() {
        let stats = SystemStatsReader.shared.read()
        XCTAssertGreaterThanOrEqual(stats.cpuPercent, 0)
        XCTAssertLessThanOrEqual(stats.cpuPercent, 100)
        XCTAssertGreaterThan(stats.memoryTotalBytes, 0)
        XCTAssertLessThanOrEqual(stats.memoryUsedBytes, stats.memoryTotalBytes)
    }

    func testDownloadsMonitorDetectsPartialAndCompletedFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ufuq-dl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let partial = tempDir.appendingPathComponent("Archive.zip.download")
        let done = tempDir.appendingPathComponent("Notes.pdf")
        try Data("part".utf8).write(to: partial)
        try Data("done".utf8).write(to: done)

        let scanned = DownloadsMonitor.scan(directory: tempDir)
        XCTAssertEqual(scanned.count, 2)
        let active = scanned.first { $0.isInProgress }
        XCTAssertEqual(active?.fileName, "Archive.zip")
        let completed = scanned.first { !$0.isInProgress }
        XCTAssertEqual(completed?.fileName, "Notes.pdf")
    }

    func testTrayActionAudioTranscribe() {
        let audio = TrayItem(path: "/tmp/voice-note.m4a", name: "voice-note.m4a", size: 2048, kind: .file)
        XCTAssertTrue(TrayAction.isAudio(audio))
        XCTAssertTrue(TrayAction.available(for: audio).contains(.transcribe))
        XCTAssertEqual(TrayAction.forKey("t"), .transcribe)
    }

    func testBentoTileOrderIncludesPhase9UtilitiesWhenLive() {
        let now = Date()
        let content = BentoContent(
            now: now,
            timer: TimerSnapshot(mode: .pomodoroFocus, status: .running, totalDuration: 1500, remaining: 1200),
            systemStats: SystemStatsSnapshot(cpuPercent: 18, memoryUsedBytes: 8_000_000_000, memoryTotalBytes: 16_000_000_000),
            transcribeActive: true
        )
        XCTAssertEqual(content.smallTiles, [.timer, .transcribe, .system])
    }

    func testShapeStyleRadiiApplyToNotchRootView() {
        let prev = UserDefaults.standard.string(forKey: AppSettings.shapeStyleKey)
        defer {
            if let prev {
                UserDefaults.standard.set(prev, forKey: AppSettings.shapeStyleKey)
            } else {
                UserDefaults.standard.removeObject(forKey: AppSettings.shapeStyleKey)
            }
        }

        UserDefaults.standard.set(UfuqShapeStyle.crisp.rawValue, forKey: AppSettings.shapeStyleKey)
        XCTAssertEqual(NotchRootView.radius(for: .expanded), 18)

        UserDefaults.standard.set(UfuqShapeStyle.pill.rawValue, forKey: AppSettings.shapeStyleKey)
        XCTAssertEqual(NotchRootView.radius(for: .expanded), 34)

        UserDefaults.standard.set(UfuqShapeStyle.standard.rawValue, forKey: AppSettings.shapeStyleKey)
        XCTAssertEqual(NotchRootView.radius(for: .expanded), 28)
    }
}
