import XCTest
@testable import UfuqCore

private func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

final class TokenFormatTests: XCTestCase {
    func testCompact() {
        XCTAssertEqual(TokenFormat.compact(812), "812")
        XCTAssertEqual(TokenFormat.compact(12_500), "12.5K")
        XCTAssertEqual(TokenFormat.compact(4_200_000), "4.2M")
        XCTAssertEqual(TokenFormat.compact(250_000_000), "250M")
        XCTAssertEqual(TokenFormat.compact(1_100_000_000), "1.1B")
        XCTAssertEqual(TokenFormat.compact(2_000_000), "2M")
        XCTAssertEqual(TokenFormat.compact(-5), "0")
        XCTAssertEqual(TokenFormat.compact(0), "0")
    }

    func testSpoken() {
        XCTAssertEqual(TokenFormat.spoken(4_200_000), "4.2 million tokens")
        XCTAssertEqual(TokenFormat.spoken(812), "812 tokens")
        XCTAssertEqual(TokenFormat.spoken(1), "1 token")
        XCTAssertEqual(TokenFormat.spoken(12_500), "12.5 thousand tokens")
        XCTAssertEqual(TokenFormat.spoken(1_100_000_000), "1.1 billion tokens")
    }
}

final class ClaudeAccountsTests: XCTestCase {
    private let home = "/Users/me"

    private func dirs(env: [String: String] = [:], entries: [String], existing: Set<String>) -> [String] {
        ClaudeAccounts.configDirs(
            home: home, environment: env,
            listDirectory: { _ in entries }, directoryExists: { existing.contains($0) })
    }

    func testDiscoversAccountsWithProjects() {
        let result = dirs(
            entries: [".claude-work", ".claude", ".claude.json", ".claude_old", ".claudeX", ".config", ".claude-empty"],
            existing: ["/Users/me/.claude", "/Users/me/.claude/projects",
                       "/Users/me/.claude-work", "/Users/me/.claude-work/projects",
                       "/Users/me/.claude_old", "/Users/me/.claude_old/projects",
                       "/Users/me/.claude-empty",
                       "/Users/me/.claudeX", "/Users/me/.claudeX/projects"])
        XCTAssertEqual(result, ["/Users/me/.claude", "/Users/me/.claude-work", "/Users/me/.claude_old"])
    }

    func testEnvDirIsAddedAndDeduped() {
        let existing: Set<String> = ["/Users/me/.claude", "/Users/me/.claude/", "/Users/me/.claude/projects", "/opt/acct"]
        XCTAssertEqual(dirs(env: ["CLAUDE_CONFIG_DIR": "/opt/acct"], entries: [".claude"], existing: existing),
                       ["/Users/me/.claude", "/opt/acct"])
        XCTAssertEqual(dirs(env: ["CLAUDE_CONFIG_DIR": "/Users/me/.claude/"], entries: [".claude"], existing: existing),
                       ["/Users/me/.claude"])
        XCTAssertEqual(dirs(env: ["CLAUDE_CONFIG_DIR": "/missing"], entries: [], existing: []), [])
    }

    func testLabels() {
        XCTAssertEqual(ClaudeAccounts.label(forConfigDir: "/Users/me/.claude"), "Claude")
        XCTAssertEqual(ClaudeAccounts.label(forConfigDir: "/Users/me/.claude-work/"), "Claude · Work")
        XCTAssertEqual(ClaudeAccounts.label(forConfigDir: "/Users/me/.claude_personal"), "Claude · Personal")
        XCTAssertEqual(ClaudeAccounts.label(forConfigDir: "/opt/acct"), "Claude · Acct")
    }
}

final class AIUsageModuleTests: XCTestCase {
    private let now = utc("2026-11-26T14:00:00Z")
    private let claudeDir = "/h/.claude"
    private let workDir = "/h/.claude-work"
    private let codexDir = "/h/.codex/sessions"

