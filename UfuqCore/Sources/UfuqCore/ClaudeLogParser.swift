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
    /// With a `cache`, a file whose modification date (known) and size are unchanged is not read
    /// again; the result is identical to parsing everything.
    public static func parse(configDir: String, source: FileSource = LocalFileSource(),
                             cache: ClaudeLogCache? = nil) -> UsageResult<ClaudeUsageReport> {
        let projects = ((configDir as NSString).expandingTildeInPath as NSString).appendingPathComponent("projects")
        let paths: [String]
        do {
            paths = try source.files(under: projects, suffix: ".jsonl")
        } catch {
            return .unavailable(reason: "Claude logs not readable: \(error)")
        }

        var acc = Accumulator()
        var failed = 0
        var kept: [String: ClaudeLogCache.Entry] = [:]
        for path in paths {
            let mtime = source.modificationDate(path)
            let size = source.size(path)
            if let mtime, let cached = cache?.entry(for: path), cached.mtime == mtime, cached.size == size {
                acc.merge(cached.parsed)
                kept[path] = cached
            } else if let data = try? source.read(path) {
                let parsed = FileParse(data)
                acc.merge(parsed)
                if let mtime { kept[path] = ClaudeLogCache.Entry(mtime: mtime, size: size, parsed: parsed) }
            } else {
                failed += 1
            }
        }
        cache?.update(directory: projects, kept: kept)
        if !paths.isEmpty, acc.filesRead == 0 {
            return .unavailable(reason: "No Claude log file could be read (\(failed) failed)")
        }
        return acc.finish(filesFailed: failed)
    }

    /// Parses raw JSONL file contents.
    public static func parse(files: [Data], filesFailed: Int = 0) -> UsageResult<ClaudeUsageReport> {
        var acc = Accumulator()
        for data in files { acc.merge(FileParse(data)) }
        return acc.finish(filesFailed: filesFailed)
    }

    /// What one file holds, before deduplication across files.
    struct FileParse: Sendable {
        var entries: [(key: String?, entry: ClaudeUsageEntry)] = []
        var skipped = 0
        var validObjects = 0

        init(_ data: Data) {
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
                entries.append((ids.isEmpty ? nil : ids.joined(separator: "|"), entry))
            }
        }
    }

    /// Folds files in one at a time so only the deduplicated entries stay in memory.
    private struct Accumulator {
        var byKey: [String: ClaudeUsageEntry] = [:]
        var keyless: [ClaudeUsageEntry] = []
        var skipped = 0
        var duplicates = 0
        var validObjects = 0
        var filesRead = 0

        mutating func merge(_ file: FileParse) {
            filesRead += 1
            skipped += file.skipped
            validObjects += file.validObjects
            for (key, entry) in file.entries {
                guard let key else { keyless.append(entry); continue }
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

/// Per-file parse results, keyed by full path, so unchanged log files are not read again.
/// Shared across config dirs. A file with an unknown modification date is never cached.
public final class ClaudeLogCache: @unchecked Sendable {
    struct Entry: Sendable {
        var mtime: Date
        var size: Int?
        var parsed: ClaudeLogParser.FileParse
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init() {}

    func entry(for path: String) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        return entries[path]
    }

    /// Stores `kept` and drops entries under `directory` that are no longer listed (or are not
    /// cacheable now), so deleted files leave the cache.
    func update(directory: String, kept: [String: Entry]) {
        lock.lock(); defer { lock.unlock() }
        let prefix = directory.hasSuffix("/") ? directory : directory + "/"
        for path in entries.keys where path.hasPrefix(prefix) && kept[path] == nil { entries[path] = nil }
        for (path, entry) in kept { entries[path] = entry }
    }
}
