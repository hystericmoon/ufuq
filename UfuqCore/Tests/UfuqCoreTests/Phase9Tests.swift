import XCTest
@testable import UfuqCore

private final class TestBox<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

final class Phase9Tests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_764_240_000)

    func testTimerCountdownPauseResumeAndCompletion() async throws {
        let now = TestBox(baseDate)
        let timer = TimerModule(clock: { now.value })
        let stream = timer.peekEvents()
        var iterator = stream.makeAsyncIterator()

        timer.startCountdown(duration: 90, at: now.value)
        XCTAssertEqual(timer.snapshot(at: now.value)?.formattedRemaining, "01:30")
        XCTAssertEqual(try timer.collapsedActivity(at: now.value)?.text, "01:30")

        now.value = now.value.addingTimeInterval(30)
        timer.pause(at: now.value)
        XCTAssertEqual(timer.snapshot(at: now.value)?.status, .paused)
        XCTAssertEqual(try timer.collapsedActivity(at: now.value)?.text, "Paused 01:00")

        now.value = now.value.addingTimeInterval(15)
        timer.resume(at: now.value)
        now.value = now.value.addingTimeInterval(55)
        XCTAssertEqual(try timer.collapsedActivity(at: now.value)?.isAlert, true)

        now.value = now.value.addingTimeInterval(5)
        timer.tick(at: now.value)
        XCTAssertEqual(timer.snapshot(at: now.value)?.status, .finished)
        XCTAssertEqual(try timer.collapsedActivity(at: now.value)?.text, "Timer done")

        let peek = await iterator.next()
        XCTAssertEqual(peek?.title, "Timer done")
    }

    func testPomodoroFourCyclesTriggersLongBreak() {
        let now = TestBox(baseDate)
        let timer = TimerModule(
            focusDuration: 1500,
            shortBreakDuration: 300,
            longBreakDuration: 900,
            cyclesBeforeLongBreak: 4,
            clock: { now.value }
        )
        timer.startPomodoroFocus(at: now.value)

        for cycle in 1...3 {
            timer.advancePomodoro(at: now.value)
            XCTAssertEqual(timer.snapshot(at: now.value)?.mode, .pomodoroShortBreak)
            XCTAssertEqual(timer.snapshot(at: now.value)?.cycleCount, cycle)
            now.value = now.value.addingTimeInterval(10)
            timer.advancePomodoro(at: now.value)
            XCTAssertEqual(timer.snapshot(at: now.value)?.mode, .pomodoroFocus)
        }

        timer.advancePomodoro(at: now.value)
        XCTAssertEqual(timer.snapshot(at: now.value)?.mode, .pomodoroLongBreak)
        XCTAssertEqual(timer.snapshot(at: now.value)?.cycleCount, 4)
        XCTAssertEqual(timer.snapshot(at: now.value)?.formattedRemaining, "15:00")
    }

    func testSystemStatsFormattingAndNetworkRateTracker() {
        let stats = SystemStatsSnapshot(
            cpuPercent: 42.6,
            memoryUsedBytes: 12 * 1024 * 1024 * 1024,
            memoryTotalBytes: 16 * 1024 * 1024 * 1024,
            downloadBytesPerSec: 1_572_864,
            uploadBytesPerSec: 512 * 1024
        )
        XCTAssertEqual(stats.formattedCPU, "43%")
        XCTAssertEqual(stats.memoryPercent, 75)
        XCTAssertEqual(stats.formattedMemory, "12.0/16G")
        XCTAssertEqual(stats.formattedDownRate, "1.5 MB/s")
        XCTAssertEqual(stats.formattedUpRate, "512 KB/s")

        var tracker = NetworkRateTracker()
        let first = tracker.sample(rxBytes: 1000, txBytes: 500, at: baseDate)
        XCTAssertEqual(first.download, 0)
        XCTAssertEqual(first.upload, 0)

        let second = tracker.sample(rxBytes: 3048, txBytes: 1524, at: baseDate.addingTimeInterval(2))
        XCTAssertEqual(second.download, 1024, accuracy: 0.1)
        XCTAssertEqual(second.upload, 512, accuracy: 0.1)

        let wrapped = tracker.sample(rxBytes: 100, txBytes: 50, at: baseDate.addingTimeInterval(4))
        XCTAssertEqual(wrapped.download, 0)
        XCTAssertEqual(wrapped.upload, 0)
    }

    func testDownloadsModuleBaselinePartialAndCompletionPeek() async throws {
        let files = TestBox([
            ActiveDownload(path: "/tmp/old.zip", fileName: "old.zip", byteCount: 1000, modifiedAt: baseDate, isInProgress: false)
        ])
        let module = DownloadsModule(scanner: { files.value })
        let stream = module.peekEvents()
        var iterator = stream.makeAsyncIterator()

        try await module.refresh()
        XCTAssertNil(try module.collapsedActivity(at: baseDate))

        files.value.append(ActiveDownload(
            path: "/tmp/Ufuq.dmg.download",
            fileName: "Ufuq.dmg.download",
            byteCount: 24 * 1024 * 1024,
            modifiedAt: baseDate,
            isInProgress: true
        ))
        try await module.refresh()
        XCTAssertEqual(try module.collapsedActivity(at: baseDate)?.text, "↓ 24 MB")

        files.value = [
            ActiveDownload(path: "/tmp/old.zip", fileName: "old.zip", byteCount: 1000, modifiedAt: baseDate, isInProgress: false),
            ActiveDownload(path: "/tmp/Ufuq.dmg", fileName: "Ufuq.dmg", byteCount: 24 * 1024 * 1024, modifiedAt: baseDate, isInProgress: false)
        ]
        try await module.refresh()
        XCTAssertNil(try module.collapsedActivity(at: baseDate))
        let peek = await iterator.next()
        XCTAssertEqual(peek?.title, "Download ready")
        XCTAssertEqual(peek?.message, "Ufuq.dmg")
    }

    func testAudioAccessoryModuleBaselineAndConnectPeek() async throws {
        let now = TestBox(baseDate)
        let devices = TestBox([AudioAccessory]())
        let module = AudioAccessoryModule(provider: { devices.value }, clock: { now.value })
        let stream = module.peekEvents()
        var iterator = stream.makeAsyncIterator()

        try await module.refresh()
        XCTAssertNil(try module.collapsedActivity(at: now.value))

        devices.value = [
            AudioAccessory(id: "ap-1", name: "AirPods Pro", kind: .airPods, leftBatteryPercent: 75, rightBatteryPercent: 90)
        ]
        try await module.refresh()
        XCTAssertEqual(devices.value[0].displayBattery, "L 75% · R 90%")
        XCTAssertEqual(try module.collapsedActivity(at: now.value)?.text, "AirPods L 75% · R 90%")

        let peek = await iterator.next()
        XCTAssertEqual(peek?.title, "AirPods Pro connected")
        XCTAssertEqual(peek?.message, "Battery L 75% · R 90%")

        now.value = now.value.addingTimeInterval(AudioAccessoryModule.connectionWingWindow + 1)
        XCTAssertNil(try module.collapsedActivity(at: now.value))
    }

    func testAppearanceAndTrayAudioHelpers() {
        XCTAssertEqual(UfuqAccent.emerald.hex, 0x4FD1A5)
        XCTAssertEqual(UfuqShapeStyle.standard.expandedRadius, 28)
        XCTAssertEqual(UfuqShapeStyle.pill.expandedRadius, 34)
        XCTAssertEqual(UfuqShapeStyle.crisp.collapsedRadius, 8)
        XCTAssertTrue(TrayActions.isAudioExtension("m4a"))
        XCTAssertFalse(TrayActions.isAudioExtension("png"))
        XCTAssertEqual(TrayActions.formatTranscriptStatus(wordCount: 0), "No speech detected")
        XCTAssertEqual(TrayActions.formatTranscriptStatus(wordCount: 1), "Copied 1 word")
        XCTAssertEqual(TrayActions.formatTranscriptStatus(wordCount: 12), "Copied 12 words")
    }
}
