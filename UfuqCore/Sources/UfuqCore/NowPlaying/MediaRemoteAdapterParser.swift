import Foundation

/// Parses output of ungive/mediaremote-adapter.
///
/// `get` prints one payload object. `stream` prints one envelope per line:
/// `{"type":"data","diff":<bool>,"payload":{...}}`; with `diff` true the payload holds only the
/// changed keys and a key set to null was removed. Keys per the README
/// (https://github.com/ungive/mediaremote-adapter): `title`, `artist`, `album`, `duration`,
/// `elapsedTime`, `timestamp`, `playing`, `playbackRate`, `bundleIdentifier`, `artworkData`
/// (base64). The README does not state units or the timestamp format, so this is defensive:
/// durations are seconds, and `timestamp` may be epoch seconds, epoch microseconds or ISO 8601.
public struct MediaRemoteAdapterParser {
    public struct Result: Equatable, Sendable {
        /// Final state after all lines; nil when nothing is playing.
        public var nowPlaying: NowPlaying?
        /// Lines that were not a JSON object.
        public var skipped: Int
    }

    /// Accumulated payload, so a stream of diffs can be fed line by line.
    private var payload: [String: Any] = [:]
    public private(set) var skipped = 0

    public init() {}

    public static func parse(_ data: Data) -> Result {
        var parser = MediaRemoteAdapterParser()
        parser.ingest(data)
        return Result(nowPlaying: parser.nowPlaying, skipped: parser.skipped)
    }

    public mutating func ingest(_ data: Data) {
        var parser = self
        JSONLines.forEachObject(in: data) { object in
            guard let object else { parser.skipped += 1; return }
            parser.apply(object)
        }
        self = parser
    }

    public var nowPlaying: NowPlaying? { Self.build(payload) }

    private mutating func apply(_ object: [String: Any]) {
        guard let inner = object["payload"] as? [String: Any] else {
            // `get` output, or an envelope whose payload is not a dictionary.
            if object["type"] != nil || object["diff"] != nil { return }
            payload = Self.clean(object)
            return
        }
        if (object["diff"] as? Bool) == true {
            for (key, value) in inner {
                if value is NSNull { payload[key] = nil } else { payload[key] = value }
            }
        } else {
            payload = Self.clean(inner)
        }
    }

    private static func clean(_ dict: [String: Any]) -> [String: Any] {
        dict.filter { !($0.value is NSNull) }
    }

    private static func build(_ p: [String: Any]) -> NowPlaying? {
        guard let title = p["title"] as? String, !title.isEmpty else { return nil }
        let artwork = (p["artworkData"] as? String).flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
        let rate = number(p["playbackRate"]) ?? 1
        let playing = bool(p["playing"]) ?? false
        return NowPlaying(
            title: title,
            artist: nonEmpty(p["artist"]),
            album: nonEmpty(p["album"]),
            duration: number(p["duration"]) ?? number(p["durationMicros"]).map { $0 / 1_000_000 },
            elapsed: number(p["elapsedTime"]) ?? number(p["elapsedTimeMicros"]).map { $0 / 1_000_000 },
            timestamp: date(p["timestamp"] ?? p["timestampEpochMicros"]),
            isPlaying: playing,
            playbackRate: playing && rate == 0 ? 1 : rate,
            bundleIdentifier: nonEmpty(p["bundleIdentifier"]),
            appName: nil,
            artwork: (artwork?.isEmpty ?? true) ? nil : artwork,
            source: .mediaRemoteAdapter)
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        return s
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.intValue != 0 }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        if let s = value as? String {
            let plain = ISO8601DateFormatter()
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = fractional.date(from: s) ?? plain.date(from: s) { return d }
            if let n = Double(s) { return epoch(n) }
            return nil
        }
        if let n = value as? NSNumber { return epoch(n.doubleValue) }
        return nil
    }

    /// Seconds, or microseconds when the value is implausibly large for seconds.
    private static func epoch(_ n: Double) -> Date {
        Date(timeIntervalSince1970: n > 1e12 ? n / 1_000_000 : n)
    }
}