    /// Real Claude Code shape: several line types, a repeated assistant line, extra usage keys.
    private var claudeLog: String {
        let usage = #"{"input_tokens":6,"cache_creation_input_tokens":1000,"cache_read_input_tokens":3000,"output_tokens":200,"output_tokens_details":{"x":1},"server_tool_use":{"web_search_requests":0},"cache_creation":{"ephemeral_5m_input_tokens":1000},"iterations":[{"a":1}],"service_tier":"standard","speed":"standard","inference_geo":"","fallback_credit":null}"#
        let line1 = #"{"type":"assistant","timestamp":"2026-11-26T13:21:14.685Z","requestId":"req_1","message":{"id":"msg_1","model":"claude-x","usage":\#(usage)}}"#
        let line2 = #"{"type":"assistant","timestamp":"2026-11-26T13:30:00.000Z","requestId":"req_2","message":{"id":"msg_2","model":"claude-x","usage":{"input_tokens":4,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":10}}}"#
        return [
            #"{"type":"queue-operation","timestamp":"2026-11-26T13:20:00.000Z"}"#,
            #"{"type":"user","timestamp":"2026-11-26T13:21:00.000Z","message":{"role":"user","content":"hi"}}"#,
            line1, line1,
            #"{"type":"attachment","timestamp":"2026-11-26T13:22:00.000Z"}"#,
            line2,
            #"{"type":"system","timestamp":"2026-11-26T13:31:00.000Z"}"#,
        ].joined(separator: "\n") + "\n"
    }

    private let codexLog = #"{"timestamp":"2026-11-26T13:50:00.000Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":84.0,"window_minutes":300,"resets_in_seconds":3600},"secondary":{"used_percent":20.0,"window_minutes":10080,"resets_in_seconds":100000}}}}"# + "\n"

    private func module(files: [String: String], claude: [String], codex: String?, existing: Set<String> = []) -> AIUsageModule {
        AIUsageModule(claudeDirs: claude, codexSessionsDir: codex,
                      fileSource: InMemoryFileSource(strings: files), directoryExists: { existing.contains($0) })
    }

    func testClaudeCountedOnceAndNoCodexLine() async throws {
        let m = module(files: ["\(claudeDir)/projects/p/a.jsonl": claudeLog, "\(workDir)/projects/p/b.jsonl": ""],
                       claude: [claudeDir, workDir], codex: codexDir, existing: [])
        try await m.refresh()
        let lines = m.lines(at: now)
        XCTAssertEqual(lines.map(\.name), ["Claude", "Claude · Work"])
        XCTAssertEqual(lines[0].value, .tokens(count: 4206 + 14, resetsAt: utc("2026-11-26T18:00:00Z")))
        XCTAssertEqual(m.status, .ok)
        XCTAssertFalse(lines.contains { $0.provider == .codex })
    }

    func testCodexDirWithoutSnapshotIsUnavailableLine() async throws {
        let m = module(files: [:], claude: [], codex: codexDir, existing: [codexDir])
        try await m.refresh()
        let lines = m.lines(at: now)
        XCTAssertEqual(lines.count, 1)
        guard case .unavailable = lines[0].value else { return XCTFail("expected unavailable") }
        XCTAssertFalse(m.status.isAvailable)
        XCTAssertNil(try m.collapsedActivity(at: now))
    }

    func testCollapsedTokensOnly() async throws {
        let m = module(files: ["\(claudeDir)/projects/p/a.jsonl": claudeLog], claude: [claudeDir], codex: nil)
        try await m.refresh()
        let activity = try XCTUnwrap(m.collapsedActivity(at: now))
        XCTAssertEqual(activity.text, "Claude 4.2K")
        XCTAssertNil(activity.usageFraction)
        XCTAssertEqual(activity.source, .aiUsage)
        XCTAssertEqual(activity.accessibilityLabel,
                       "Claude, 5-hour session, 4.2 thousand tokens used, resets in 4 hours")
    }

    func testCollapsedPrefersCodexLimits() async throws {
        let m = module(files: ["\(claudeDir)/projects/p/a.jsonl": claudeLog,
                               "\(codexDir)/2026/11/26/rollout-1.jsonl": codexLog],
                       claude: [claudeDir], codex: codexDir, existing: [codexDir])
        try await m.refresh()
        let activity = try XCTUnwrap(m.collapsedActivity(at: now))
        XCTAssertEqual(activity.text, "84%")
        XCTAssertEqual(try XCTUnwrap(activity.usageFraction), 0.84, accuracy: 0.0001)
        XCTAssertEqual(m.lines(at: now).map(\.provider), [.claude, .codex])
    }

    func testNoActivityWithoutData() async throws {
        let m = module(files: ["\(claudeDir)/projects/p/a.jsonl": ""], claude: [claudeDir], codex: nil)
        try await m.refresh()
        XCTAssertNil(try m.collapsedActivity(at: utc("2026-11-27T14:00:00Z")))
    }
}

