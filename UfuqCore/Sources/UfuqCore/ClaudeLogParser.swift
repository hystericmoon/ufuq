import Foundation

public struct TokenCounts: Equatable, Sendable {
    public var input = 0
    public var output = 0
    public var cacheCreation = 0
    public var cacheRead = 0

    public init(input: Int = 0, output: Int = 0, cacheCreation: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheCreation = cacheCreation
        self.cacheRead = cacheRead
    }

    public var total: Int { Self.add(Self.add(input, output), Self.add(cacheCreation, cacheRead)) }

    public static func + (a: TokenCounts, b: TokenCounts) -> TokenCounts {
        TokenCounts(input: add(a.input, b.input), output: add(a.output, b.output),
                    cacheCreation: add(a.cacheCreation, b.cacheCreation), cacheRead: add(a.cacheRead, b.cacheRead))
    }

    /// Saturating add: corrupt logs must not trap the app.
    private static func add(_ a: Int, _ b: Int) -> Int {
        let (sum, overflow) = a.addingReportingOverflow(b)
        return overflow ? (a < 0 ? Int.min : Int.max) : sum
    }
}

/// One assistant message's usage after deduplication.
public struct ClaudeUsageEntry: Equatable, Sendable {
    public var timestamp: Date
    public var model: String?
    public var tokens: TokenCounts
}

/// A 5-hour block: starts at the first message's hour (UTC) and lasts 5 hours.
public struct ClaudeUsageBlock: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var lastActivity: Date
    public var tokens: TokenCounts
    public var messageCount: Int

    public func isActive(at now: Date) -> Bool { now >= start && now < end }
}

public struct ClaudeUsageReport: Equatable, Sendable {
    public var blocks: [ClaudeUsageBlock]
    public var entries: [ClaudeUsageEntry]
    public var filesRead: Int
    public var filesFailed: Int
    /// Lines that were not valid JSON (or an assistant line with unusable fields).
    public var skippedLines: Int
    public var duplicatesDropped: Int

    /// The block containing `now`, if any.
    public func currentBlock(at now: Date) -> ClaudeUsageBlock? {
        blocks.last { $0.isActive(at: now) }
    }

    /// Tokens over the 7 days up to `now`.
    public func weeklyTokens(at now: Date) -> TokenCounts {
        let from = now.addingTimeInterval(-ClaudeLogParser.weekLength)
        return entries.filter { $0.timestamp > from && $0.timestamp <= now }
            .reduce(TokenCounts()) { $0 + $1.tokens }
    }
}

public enum ClaudeLogParser {
    public static let blockLength: TimeInterval = 5 * 3600
    public static let weekLength: TimeInterval = 7 * 24 * 3600

    /// `<config dir>`: `CLAUDE_CONFIG_DIR` from `environment`, else `~/.claude`.
    public static func defaultConfigDir(environment: [String: String] = ProcessInfo.processInfo.environment,
                                        home: String = NSHomeDirectory()) -> String {
        if let dir = environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty { return dir }
        return (home as NSString).appendingPathComponent(".claude")
    }

    /// Reads every `projects/**/*.jsonl` under `configDir` (`~` is expanded), one file at a time.
    /// With `modifiedSince`, files last modified before it are skipped; a file whose date is
    /// unknown is always read.
    public static func parse(configDir: String, source: FileSource = LocalFileSource(),
                             modifiedSince: Date? = nil) -> UsageResult<ClaudeUsageReport> {
        let projects = ((configDir as NSString).expandingTildeInPath as NSString).appendingPathComponent("projects")
        var paths: [String]
        do {
            paths = try source.files(under: projects, suffix: ".jsonl")
        } catch {
            return .unavailable(reason: "Claude logs not readable: \(error)")
        }
        if let modifiedSince {
            paths = paths.filter { path in source.modificationDate(path).map { $0 >= modifiedSince } ?? true }
        }

        var acc = Accumulator()
        var failed = 0
        for path in paths {
            if let data = try? source.read(path) { acc.ingest(data) } else { failed += 1 }
        }
        if !paths.isEmpty, acc.filesRead == 0 {
            return .unavailable(reason: "No Claude log file could be read (\(failed) failed)")
        }
        return acc.finish(filesFailed: failed)
    }

