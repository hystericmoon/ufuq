import Foundation

/// The latest rate-limit snapshot found in Codex session logs.
public struct CodexRateLimits: Equatable, Sendable {
    public var capturedAt: Date
    public var readings: [UsageWindowReading]
}

/// Parses `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. Field names are assumptions to verify
/// on a real Mac: `payload.type == "token_count"`, `payload.rate_limits.{primary,secondary}` with
/// `used_percent`, `window_minutes` and `resets_in_seconds` or `resets_at`.
public enum CodexParser {
    public static func defaultSessionsDir(home: String = NSHomeDirectory()) -> String {
        (home as NSString).appendingPathComponent(".codex/sessions")
    }

    /// Reads the newest `maxFiles` rollout files and returns the most recent snapshot.
    public static func parse(sessionsDir: String = defaultSessionsDir(),
                             source: FileSource = LocalFileSource(),
                             maxFiles: Int = 20,
                             now: Date = Date()) -> UsageResult<CodexRateLimits> {
        let paths: [String]
        do {
            paths = try source.files(under: sessionsDir, suffix: ".jsonl")
        } catch {
            return .unavailable(reason: "Codex sessions not readable: \(error)")
        }
        let rollouts = paths
            .filter { ($0 as NSString).lastPathComponent.hasPrefix("rollout-") }
            .sorted(by: >)
            .prefix(maxFiles)
        guard !rollouts.isEmpty else { return .unavailable(reason: "No Codex session files found") }

        var acc = Accumulator(now: now)
        var read = 0
        for path in rollouts {
            if let data = try? source.read(path) { acc.ingest(data); read += 1 }
        }
        guard read > 0 else { return .unavailable(reason: "No Codex session file could be read") }
        return acc.finish()
    }

    /// Snapshots stamped more than a day after `now` are clock skew or corruption and are ignored,
    /// so one bad line cannot pin the "latest" snapshot forever.
    public static func parse(files: [Data], now: Date = Date()) -> UsageResult<CodexRateLimits> {
        var acc = Accumulator(now: now)
        for data in files { acc.ingest(data) }
        return acc.finish()
    }

    private struct Accumulator {
        var now: Date
        var best: CodexRateLimits?
        var sawSnapshotLine = false

        mutating func ingest(_ data: Data) {
            let latestAllowed = now.addingTimeInterval(86_400)
            JSONLines.forEachObject(in: data) { object in
                guard let object,
                      let payload = object["payload"] as? [String: Any],
                      (payload["type"] as? String) == "token_count",
                      let limits = payload["rate_limits"] as? [String: Any],
                      let timestamp = JSONLines.date(object["timestamp"]), timestamp <= latestAllowed else { return }
                sawSnapshotLine = true
                let readings = CodexParser.readings(from: limits, capturedAt: timestamp)
                guard !readings.isEmpty else { return }
                if let current = best, timestamp < current.capturedAt { return }
                best = CodexRateLimits(capturedAt: timestamp, readings: readings)
            }
        }

        func finish() -> UsageResult<CodexRateLimits> { CodexParser.result(best: best, sawSnapshotLine: sawSnapshotLine) }
    }

    private static func result(best: CodexRateLimits?, sawSnapshotLine: Bool) -> UsageResult<CodexRateLimits> {
        if let best { return .available(best) }
        return .unavailable(reason: sawSnapshotLine
            ? "Codex rate_limits had no usable window"
            : "No Codex rate-limit snapshot found in session logs")
    }

    static func readings(from limits: [String: Any], capturedAt: Date) -> [UsageWindowReading] {
        var out: [UsageWindowReading] = []
        for (name, fallback) in [("primary", UsageWindowKind.session5h), ("secondary", .weekly)] {
            guard let window = limits[name] as? [String: Any],
                  let percent = JSONLines.double(window["used_percent"]), percent.isFinite else { continue }
            let kind = JSONLines.double(window["window_minutes"]).map(kind(forMinutes:)) ?? fallback
            let resetsAt: Date?
            if let epoch = JSONLines.double(window["resets_at"]), let date = JSONLines.epochDate(epoch) {
                resetsAt = date
            } else if let secs = JSONLines.double(window["resets_in_seconds"]), secs.isFinite, abs(secs) < 1e9 {
                resetsAt = capturedAt.addingTimeInterval(secs)
            } else {
                resetsAt = nil
            }
            let snapshot = UsageSnapshot(fraction: max(percent, 0) / 100, capturedAt: capturedAt, resetsAt: resetsAt)
            out.append(UsageWindowReading(kind: kind, snapshot: snapshot))
        }
        return out
    }

    /// Windows up to 6 h count as the session window; longer ones as weekly.
    static func kind(forMinutes minutes: Double) -> UsageWindowKind {
        minutes <= 360 ? .session5h : .weekly
    }
}
