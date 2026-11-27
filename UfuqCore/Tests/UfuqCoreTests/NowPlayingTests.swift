import XCTest
@testable import UfuqCore

final class MediaRemoteAdapterParserTests: XCTestCase {
    func testFullGetObject() throws {
        let json = #"{"title":"Song","artist":"Band","album":"LP","duration":200.5,"elapsedTime":10,"timestamp":1700000000.5,"playing":true,"playbackRate":1,"bundleIdentifier":"com.spotify.client","extra":{"x":1}}"#
        let r = MediaRemoteAdapterParser.parse(Data((json + "\n").utf8))
        let np = try XCTUnwrap(r.nowPlaying)
        XCTAssertEqual(np.title, "Song")
        XCTAssertEqual(np.artist, "Band")
        XCTAssertEqual(np.album, "LP")
        XCTAssertEqual(np.duration, 200.5)
        XCTAssertEqual(np.elapsed, 10)
        XCTAssertEqual(np.timestamp, Date(timeIntervalSince1970: 1700000000.5))
        XCTAssertTrue(np.isPlaying)
        XCTAssertEqual(np.bundleIdentifier, "com.spotify.client")
        XCTAssertEqual(np.source, .mediaRemoteAdapter)
        XCTAssertEqual(r.skipped, 0)
    }

