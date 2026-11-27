import Foundation

/// What is playing right now, from any source.
public struct NowPlaying: Equatable, Sendable {
    public enum Source: String, Sendable {
        case mediaRemoteAdapter
        case spotifyAppleScript
    }

    public var title: String
    public var artist: String?
    public var album: String?
    /// Seconds; nil when unknown (streams).
    public var duration: TimeInterval?
    /// Playback position in seconds at `timestamp`.
    public var elapsed: TimeInterval?
    /// When `elapsed` was true, so the position can be extrapolated.
    public var timestamp: Date?
    public var isPlaying: Bool
    public var playbackRate: Double
    public var bundleIdentifier: String?
    public var appName: String?
    public var artwork: Data?
    /// Remote artwork (Spotify gives a URL instead of bytes).
    public var artworkURL: String?
    public var source: Source

    public init(
        title: String, artist: String? = nil, album: String? = nil,
        duration: TimeInterval? = nil, elapsed: TimeInterval? = nil, timestamp: Date? = nil,
        isPlaying: Bool = true, playbackRate: Double = 1,
        bundleIdentifier: String? = nil, appName: String? = nil,
        artwork: Data? = nil, artworkURL: String? = nil, source: Source
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.timestamp = timestamp
        self.isPlaying = isPlaying
        self.playbackRate = playbackRate
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.artwork = artwork
        self.artworkURL = artworkURL
        self.source = source
    }

    /// Position at `now`, extrapolated while playing and clamped to `0...duration`.
    public func position(at now: Date) -> TimeInterval? {
        guard let elapsed else { return nil }
        var position = elapsed
        if isPlaying, let timestamp {
            position += max(now.timeIntervalSince(timestamp), 0) * playbackRate
        }
        if let duration { position = min(position, duration) }
        return max(position, 0)
    }
}

public enum NowPlayingCommand: Equatable, Sendable {
    case playPause
    case next
    case previous
    case seek(to: TimeInterval)
}

/// A way to read (and control) what is playing. The Mac app supplies the real process runners.
public protocol NowPlayingSource: Sendable {
    /// "MediaRemote adapter", "Spotify": shown in Settings.
    var name: String { get }
    /// True when this source can work on this machine right now.
    func selfTest() async -> Bool
    /// Current state; nil when nothing is playing. Throws when the source breaks.
    func snapshot() async throws -> NowPlaying?
    func send(_ command: NowPlayingCommand) async throws
}
