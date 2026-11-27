import Foundation

/// Now Playing: tries the MediaRemote adapter first, falls back to Spotify. A broken source
/// means "unavailable", never a crash.
public final class NowPlayingModule: UfuqModule {
    public let id = "nowPlaying"
    public let title = "Now Playing"
    public var isEnabled = true

    /// Paused longer than this leaves the wing.
    public static let pausedWingWindow: TimeInterval = 60
    public static let unavailableReason = "Now Playing unavailable"

    private struct State {
        var current: NowPlaying?
        var activeSource: String?
        var verified: String?
        var pausedSince: Date?
        var failed = false
    }

    private let sources: [any NowPlayingSource]
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var state = State()

    /// `sources` in preference order (adapter first, Spotify second).
    public init(sources: [any NowPlayingSource], clock: @escaping @Sendable () -> Date = { Date() }) {
        self.sources = sources
        self.clock = clock
    }

    public var status: ModuleStatus {
        withLock { $0.failed } ? .unavailable(reason: Self.unavailableReason) : .ok
    }

    /// For Settings: "Using MediaRemote adapter" / "Using Spotify"; nil when none works.
    public var activeSourceDescription: String? {
        withLock { $0.activeSource }.map { "Using \($0)" }
    }

    public var nowPlaying: NowPlaying? { withLock { $0.current } }

    public func refresh() async throws {
        let verified = withLock { $0.verified }
        for source in sources {
            if source.name != verified, !(await source.selfTest()) { continue }
            do {
                let snapshot = try await source.snapshot()
                apply(snapshot, from: source.name)
                return
            } catch {
                withLock { if $0.verified == source.name { $0.verified = nil } }
            }
        }
        withLock {
            $0.current = nil
            $0.activeSource = nil
            $0.verified = nil
            $0.pausedSince = nil
            $0.failed = true
        }
    }

    private func apply(_ snapshot: NowPlaying?, from name: String) {
        let now = clock()
        withLock { state in
            state.failed = false
            state.verified = name
            state.activeSource = name
            state.current = snapshot
            if let snapshot, !snapshot.isPlaying {
                if state.pausedSince == nil { state.pausedSince = now }
            } else {
                state.pausedSince = nil
            }
        }
    }

    /// Forwards to the source in use. Errors are swallowed: a failed command is not a failed module.
    public func send(_ command: NowPlayingCommand) async {
        guard let name = withLock({ $0.activeSource }),
              let source = sources.first(where: { $0.name == name }) else { return }
        try? await source.send(command)
    }

    public func collapsedActivity(at now: Date) throws -> LiveActivity? {
        let (current, pausedSince) = withLock { ($0.current, $0.pausedSince) }
        guard let current else { return nil }
        if !current.isPlaying {
            guard let pausedSince, now.timeIntervalSince(pausedSince) <= Self.pausedWingWindow else { return nil }
        }
        let text = [current.title, current.artist].compactMap { $0 }.joined(separator: " · ")
        let by = current.artist.map { " by \($0)" } ?? ""
        return LiveActivity(
            id: "nowPlaying", moduleID: id, source: .nowPlaying, text: text,
            accessibilityLabel: "\(current.isPlaying ? "Playing" : "Paused"), \(current.title)\(by)")
    }

    public func accessibilitySummary() -> String {
        (try? collapsedActivity(at: clock()))?.accessibilityLabel ?? "Nothing playing"
    }

    private func withLock<T>(_ body: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }
}