    func testISOTimestampAndMicros() throws {
        let a = MediaRemoteAdapterParser.parse(Data(#"{"title":"T","playing":true,"timestamp":"2025-01-02T03:04:05Z"}"#.utf8 + [10]))
        XCTAssertEqual(a.nowPlaying?.timestamp, Date(timeIntervalSince1970: 1735787045))
        let b = MediaRemoteAdapterParser.parse(Data(#"{"title":"T","playing":true,"timestampEpochMicros":1700000000000000,"durationMicros":2000000}"#.utf8 + [10]))
        XCTAssertEqual(b.nowPlaying?.timestamp, Date(timeIntervalSince1970: 1700000000))
        XCTAssertEqual(b.nowPlaying?.duration, 2)
    }

    func testStreamEnvelopesAndDiffs() throws {
        let lines = """
        {"type":"data","diff":false,"payload":{"title":"A","artist":"X","playing":true,"elapsedTime":1}}
        {"type":"data","diff":true,"payload":{"title":"B","artist":null,"playing":false}}

        """
        let r = MediaRemoteAdapterParser.parse(Data(lines.utf8))
        let np = try XCTUnwrap(r.nowPlaying)
        XCTAssertEqual(np.title, "B")
        XCTAssertNil(np.artist)
        XCTAssertFalse(np.isPlaying)
        XCTAssertEqual(np.elapsed, 1)
    }

    func testMalformedLineSkippedAndCounted() {
        let lines = "not json\n{\"title\":\"A\",\"playing\":true}\n[1,2]\n"
        let r = MediaRemoteAdapterParser.parse(Data(lines.utf8))
        XCTAssertEqual(r.nowPlaying?.title, "A")
        XCTAssertEqual(r.skipped, 2)
    }

    func testEmptyPayloadIsNothingPlaying() {
        XCTAssertNil(MediaRemoteAdapterParser.parse(Data("{}\n".utf8)).nowPlaying)
        XCTAssertNil(MediaRemoteAdapterParser.parse(Data(#"{"type":"data","diff":false,"payload":{}}"#.utf8 + [10])).nowPlaying)
        XCTAssertNil(MediaRemoteAdapterParser.parse(Data()).nowPlaying)
    }

    func testArtworkBase64Decoded() throws {
        let bytes = Data([1, 2, 3, 4, 5])
        let json = #"{"title":"T","playing":true,"artworkData":"\#(bytes.base64EncodedString())","artworkMimeType":"image/png"}"#
        let np = try XCTUnwrap(MediaRemoteAdapterParser.parse(Data((json + "\n").utf8)).nowPlaying)
        XCTAssertEqual(np.artwork, bytes)
    }

    func testPositionExtrapolation() {
        let t0 = Date(timeIntervalSince1970: 1000)
        let np = NowPlaying(title: "T", duration: 100, elapsed: 10, timestamp: t0, isPlaying: true, playbackRate: 1, source: .mediaRemoteAdapter)
        XCTAssertEqual(np.position(at: t0.addingTimeInterval(5)), 15)
        XCTAssertEqual(np.position(at: t0.addingTimeInterval(500)), 100)
        var paused = np; paused.isPlaying = false
        XCTAssertEqual(paused.position(at: t0.addingTimeInterval(5)), 10)
    }
}

final class SpotifyAppleScriptParserTests: XCTestCase {
    private let d = SpotifyAppleScriptParser.delimiter

    func testMillisecondDuration() throws {
        let out = ["playing", "Song", "Band", "LP", "215000", "12.5", "https://i.scdn.co/a"].joined(separator: d)
        let np = try XCTUnwrap(SpotifyAppleScriptParser.parse(out))
        XCTAssertEqual(np.duration, 215)
        XCTAssertEqual(np.elapsed, 12.5)
        XCTAssertTrue(np.isPlaying)
        XCTAssertEqual(np.artworkURL, "https://i.scdn.co/a")
        XCTAssertEqual(np.source, .spotifyAppleScript)
    }

    func testSecondsDurationAndPaused() throws {
        let out = ["paused", "Song", "Band", "LP", "215", "3,5", "missing value"].joined(separator: d)
        let np = try XCTUnwrap(SpotifyAppleScriptParser.parse(out))
        XCTAssertEqual(np.duration, 215)
        XCTAssertEqual(np.elapsed, 3.5)
        XCTAssertFalse(np.isPlaying)
        XCTAssertNil(np.artworkURL)
    }

    func testStoppedNotRunningAndMissingArtworkField() {
        XCTAssertNil(SpotifyAppleScriptParser.parse("stopped"))
        XCTAssertNil(SpotifyAppleScriptParser.parse(""))
        let out = ["playing", "Song", "Band", "LP", "100", "1"].joined(separator: d)
        XCTAssertNotNil(SpotifyAppleScriptParser.parse(out))
        XCTAssertNil(SpotifyAppleScriptParser.parse(out)?.artworkURL)
    }
}

private final class StubSource: NowPlayingSource, @unchecked Sendable {
    let name: String
    var testResult: Bool
    var result: Result<NowPlaying?, Error>
    var commands: [NowPlayingCommand] = []
    init(_ name: String, test: Bool = true, result: Result<NowPlaying?, Error> = .success(nil)) {
        self.name = name; testResult = test; self.result = result
    }
    func selfTest() async -> Bool { testResult }
    func snapshot() async throws -> NowPlaying? { try result.get() }
    func send(_ command: NowPlayingCommand) async throws { commands.append(command) }
}

private struct Boom: Error {}

private final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 10_000)
}

final class NowPlayingModuleTests: XCTestCase {
    private func track(playing: Bool = true) -> NowPlaying {
        NowPlaying(title: "Song", artist: "Band", isPlaying: playing, source: .mediaRemoteAdapter)
    }

    func testPrefersAdapter() async throws {
        let a = StubSource("MediaRemote adapter", result: .success(track()))
        let s = StubSource("Spotify", result: .success(track()))
        let m = NowPlayingModule(sources: [a, s])
        try await m.refresh()
        XCTAssertEqual(m.activeSourceDescription, "Using MediaRemote adapter")
        XCTAssertEqual(m.status, .ok)
    }

    func testFallsBackWhenSelfTestFails() async throws {
        let a = StubSource("MediaRemote adapter", test: false)
        let s = StubSource("Spotify", result: .success(track()))
        let m = NowPlayingModule(sources: [a, s])
        try await m.refresh()
        XCTAssertEqual(m.activeSourceDescription, "Using Spotify")
        XCTAssertEqual(m.nowPlaying?.title, "Song")
    }

    func testFallsBackWhenAdapterThrows() async throws {
        let a = StubSource("MediaRemote adapter", result: .failure(Boom()))
        let s = StubSource("Spotify", result: .success(track()))
        let m = NowPlayingModule(sources: [a, s])
        try await m.refresh()
        XCTAssertEqual(m.activeSourceDescription, "Using Spotify")
    }

    func testBothFailIsUnavailableNotThrown() async throws {
        let a = StubSource("MediaRemote adapter", test: false)
        let s = StubSource("Spotify", result: .failure(Boom()))
        let m = NowPlayingModule(sources: [a, s])
        try await m.refresh()
        XCTAssertEqual(m.status, .unavailable(reason: "Now Playing unavailable"))
        XCTAssertNil(m.activeSourceDescription)
        XCTAssertNil(try m.collapsedActivity(at: Date()))
    }

    func testRecoversAfterFailure() async throws {
        let a = StubSource("MediaRemote adapter", test: false)
        let m = NowPlayingModule(sources: [a])
        try await m.refresh()
        XCTAssertFalse(m.status.isAvailable)
        a.testResult = true
        a.result = .success(track())
        try await m.refresh()
        XCTAssertEqual(m.status, .ok)
    }

    func testActivityWhilePlayingAndGoneAfter60sPaused() async throws {
        let clock = Clock()
        let a = StubSource("MediaRemote adapter", result: .success(track()))
        let m = NowPlayingModule(sources: [a], clock: { clock.now })
        try await m.refresh()
        let activity = try XCTUnwrap(try m.collapsedActivity(at: clock.now))
        XCTAssertEqual(activity.text, "Song · Band")
        XCTAssertEqual(activity.source, .nowPlaying)
        XCTAssertFalse(activity.isAlert)

        a.result = .success(track(playing: false))
        try await m.refresh()
        XCTAssertNotNil(try m.collapsedActivity(at: clock.now.addingTimeInterval(30)))
        clock.now = clock.now.addingTimeInterval(30)
        try await m.refresh()  // still paused: the pause start must not reset
        XCTAssertNotNil(try m.collapsedActivity(at: clock.now.addingTimeInterval(20)))
        XCTAssertNil(try m.collapsedActivity(at: clock.now.addingTimeInterval(40)))

        a.result = .success(track())
        try await m.refresh()
        XCTAssertNotNil(try m.collapsedActivity(at: clock.now.addingTimeInterval(500)))
    }

    func testCommandsForwardedToActiveSource() async throws {
        let a = StubSource("MediaRemote adapter", result: .success(track()))
        let m = NowPlayingModule(sources: [a])
        await m.send(.playPause)  // no active source yet: ignored
        try await m.refresh()
        await m.send(.seek(to: 42))
        XCTAssertEqual(a.commands, [.seek(to: 42)])
    }
}
