import Foundation

/// What the Mac has to share right now.
public struct SyncSnapshotContent: Sendable {
    public var readings: [SyncReading]
    public var agents: [SyncAgent]

    public init(readings: [SyncReading] = [], agents: [SyncAgent] = []) {
        self.readings = readings
        self.agents = agents
    }
}

public enum SyncAuth {
    /// The `X-Ufuq-Auth` value a client sends: its clock, sealed with the shared key.
    public static func token(sealer: SyncSealer, now: Date) throws -> String {
        let plain = Data("\(SyncProtocol.authPrefix)\(Int(now.timeIntervalSince1970))".utf8)
        return SyncCoding.base64URLEncode(try sealer.seal(plain))
    }

    /// True when the token opens with our key and its time is within `maxClockSkew` of `now`.
    public static func verify(_ token: String?, sealer: SyncSealer, now: Date) -> Bool {
        issuedAt(token, sealer: sealer, now: now) != nil
    }

    /// The client time sealed in a valid token, or nil when it fails to open or is outside the skew window.
    public static func issuedAt(_ token: String?, sealer: SyncSealer, now: Date) -> Date? {
        guard let token, let sealed = SyncCoding.base64URLDecode(token),
              let plain = try? sealer.open(sealed),
              let text = String(data: plain, encoding: .utf8), text.hasPrefix(SyncProtocol.authPrefix),
              let seconds = TimeInterval(text.dropFirst(SyncProtocol.authPrefix.count)),
              abs(now.timeIntervalSince1970 - seconds) <= SyncProtocol.maxClockSkew else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

/// Maps a parsed request to a response. Transport-free, so it is tested on Linux.
/// Order: unpaired or replayed requests get an empty 401 before anything else is revealed.
public struct SyncRouter: Sendable {
    public typealias ContentProvider = @Sendable () async -> SyncSnapshotContent

    private let sealer: SyncSealer
    private let log: SyncEventLog
    private let content: ContentProvider
    private let now: @Sendable () -> Date
    private let longPollTimeout: TimeInterval
    private let replayGuard = SyncReplayGuard()

    public init(sealer: SyncSealer, log: SyncEventLog, content: @escaping ContentProvider,
                now: @escaping @Sendable () -> Date = { Date() },
                longPollTimeout: TimeInterval = SyncProtocol.longPollTimeout) {
        self.sealer = sealer
        self.log = log
        self.content = content
        self.now = now
        self.longPollTimeout = longPollTimeout
    }

    public func handle(_ request: HTTPRequest) async -> HTTPResponse {
        let token = request.headers[SyncProtocol.authHeader.lowercased()]
        let at = now()
        // A token is usable once: a replay on the same network gets the same empty 401 as a stranger.
        // Keyed on the canonical encoding, so a re-padded copy of the same bytes is still a replay.
        guard let token, let issued = SyncAuth.issuedAt(token, sealer: sealer, now: at),
              let sealed = SyncCoding.base64URLDecode(token),
              await replayGuard.admit(SyncCoding.base64URLEncode(sealed), expires: issued.addingTimeInterval(SyncProtocol.maxClockSkew), now: at) else {
            return HTTPResponse(status: 401)
        }
        do {
            switch request.path {
            case "/v1/snapshot":
                let c = await content()
                return try ok(SyncSnapshot(generatedAt: now(), readings: c.readings, agents: c.agents))
            case "/v1/events":
                var since = Int(request.query["since"] ?? "0") ?? 0
                // A cursor ahead of the log means the Mac app restarted; start over.
                let latest = await log.latestSeq
                if since > latest || since < 0 { since = 0 }
                let events = await log.wait(since: since, timeout: longPollTimeout)
                // The cursor is the last event handed out (or `since`), so none is skipped.
                let batch = SyncEventBatch(generatedAt: now(), latestSeq: events.last?.seq ?? since, events: events)
                return try ok(batch)
            default:
                return HTTPResponse(status: 404)
            }
        } catch {
            return HTTPResponse(status: 500)
        }
    }

    private func ok<T: Encodable>(_ value: T) throws -> HTTPResponse {
        HTTPResponse(status: 200, body: try sealer.seal(try SyncCoding.encode(value)))
    }
}
