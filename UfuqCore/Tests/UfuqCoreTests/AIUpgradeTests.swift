import XCTest
@testable import UfuqCore
#if canImport(SQLite3)
import SQLite3
#endif

final class AIUpgradeTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testClaudeCostByModelFamily() {
        let sonnet = ClaudeUsageEntry(
            timestamp: base,
            model: "claude-sonnet-4-5-20250929",
            tokens: TokenCounts(input: 1_000_000, output: 100_000, cacheCreation: 0, cacheRead: 1_000_000)
        )
        // 1M * $3 + 0.1M * $15 + 1M * $0.30 = $4.80
        XCTAssertEqual(ClaudeCost.costUSD(for: sonnet), 4.80, accuracy: 0.001)
        XCTAssertEqual(ClaudeCost.formatUSD(4.80), "~$4.80")
        XCTAssertEqual(ClaudeCost.spokenUSD(4.80), "4 dollars 80 cents")

        let opus = ClaudeUsageEntry(
            timestamp: base,
            model: "claude-opus-4-6",
            tokens: TokenCounts(input: 1_000_000, output: 0, cacheCreation: 0, cacheRead: 0)
        )
        XCTAssertEqual(ClaudeCost.costUSD(for: opus), 5.00, accuracy: 0.001)
    }

    func testClaudePaceUsesBurnRateMinimumSpan() {
        let resetsAt = base.addingTimeInterval(5 * 3600)
        let tooShort = [
            ClaudeUsageEntry(timestamp: base, model: nil, tokens: TokenCounts(input: 100_000)),
            ClaudeUsageEntry(timestamp: base.addingTimeInterval(60), model: nil, tokens: TokenCounts(input: 100_000)),
        ]
        XCTAssertNil(ClaudePace.tokensPerHour(entries: tooShort, resetsAt: resetsAt))

        // 0 -> 100k, +15m -> +250k, +30m -> +250k => linear 1M/hr over the 30 min window
        let steady = [
            ClaudeUsageEntry(timestamp: base, model: nil, tokens: TokenCounts(input: 100_000)),
            ClaudeUsageEntry(timestamp: base.addingTimeInterval(15 * 60), model: nil, tokens: TokenCounts(input: 250_000)),
            ClaudeUsageEntry(timestamp: base.addingTimeInterval(30 * 60), model: nil, tokens: TokenCounts(input: 250_000)),
        ]
        let pace = ClaudePace.tokensPerHour(entries: steady, resetsAt: resetsAt)
        XCTAssertNotNil(pace)
        XCTAssertEqual(pace ?? 0, 1_000_000, accuracy: 10_000)
    }

    func testDecodeGenMetadataTokensHandlesValidAndCorruptBlobs() {
        // Construct minimal f1.f4 message:
        // f4 (tag 0x22) -> { f1=1500 (0x08 0xdc 0x0b), f2=500 (0x10 0xf4 0x03), f3=200 (0x18 0xc8 0x01), f5=100 (0x28 0x64) }
        // Wrapped in f1 (tag 0x0a)
        let f4Payload = Data([0x08, 0xdc, 0x0b, 0x10, 0xf4, 0x03, 0x18, 0xc8, 0x01, 0x28, 0x64])
        var f1Payload = Data([0x22, UInt8(f4Payload.count)])
        f1Payload.append(f4Payload)
        var blob = Data([0x0a, UInt8(f1Payload.count)])
        blob.append(f1Payload)

        XCTAssertEqual(AntigravityParser.decodeGenMetadataTokens(blob), 1500 + 500 + 200 + 100)
        XCTAssertEqual(AntigravityParser.decodeGenMetadataTokens(Data([0xff, 0xff, 0x00])), 0)
    }

    func testAntigravityMissingAndSchemaChangedFailCleanly() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ufuq-ag-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Directory exists, but conversation_summaries.db is missing -> .unavailable with isBetaSource
        let missingMod = AIUsageModule(
            claudeDirs: [],
            codexSessionsDir: nil,
            antigravityDir: tmp.path,
            directoryExists: { $0 == tmp.path }
        )
        try await missingMod.refresh()
        let missingLines = missingMod.lines(at: base)
        XCTAssertEqual(missingLines.count, 1)
        XCTAssertEqual(missingLines[0].provider, .antigravity)
        XCTAssertTrue(missingLines[0].isBetaSource)
        guard case .unavailable = missingLines[0].value else {
            return XCTFail("Expected unavailable when DB missing")
        }

        #if canImport(SQLite3)
        // Wrong schema in conversation_summaries.db -> .unavailable cleanly
        let dbPath = tmp.appendingPathComponent("conversation_summaries.db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbPath, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE wrong_table (id TEXT);", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let badSchemaMod = AIUsageModule(
            claudeDirs: [],
            codexSessionsDir: nil,
            antigravityDir: tmp.path,
            directoryExists: { $0 == tmp.path }
        )
        try await badSchemaMod.refresh()
        let badLines = badSchemaMod.lines(at: base)
        XCTAssertEqual(badLines.count, 1)
        XCTAssertTrue(badLines[0].isBetaSource)
        guard case .unavailable = badLines[0].value else {
            return XCTFail("Expected unavailable when schema changed")
        }
        #endif
    }

    func testClaudeWeeklyTokensAndCostInAIUsageModule() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ufuq-claude-weekly-\(UUID().uuidString)")
        let proj = tmp.appendingPathComponent("projects/demo")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let now = Date(timeIntervalSince1970: 1_700_600_000)
        let iso = ISO8601DateFormatter()
        let in5h = iso.string(from: now.addingTimeInterval(-30 * 60))       // 30 min ago (in 5h + 7d)
        let in7d = iso.string(from: now.addingTimeInterval(-2 * 24 * 3600)) // 2 days ago (only in 7d)
        let old = iso.string(from: now.addingTimeInterval(-9 * 24 * 3600))  // 9 days ago (excluded)

        let jsonl = """
        {"type":"assistant","timestamp":"\(in5h)","requestId":"r1","message":{"id":"m1","model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":1000000,"output_tokens":0}}}
        {"type":"assistant","timestamp":"\(in7d)","requestId":"r2","message":{"id":"m2","model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":2000000,"output_tokens":0}}}
        {"type":"assistant","timestamp":"\(old)","requestId":"r3","message":{"id":"m3","model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":5000000,"output_tokens":0}}}
        """
        try jsonl.data(using: .utf8)!.write(to: proj.appendingPathComponent("session.jsonl"))

        let mod = AIUsageModule(claudeDirs: [tmp.path], codexSessionsDir: nil)
        try await mod.refresh()
        let lines = mod.lines(at: now)
        XCTAssertEqual(lines.count, 1)
        if case .tokens(let count, _) = lines[0].value {
            XCTAssertEqual(count, 1_000_000)
        } else {
            XCTFail("Expected token count for Claude")
        }
        XCTAssertEqual(lines[0].weeklyTokens, 3_000_000)
        XCTAssertEqual(lines[0].weeklyEstimatedCostUSD ?? 0, 9.0, accuracy: 0.001)
    }

    #if canImport(SQLite3)
    func testAntigravitySeparates5HourAndWeeklyTokens() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ufuq-ag-weekly-\(UUID().uuidString)")
        let convDir = tmp.appendingPathComponent("conversations")
        try FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let now = Date(timeIntervalSince1970: 1_700_600_000)
        let recentTs = Int64(now.addingTimeInterval(-3600).timeIntervalSince1970)        // 1h ago
        let weekTs = Int64(now.addingTimeInterval(-2 * 24 * 3600).timeIntervalSince1970) // 2d ago
        let oldTs = Int64(now.addingTimeInterval(-10 * 24 * 3600).timeIntervalSince1970) // 10d ago

        let summaryPath = tmp.appendingPathComponent("conversation_summaries.db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(summaryPath, &db), SQLITE_OK)
        let createSQL = "CREATE TABLE conversation_summaries (conversation_id TEXT, status TEXT, last_modified_time INTEGER, killed INTEGER);"
        XCTAssertEqual(sqlite3_exec(db, createSQL, nil, nil, nil), SQLITE_OK)
        let insertSQL = """
            INSERT INTO conversation_summaries VALUES
            ('c-5h', 'CASCADE_RUN_STATUS_IDLE', \(recentTs), 0),
            ('c-7d', 'CASCADE_RUN_STATUS_IDLE', \(weekTs), 0),
            ('c-old', 'CASCADE_RUN_STATUS_IDLE', \(oldTs), 0);
            """
        XCTAssertEqual(sqlite3_exec(db, insertSQL, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        // Helper blob: f1.f4.f1 = 1500 tokens
        func writeConv(_ id: String, tokens: UInt64) throws {
            var f4 = Data([0x08])
            var v = tokens
            while true {
                let b = UInt8(v & 0x7F)
                v >>= 7
                if v == 0 { f4.append(b); break }
                f4.append(b | 0x80)
            }
            var f1 = Data([0x22, UInt8(f4.count)])
            f1.append(f4)
            var blob = Data([0x0a, UInt8(f1.count)])
            blob.append(f1)

            var cdb: OpaquePointer?
            let cpath = convDir.appendingPathComponent("\(id).db").path
            XCTAssertEqual(sqlite3_open(cpath, &cdb), SQLITE_OK)
            XCTAssertEqual(sqlite3_exec(cdb, "CREATE TABLE gen_metadata (data BLOB);", nil, nil, nil), SQLITE_OK)
            var stmt: OpaquePointer?
            XCTAssertEqual(sqlite3_prepare_v2(cdb, "INSERT INTO gen_metadata VALUES (?);", -1, &stmt, nil), SQLITE_OK)
            blob.withUnsafeBytes { raw in
                _ = sqlite3_bind_blob(stmt, 1, raw.baseAddress, Int32(blob.count), nil)
                XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE)
            }
            sqlite3_finalize(stmt)
            sqlite3_close(cdb)
        }

        try writeConv("c-5h", tokens: 1500)
        try writeConv("c-7d", tokens: 3000)
        try writeConv("c-old", tokens: 9000)

        let result = AntigravityParser.parse(configDir: tmp.path, now: now)
        guard case .available(let report) = result else {
            return XCTFail("Expected available Antigravity report")
        }
        XCTAssertEqual(report.tokens, 1500)
        XCTAssertEqual(report.weeklyTokens, 4500)
        XCTAssertEqual(report.recentCount, 1)
    }
    #endif
}
