import XCTest
@testable import UfuqCore

private func fixture(_ path: String) -> String {
    Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(path)").path
}

private func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

final class ClaudeLogParserTests: XCTestCase {
    func testNormalFixtureDedupesSkipsAndBlocks() throws {
        let report = try XCTUnwrap(ClaudeLogParser.parse(configDir: fixture("claude/normal")).value)
        XCTAssertEqual(report.filesRead, 2)
        XCTAssertEqual(report.entries.count, 5)
        XCTAssertEqual(report.duplicatesDropped, 2)
        XCTAssertEqual(report.skippedLines, 2) // garbage line + bad timestamp
        XCTAssertEqual(report.blocks.count, 4)

        let block = try XCTUnwrap(report.currentBlock(at: utc("2026-11-26T12:00:00Z")))
        XCTAssertEqual(block.start, utc("2026-11-26T10:00:00Z"))
        XCTAssertEqual(block.end, utc("2026-11-26T15:00:00Z"))
        XCTAssertEqual(block.messageCount, 2)
        // msg_1 keeps the fullest streamed copy (10+50+100), msg_2 is 20+30+1000.
        XCTAssertEqual(block.tokens, TokenCounts(input: 30, output: 80, cacheCreation: 100, cacheRead: 1000))
        XCTAssertNil(report.currentBlock(at: utc("2026-11-26T15:30:00Z")))
        XCTAssertEqual(report.currentBlock(at: utc("2026-11-26T17:00:00Z"))?.tokens.total, 10)
    }

    func testWeeklyWindowIsRolling() throws {
        let report = try XCTUnwrap(ClaudeLogParser.parse(configDir: fixture("claude/normal")).value)
        // 11-20 entry is inside the 7 days, 11-10 is not.
        XCTAssertEqual(report.weeklyTokens(at: utc("2026-11-26T17:00:00Z")).total, 1000 + 1210 + 10)
        // A day later, 11-20 09:00 has aged out.
        XCTAssertEqual(report.weeklyTokens(at: utc("2026-11-27T10:00:00Z")).total, 1210 + 10)
    }

    func testMissingDirIsUnavailable() {
        let result = ClaudeLogParser.parse(configDir: fixture("claude/does-not-exist"))
        guard case .unavailable(let reason) = result else { return XCTFail("expected unavailable") }
        XCTAssertFalse(reason.isEmpty)
        XCTAssertFalse(result.status.isAvailable)
    }

    func testEmptyFileIsAvailableWithNoData() throws {
        let report = try XCTUnwrap(ClaudeLogParser.parse(configDir: fixture("claude/empty")).value)
        XCTAssertTrue(report.entries.isEmpty)
        XCTAssertTrue(report.blocks.isEmpty)
        XCTAssertNil(report.currentBlock(at: Date()))
    }

    func testBinaryGarbageIsUnavailableNotACrash() {
        guard case .unavailable = ClaudeLogParser.parse(configDir: fixture("claude/garbage")) else {
            return XCTFail("expected unavailable")
        }
    }

    func testGapOverFiveHoursStartsNewBlockEvenInsideWindow() {
        let a = #"{"type":"assistant","timestamp":"2026-11-26T10:00:00Z","requestId":"a","message":{"id":"1","usage":{"input_tokens":1}}}"#
        let b = #"{"type":"assistant","timestamp":"2026-11-26T14:59:00Z","requestId":"b","message":{"id":"2","usage":{"input_tokens":1}}}"#
        let c = #"{"type":"assistant","timestamp":"2026-11-26T15:01:00Z","requestId":"c","message":{"id":"3","usage":{"input_tokens":1}}}"#
        let report = ClaudeLogParser.parse(files: [Data([a, b, c].joined(separator: "\n").utf8)]).value
        XCTAssertEqual(report?.blocks.map(\.messageCount), [2, 1])
    }

    func testInMemorySourceAndUnreadableFiles() {
        let line = #"{"type":"assistant","timestamp":"2026-11-26T10:00:00Z","requestId":"a","message":{"id":"1","usage":{"output_tokens":7}}}"#
        let ok = InMemoryFileSource(
            files: ["/c/projects/p/a.jsonl": Data(line.utf8)], unreadable: ["/c/projects/p/b.jsonl"])
        let report = ClaudeLogParser.parse(configDir: "/c", source: ok).value
        XCTAssertEqual(report?.filesFailed, 1)
        XCTAssertEqual(report?.entries.first?.tokens.output, 7)

        let allBad = InMemoryFileSource(unreadable: ["/c/projects/p/b.jsonl"])
        guard case .unavailable = ClaudeLogParser.parse(configDir: "/c", source: allBad) else {
            return XCTFail("expected unavailable")
        }
        guard case .unavailable = ClaudeLogParser.parse(configDir: "/nowhere", source: InMemoryFileSource()) else {
            return XCTFail("expected unavailable")
        }
    }

