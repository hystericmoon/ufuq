import XCTest
import UfuqCore
@testable import Ufuq

final class NowPlayingLayoutTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func track(playing: Bool) -> NowPlaying {
        NowPlaying(title: "Bertaut", artist: "Nadin Amizah", isPlaying: playing, source: .mediaRemoteAdapter)
    }

    func testNothingPlayingHasNoTile() {
        let content = BentoContent(now: now)
        XCTAssertFalse(content.smallTiles.contains(.nowPlaying))
    }

    func testPlayingShowsTile() {
        let content = BentoContent(now: now, nowPlaying: track(playing: true))
        XCTAssertEqual(content.smallTiles, [.nowPlaying])
    }

    func testPausedUnderAMinuteShowsTileAndOverHidesIt() {
        let recent = BentoContent(
            now: now, nowPlaying: track(playing: false), nowPlayingPausedSince: now.addingTimeInterval(-59))
        XCTAssertTrue(recent.smallTiles.contains(.nowPlaying))
        let stale = BentoContent(
            now: now, nowPlaying: track(playing: false), nowPlayingPausedSince: now.addingTimeInterval(-61))
        XCTAssertFalse(stale.smallTiles.contains(.nowPlaying))
    }

    func testBatteryAndNowPlayingShareOneColumn() {
        let content = BentoContent(
            now: now, battery: BatteryStatus(percent: 80, isCharging: false, isPluggedIn: false),
            nowPlaying: track(playing: true))
        XCTAssertEqual(content.smallTiles, [.battery, .nowPlaying])
        XCTAssertEqual(BentoLayout.width(smallTiles: content.smallTiles.count), 648)
    }

    func testSeekTargetIsClamped() {
        var t = track(playing: false)
        t.elapsed = 5
        t.duration = 100
        XCTAssertEqual(NowPlayingFormat.seekTarget(t, by: -10, at: now), 0)
        t.elapsed = 95
        XCTAssertEqual(NowPlayingFormat.seekTarget(t, by: 10, at: now), 100)
    }

    func testPlayPauseLabel() {
        XCTAssertEqual(NowPlayingFormat.playPauseLabel(track(playing: true)), "Pause, Bertaut by Nadin Amizah")
        XCTAssertEqual(NowPlayingFormat.playPauseLabel(track(playing: false)), "Play, Bertaut by Nadin Amizah")
    }

    func testFocusedTileKeyCommands() {
        var withPosition = track(playing: true)
        withPosition.elapsed = 30
        withPosition.duration = 120
        XCTAssertEqual(NowPlayingFormat.command(for: .space, track: withPosition, at: now), .playPause)
        XCTAssertEqual(NowPlayingFormat.command(for: .left, track: withPosition, at: now), .seek(to: 20))
        XCTAssertEqual(NowPlayingFormat.command(for: .right, track: withPosition, at: now), .seek(to: 40))

        let withoutPosition = track(playing: false)
        XCTAssertEqual(NowPlayingFormat.command(for: .space, track: withoutPosition, at: now), .playPause)
        XCTAssertNil(NowPlayingFormat.command(for: .left, track: withoutPosition, at: now))
        XCTAssertNil(NowPlayingFormat.command(for: .right, track: withoutPosition, at: now))
    }
}