/// Records reads; modification dates and sizes are settable (absent mtime = unknown).
private final class CacheTestSource: FileSource, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: String]
    private var mtimes: [String: Date] = [:]
    private var log: [String] = []

    init(_ files: [String: String]) {
        self.files = files
        for path in files.keys { mtimes[path] = Date(timeIntervalSince1970: 1_000) }
    }

    var reads: [String] { lock.lock(); defer { lock.unlock() }; return log.sorted() }
    func resetReads() { lock.lock(); log = []; lock.unlock() }
    func setMtime(_ path: String, _ date: Date?) { lock.lock(); mtimes[path] = date; lock.unlock() }
    func remove(_ path: String) { lock.lock(); files[path] = nil; mtimes[path] = nil; lock.unlock() }

    func files(under directory: String, suffix: String) throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        return files.keys.filter { $0.hasPrefix(directory + "/") && $0.hasSuffix(suffix) }.sorted()
    }

    func read(_ path: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        log.append(path)
        guard let text = files[path] else { throw FileSourceError("missing") }
        return Data(text.utf8)
    }

    func modificationDate(_ path: String) -> Date? { lock.lock(); defer { lock.unlock() }; return mtimes[path] }
    func size(_ path: String) -> Int? { lock.lock(); defer { lock.unlock() }; return files[path]?.utf8.count }
}

final class ClaudeLogCacheTests: XCTestCase {
    private let dir = "/h/.claude"
    private let a = "/h/.claude/projects/p/a.jsonl"
    private let b = "/h/.claude/projects/p/b.jsonl"

    private func line(_ id: String, _ time: String, input: Int) -> String {
        #"{"type":"assistant","timestamp":"\#(time)","requestId":"r_\#(id)","message":{"id":"m_\#(id)","usage":{"input_tokens":\#(input),"output_tokens":0}}}"# + "\n"
    }

    private func report(_ r: UsageResult<ClaudeUsageReport>) throws -> ClaudeUsageReport {
        guard case .available(let report) = r else { throw FileSourceError("unavailable") }
        return report
    }

    private func total(_ r: ClaudeUsageReport) -> Int { r.entries.reduce(0) { $0 + $1.tokens.total } }

    private func makeSource() -> CacheTestSource {
        CacheTestSource([a: line("1", "2026-11-26T13:00:00Z", input: 10), b: line("2", "2026-11-26T13:10:00Z", input: 20)])
    }

    func testUnchangedFilesAreNotReadAgain() throws {
        let source = makeSource()
        let cache = ClaudeLogCache()
        let first = try report(ClaudeLogParser.parse(configDir: dir, source: source, cache: cache))
        XCTAssertEqual(source.reads, [a, b])
        source.resetReads()
        let second = try report(ClaudeLogParser.parse(configDir: dir, source: source, cache: cache))
        XCTAssertEqual(source.reads, [])
        XCTAssertEqual(first, second)
        XCTAssertEqual(total(second), 30)
    }

    func testChangedMtimeRereadsOnlyThatFile() throws {
        let source = makeSource()
        let cache = ClaudeLogCache()
        _ = ClaudeLogParser.parse(configDir: dir, source: source, cache: cache)
        source.resetReads()
        source.setMtime(b, Date(timeIntervalSince1970: 2_000))
        _ = ClaudeLogParser.parse(configDir: dir, source: source, cache: cache)
        XCTAssertEqual(source.reads, [b])
    }

    func testUnknownMtimeIsAlwaysRead() throws {
        let source = makeSource()
        source.setMtime(a, nil)
        let cache = ClaudeLogCache()
        _ = ClaudeLogParser.parse(configDir: dir, source: source, cache: cache)
        source.resetReads()
        _ = ClaudeLogParser.parse(configDir: dir, source: source, cache: cache)
        XCTAssertEqual(source.reads, [a])
    }

    func testDedupeAcrossFilesWithOneFromCache() throws {
        let dup = line("1", "2026-11-26T13:00:00Z", input: 10)
        let source = CacheTestSource([a: dup, b: dup])
        let cache = ClaudeLogCache()
        _ = ClaudeLogParser.parse(configDir: dir, source: source, cache: cache)
        source.resetReads()
        source.setMtime(b, Date(timeIntervalSince1970: 2_000))
        let r = try report(ClaudeLogParser.parse(configDir: dir, source: source, cache: cache))
        XCTAssertEqual(source.reads, [b])
        XCTAssertEqual(r.entries.count, 1)
        XCTAssertEqual(total(r), 10)
        XCTAssertEqual(r.duplicatesDropped, 1)
    }

    func testRemovedFileDropsOut() throws {
        let source = makeSource()
        let cache = ClaudeLogCache()
        _ = ClaudeLogParser.parse(configDir: dir, source: source, cache: cache)
        source.remove(b)
        let r = try report(ClaudeLogParser.parse(configDir: dir, source: source, cache: cache))
        XCTAssertEqual(total(r), 10)
    }
}