    func testDefaultConfigDir() {
        XCTAssertEqual(ClaudeLogParser.defaultConfigDir(environment: ["CLAUDE_CONFIG_DIR": "/x"], home: "/h"), "/x")
        XCTAssertEqual(ClaudeLogParser.defaultConfigDir(environment: [:], home: "/h"), "/h/.claude")
    }
}

final class CodexParserTests: XCTestCase {
    func testLatestSnapshotAcrossFiles() throws {
        let limits = try XCTUnwrap(CodexParser.parse(sessionsDir: fixture("codex/normal")).value)
        XCTAssertEqual(limits.capturedAt, utc("2026-11-26T10:30:00Z"))
        let session = try XCTUnwrap(limits.readings.first { $0.kind == .session5h })
        XCTAssertEqual(session.snapshot.fraction, 0.42, accuracy: 1e-9)
        XCTAssertEqual(session.snapshot.resetsAt, utc("2026-11-26T10:30:00Z").addingTimeInterval(1234))
        XCTAssertFalse(session.isEstimated)
        let weekly = try XCTUnwrap(limits.readings.first { $0.kind == .weekly })
        XCTAssertEqual(weekly.snapshot.fraction, 0.10, accuracy: 1e-9)
        XCTAssertEqual(UsageSummary.worstPercent(of: limits.readings), 42)
    }

    func testResetsAtEpochAndMissingWindowMinutes() throws {
        let limits = try XCTUnwrap(CodexParser.parse(sessionsDir: fixture("codex/alt")).value)
        XCTAssertEqual(limits.readings.count, 2)
        XCTAssertEqual(limits.readings[0].snapshot.resetsAt, Date(timeIntervalSince1970: 1_796_000_000))
        XCTAssertEqual(limits.readings[1].kind, .weekly) // falls back to secondary = weekly
        XCTAssertNil(limits.readings[1].snapshot.resetsAt)
    }

    func testMissingRateLimitsIsUnavailable() {
        guard case .unavailable(let reason) = CodexParser.parse(sessionsDir: fixture("codex/norate")) else {
            return XCTFail("expected unavailable")
        }
        XCTAssertTrue(reason.contains("rate-limit"))
    }

    func testGarbageAndMissingDirAreUnavailable() {
        guard case .unavailable = CodexParser.parse(sessionsDir: fixture("codex/garbage")) else {
            return XCTFail("expected unavailable")
        }
        guard case .unavailable = CodexParser.parse(sessionsDir: fixture("codex/nope")) else {
            return XCTFail("expected unavailable")
        }
    }

    func testWindowMinutesClassifyKind() {
        XCTAssertEqual(CodexParser.kind(forMinutes: 300), .session5h)
        XCTAssertEqual(CodexParser.kind(forMinutes: 10080), .weekly)
    }

    func testNonRolloutFilesIgnoredAndEmptyDirUnavailable() {
        let src = InMemoryFileSource(strings: ["/s/2026/11/26/notes.jsonl": "{}"])
        guard case .unavailable = CodexParser.parse(sessionsDir: "/s", source: src) else {
            return XCTFail("expected unavailable")
        }
    }
}

final class UsageModelTests: XCTestCase {
    private func reading(_ kind: UsageWindowKind, _ f: Double) -> UsageWindowReading {
        UsageWindowReading(kind: kind, snapshot: UsageSnapshot(fraction: f, capturedAt: Date(timeIntervalSince1970: 0)))
    }

    func testWorstFraction() {
        let readings = [reading(.session5h, 0.4), reading(.weekly, 0.874), reading(.modelGroup("Gemini"), 0.1)]
        XCTAssertEqual(UsageSummary.worstFraction(of: readings), 0.874)
        XCTAssertEqual(UsageSummary.worst(of: readings)?.kind, .weekly)
        XCTAssertEqual(UsageSummary.worstPercent(of: readings), 87)
        XCTAssertNil(UsageSummary.worstFraction(of: []))
        XCTAssertEqual(UsageSummary.worstFraction(of: [reading(.weekly, 1.7)]), 1)
        XCTAssertNil(UsageSummary.worst(of: [reading(.weekly, .nan)]))
    }

    func testEstimateIsLabelledEstimated() throws {
        let report = try XCTUnwrap(ClaudeLogParser.parse(configDir: fixture("claude/normal")).value)
        let est = UsageEstimate(sessionBudgetTokens: 2420, weeklyBudgetTokens: 4440)
        let readings = est.readings(from: report, at: utc("2026-11-26T12:00:00Z"))
        XCTAssertEqual(readings.count, 2)
        XCTAssertTrue(readings.allSatisfy(\.isEstimated))
        XCTAssertEqual(readings[0].snapshot.fraction, 0.5, accuracy: 1e-9)
        XCTAssertEqual(readings[0].snapshot.resetsAt, utc("2026-11-26T15:00:00Z"))
    }