    /// Parses raw JSONL file contents.
    public static func parse(files: [Data], filesFailed: Int = 0) -> UsageResult<ClaudeUsageReport> {
        var acc = Accumulator()
        for data in files { acc.ingest(data) }
        return acc.finish(filesFailed: filesFailed)
    }

    /// Folds files in one at a time so only the deduplicated entries stay in memory.
    private struct Accumulator {
        var byKey: [String: ClaudeUsageEntry] = [:]
        var keyless: [ClaudeUsageEntry] = []
        var skipped = 0
        var duplicates = 0
        var validObjects = 0
        var filesRead = 0

        mutating func ingest(_ data: Data) {
            filesRead += 1
            JSONLines.forEachObject(in: data) { object in
                guard let object else { skipped += 1; return }
                validObjects += 1
                guard (object["type"] as? String) == "assistant",
                      let message = object["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else { return }
                guard let timestamp = JSONLines.date(object["timestamp"]) else { skipped += 1; return }

                let tokens = TokenCounts(
                    input: max(JSONLines.int(usage["input_tokens"]) ?? 0, 0),
                    output: max(JSONLines.int(usage["output_tokens"]) ?? 0, 0),
                    cacheCreation: max(JSONLines.int(usage["cache_creation_input_tokens"]) ?? 0, 0),
                    cacheRead: max(JSONLines.int(usage["cache_read_input_tokens"]) ?? 0, 0))
                let entry = ClaudeUsageEntry(timestamp: timestamp, model: message["model"] as? String, tokens: tokens)

                // Prefixes keep a message id "x" apart from a request id "x".
                let ids = [(message["id"] as? String).map { "m:" + $0 }, (object["requestId"] as? String).map { "r:" + $0 }]
                    .compactMap { $0 }
                if ids.isEmpty { keyless.append(entry); return }
                let key = ids.joined(separator: "|")
                if let existing = byKey[key] {
                    duplicates += 1
                    // Streamed duplicates grow as the message completes; keep the fullest.
                    if entry.tokens.total > existing.tokens.total { byKey[key] = entry }
                } else {
                    byKey[key] = entry
                }
            }
        }

        func finish(filesFailed: Int) -> UsageResult<ClaudeUsageReport> {
            if validObjects == 0, skipped > 0 {
                return .unavailable(reason: "Claude logs are not valid JSONL (\(skipped) bad lines)")
            }
            let entries = (Array(byKey.values) + keyless).sorted { $0.timestamp < $1.timestamp }
            return .available(ClaudeUsageReport(
                blocks: ClaudeLogParser.blocks(from: entries), entries: entries,
                filesRead: filesRead, filesFailed: filesFailed,
                skippedLines: skipped, duplicatesDropped: duplicates))
        }
    }

    static func floorToHour(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }

    /// Entries must be sorted. A new block starts when a message falls past the current block's
    /// end, or after a gap of more than 5 hours.
    static func blocks(from entries: [ClaudeUsageEntry]) -> [ClaudeUsageBlock] {
        var result: [ClaudeUsageBlock] = []
        for entry in entries {
            if var last = result.last,
               entry.timestamp < last.end,
               entry.timestamp.timeIntervalSince(last.lastActivity) <= blockLength {
                last.tokens = last.tokens + entry.tokens
                last.messageCount += 1
                last.lastActivity = entry.timestamp
                result[result.count - 1] = last
            } else {
                let start = floorToHour(entry.timestamp)
                result.append(ClaudeUsageBlock(start: start, end: start.addingTimeInterval(blockLength),
                                               lastActivity: entry.timestamp, tokens: entry.tokens, messageCount: 1))
            }
        }
        return result
    }
}
