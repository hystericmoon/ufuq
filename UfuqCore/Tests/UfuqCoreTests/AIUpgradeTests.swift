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
}