    func testResolverPrefersLiveThenEstimateThenUnavailable() async {
        let account = UsageAccount(id: "a", provider: .claude, displayName: "Work", configDir: fixture("claude/normal"))
        let est = UsageEstimate(sessionBudgetTokens: 1000, weeklyBudgetTokens: 1000)
        let now = utc("2026-11-26T12:00:00Z")
        let liveReading = reading(.session5h, 0.3)

        let live = await ClaudeUsageResolver.readings(
            for: account, live: FakeClaudeLimitSource(result: .success([liveReading])), estimate: est, now: now)
        XCTAssertEqual(live.value, [liveReading])

        struct Boom: Error {}
        let fallback = await ClaudeUsageResolver.readings(
            for: account, live: FakeClaudeLimitSource(result: .failure(Boom())), estimate: est, now: now)
        XCTAssertEqual(fallback.value?.allSatisfy(\.isEstimated), true)

        let broken = UsageAccount(id: "b", provider: .claude, displayName: "Gone", configDir: fixture("claude/nope"))
        let none = await ClaudeUsageResolver.readings(for: broken, live: nil, estimate: est, now: now)
        XCTAssertFalse(none.status.isAvailable)
    }
}

final class UsageHardeningTests: XCTestCase {
    private func line(_ id: String, _ ts: String = "2026-11-26T10:00:00Z", out: String = "1", req: String? = nil) -> String {
        let r = req.map { #""requestId":"\#($0)","# } ?? ""
        return #"{"type":"assistant","timestamp":"\#(ts)",\#(r)"message":{"id":"\#(id)","usage":{"output_tokens":\#(out)}}}"#
    }

    private func tempDir() throws -> String {
        let dir = NSTemporaryDirectory() + "ufuq-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    func testTokenArithmeticSaturatesInsteadOfTrapping() {
        let big = TokenCounts(input: Int.max, output: Int.max, cacheCreation: Int.max, cacheRead: Int.max)
        XCTAssertEqual(big.total, Int.max)
        XCTAssertEqual((big + big).input, Int.max)
    }

    func testHugeTokenValuesDoNotOverflowAcrossManyEntries() throws {
        let lines = (0..<20_000).map { line("m\($0)", out: "999999999999999") }
        let report = try XCTUnwrap(ClaudeLogParser.parse(files: [Data(lines.joined(separator: "\n").utf8)]).value)
        XCTAssertEqual(report.blocks.first?.tokens.output, Int.max)
        _ = report.weeklyTokens(at: utc("2026-11-26T12:00:00Z")).total
    }

    func testPartialLastLineIsNotCountedAsCorruption() throws {
        let data = Data((line("a") + "\n" + #"{"type":"assistant","timestamp":"2026-11-26T10:0"#).utf8)
        let report = try XCTUnwrap(ClaudeLogParser.parse(files: [data]).value)
        XCTAssertEqual(report.skippedLines, 0)
        XCTAssertEqual(report.entries.count, 1)
        // A file that is only a half-written first line is empty, not "unavailable".
        let only = Data(#"{"type":"assist"#.utf8)
        XCTAssertNotNil(ClaudeLogParser.parse(files: [only]).value)
    }

    func testCompleteBadLineStillCounted() throws {
        let data = Data((line("a") + "\nnot json\n" + line("b")).utf8)
        XCTAssertEqual(ClaudeLogParser.parse(files: [data]).value?.skippedLines, 1)
    }

    func testBOMAndCRLFAreTolerated() throws {
        let data = Data([0xEF, 0xBB, 0xBF] + Array((line("a") + "\r\n" + line("b") + "\r\n").utf8))
        let report = try XCTUnwrap(ClaudeLogParser.parse(files: [data]).value)
        XCTAssertEqual(report.entries.count, 2)
        XCTAssertEqual(report.skippedLines, 0)
    }

    func testDeeplyNestedAndInvalidUTF8LinesDoNotCrash() throws {
        let deep = String(repeating: "[", count: 200_000)
        var bytes = Array((deep + "\n").utf8)
        bytes += [0xFF, 0xFE, 0x7B, 0x0A]
        bytes += Array(line("ok").utf8)
        let report = try XCTUnwrap(ClaudeLogParser.parse(files: [Data(bytes)]).value)
        XCTAssertEqual(report.entries.count, 1)
    }

    func testDedupeKeysDoNotCollideBetweenMessageIdAndRequestId() throws {
        let a = #"{"type":"assistant","timestamp":"2026-11-26T10:00:00Z","message":{"id":"x","usage":{"output_tokens":1}}}"#
        let b = #"{"type":"assistant","timestamp":"2026-11-26T10:00:01Z","requestId":"x","message":{"usage":{"output_tokens":1}}}"#
        let report = try XCTUnwrap(ClaudeLogParser.parse(files: [Data([a, b].joined(separator: "\n").utf8)]).value)
        XCTAssertEqual(report.entries.count, 2)
    }

    func testEpochTimestampsAreAccepted() throws {
        XCTAssertEqual(JSONLines.date(1_796_000_000), Date(timeIntervalSince1970: 1_796_000_000))
        XCTAssertEqual(JSONLines.date(1_796_000_000_000), Date(timeIntervalSince1970: 1_796_000_000))
        XCTAssertNil(JSONLines.date(Double.nan))
        XCTAssertNil(JSONLines.date(-5))
        XCTAssertEqual(JSONLines.date("2026-11-26T17:00:00+07:00"), utc("2026-11-26T10:00:00Z"))
    }

    func testDirectoryNamedLikeLogIsNotAFailedFile() throws {
        let dir = try tempDir()
        let proj = dir + "/projects/p"
        try FileManager.default.createDirectory(atPath: proj + "/weird.jsonl", withIntermediateDirectories: true)
        try line("a").write(toFile: proj + "/ok.jsonl", atomically: true, encoding: .utf8)
        let report = try XCTUnwrap(ClaudeLogParser.parse(configDir: dir).value)
        XCTAssertEqual(report.filesFailed, 0)
        XCTAssertEqual(report.filesRead, 1)
    }

    func testTildeConfigDirIsExpanded() throws {
        let home = NSHomeDirectory()
        let name = ".ufuq-test-\(UUID().uuidString)"
        let dir = home + "/" + name
        try FileManager.default.createDirectory(atPath: dir + "/projects", withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        try line("a").write(toFile: dir + "/projects/a.jsonl", atomically: true, encoding: .utf8)
        XCTAssertEqual(ClaudeLogParser.parse(configDir: "~/" + name).value?.entries.count, 1)
    }

    func testOversizedFileIsReadFromItsTailOnWholeLines() throws {
        let dir = try tempDir()
        let path = dir + "/big.jsonl"
        let lines = (0..<200).map { line("m\($0)") }
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        let src = LocalFileSource(maxFileBytes: 2_000)
        let data = try src.read(path)
        XCTAssertLessThanOrEqual(data.count, 2_000)
        let objects = JSONLines.objects(in: data)
        XCTAssertFalse(objects.isEmpty)
        XCTAssertTrue(objects.allSatisfy { $0 != nil }, "tail must start on a line boundary")
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("m199"))
    }

    func testCodexPicksLatestByTimestampNotFileOrder() throws {
        func rollout(_ ts: String, _ pct: Int) -> String {
            #"{"timestamp":"\#(ts)","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":\#(pct),"window_minutes":300}}}}"#
        }
        let src = InMemoryFileSource(strings: [
            "/s/2026/11/26/rollout-b.jsonl": rollout("2026-11-26T08:00:00Z", 10),
            "/s/2026/11/20/rollout-a.jsonl": rollout("2026-11-26T09:00:00Z", 55) + "\n" + rollout("2026-11-26T07:00:00Z", 5),
        ])
        let limits = try XCTUnwrap(CodexParser.parse(sessionsDir: "/s", source: src).value)
        XCTAssertEqual(limits.readings.first?.snapshot.fraction ?? 0, 0.55, accuracy: 1e-9)
    }

    func testCodexResetsAtMillisecondsAndOversizedPercent() throws {
        let l = #"{"timestamp":"2026-11-26T10:00:00Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":"140","window_minutes":300,"resets_at":1796000000000},"secondary":{"used_percent":null}}}}"#
        let limits = try XCTUnwrap(CodexParser.parse(files: [Data(l.utf8)]).value)
        XCTAssertEqual(limits.readings.count, 1)
        XCTAssertEqual(limits.readings[0].snapshot.resetsAt, Date(timeIntervalSince1970: 1_796_000_000))
        XCTAssertEqual(UsageSummary.worstPercent(of: limits.readings), 100)
    }

    func testCodexFutureTimestampDoesNotPinSnapshotForever() throws {
        func rollout(_ ts: String, _ pct: Int) -> String {
            #"{"timestamp":"\#(ts)","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":\#(pct),"window_minutes":300}}}}"#
        }
        let data = Data([rollout("2099-01-01T00:00:00Z", 99), rollout("2026-11-26T10:00:00Z", 20)].joined(separator: "\n").utf8)
        let limits = try XCTUnwrap(CodexParser.parse(files: [data], now: utc("2026-11-26T12:00:00Z")).value)
        XCTAssertEqual(limits.readings.first?.snapshot.fraction ?? 0, 0.20, accuracy: 1e-9)
    }
}
