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
                             maxFiles: Int = 20) -> UsageResult<CodexRateLimits> {
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

        var datas: [Data] = []
        for path in rollouts {
            if let data = try? source.read(path) { datas.append(data) }
        }
        guard !datas.isEmpty else { return .unavailable(reason: "No Codex session file could be read") }
        return parse(files: datas)
    }

    public static func parse(files: [Data]) -> UsageResult<CodexRateLimits> {
        var best: CodexRateLimits?
        var sawSnapshotLine = false
        for data in files {
            for object in JSONLines.objects(in: data) {
                guard let object,
                      let payload = object["payload"] as? [String: Any],
                      (payload["type"] as? String) == "token_count",
                      let limits = payload["rate_limits"] as? [String: Any],
                      let timestamp = JSONLines.date(object["timestamp"]) else { continue }
                sawSnapshotLine = true
                let readings = readings(from: limits, capturedAt: timestamp)
                guard !readings.isEmpty else { continue }
                if best == nil || timestamp >= best!.capturedAt {
                    best = CodexRateLimits(capturedAt: timestamp, readings: readings)
                }
            }
        }
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
            if let epoch = JSONLines.double(window["resets_at"]), epoch.isFinite {
                resetsAt = Date(timeIntervalSince1970: epoch)
            } else if let secs = JSONLines.double(window["resets_in_seconds"]), secs.isFinite {
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
