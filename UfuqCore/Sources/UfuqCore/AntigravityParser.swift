import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

public struct AntigravityUsageReport: Equatable, Sendable {
    public var tokens: Int
    public var activeCount: Int
    public var recentCount: Int
    public var resetsAt: Date?

    public init(tokens: Int, activeCount: Int, recentCount: Int, resetsAt: Date? = nil) {
        self.tokens = tokens
        self.activeCount = activeCount
        self.recentCount = recentCount
        self.resetsAt = resetsAt
    }
}

/// Reads local Antigravity SQLite state read-only without touching any secrets or auth files.
///
/// Fragile undocumented source ("Beta source"): any missing file, unreadable DB, or schema change
/// returns `.unavailable` instead of throwing or crashing.
public enum AntigravityParser {
    public static let windowLength: TimeInterval = 5 * 3600

    public static func defaultConfigDir(home: String = NSHomeDirectory()) -> String {
        URL(fileURLWithPath: home).appendingPathComponent(".gemini/antigravity").path
    }

    public static func parse(
        configDir: String = defaultConfigDir(),
        now: Date = Date()
    ) -> UsageResult<AntigravityUsageReport> {
        #if canImport(SQLite3)
        let summaryPath = URL(fileURLWithPath: configDir)
            .appendingPathComponent("conversation_summaries.db").path
        guard FileManager.default.fileExists(atPath: summaryPath) else {
            return .unavailable(reason: "Antigravity summary DB missing")
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(summaryPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return .unavailable(reason: "Cannot open Antigravity DB")
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT conversation_id, status, last_modified_time
            FROM conversation_summaries
            WHERE COALESCE(killed, 0) = 0
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return .unavailable(reason: "Antigravity schema changed")
        }
        defer { sqlite3_finalize(stmt) }

        let cutoff = now.addingTimeInterval(-windowLength)
        var activeCount = 0
        var recentIDs: [String] = []
        var earliestRecent: Date?

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(stmt, 0) else { continue }
            let convID = String(cString: idC)
            let status = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            if status == "CASCADE_RUN_STATUS_RUNNING" {
                activeCount += 1
            }
            if let modDate = columnDate(stmt, index: 2), modDate >= cutoff {
                recentIDs.append(convID)
                if earliestRecent == nil || modDate < earliestRecent! {
                    earliestRecent = modDate
                }
            }
        }

        let convDir = URL(fileURLWithPath: configDir).appendingPathComponent("conversations")
        var totalTokens = 0
        for convID in recentIDs {
            let convPath = convDir.appendingPathComponent("\(convID).db").path
            totalTokens = saturatingAdd(totalTokens, readConversationTokens(at: convPath))
        }

        let resetsAt = earliestRecent?.addingTimeInterval(windowLength)
        return .available(AntigravityUsageReport(
            tokens: totalTokens,
            activeCount: activeCount,
            recentCount: recentIDs.count,
            resetsAt: resetsAt
        ))
        #else
        return .unavailable(reason: "Antigravity reader requires macOS SQLite")
        #endif
    }

    #if canImport(SQLite3)
    private static func columnDate(_ stmt: OpaquePointer, index: Int32) -> Date? {
        let type = sqlite3_column_type(stmt, index)
        if type == SQLITE_INTEGER || type == SQLITE_FLOAT {
            let raw = sqlite3_column_double(stmt, index)
            // Normalize milliseconds/microseconds if stored larger than ~year 3000 in seconds.
            let seconds = raw > 1e14 ? raw / 1e6 : (raw > 1e11 ? raw / 1e3 : raw)
            return Date(timeIntervalSince1970: seconds)
        }
        if type == SQLITE_TEXT, let textC = sqlite3_column_text(stmt, index) {
            let str = String(cString: textC)
            if let num = Double(str) {
                let seconds = num > 1e14 ? num / 1e6 : (num > 1e11 ? num / 1e3 : num)
                return Date(timeIntervalSince1970: seconds)
            }
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: str) { return d }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: str)
        }
        return nil
    }

    private static func readConversationTokens(at path: String) -> Int {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return 0
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT data FROM gen_metadata", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }

        var total = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(stmt, 0) else { continue }
            let count = Int(sqlite3_column_bytes(stmt, 0))
            guard count > 0 else { continue }
            let data = Data(bytes: bytes, count: count)
            total = saturatingAdd(total, decodeGenMetadataTokens(data))
        }
        return total
    }
    #endif

    /// Decodes `f1.f4` token fields (`f1` base, `f2` input, `f3` output, `f5` cached) from a
    /// `gen_metadata.data` protobuf blob. Returns 0 on any unexpected wire structure.
    static func decodeGenMetadataTokens(_ data: Data) -> Int {
        var total = 0
        for (field, wireType, payload) in ProtoWire.fields(in: data) {
            guard field == 1, wireType == 2 else { continue }
            for (subField, subWire, subPayload) in ProtoWire.fields(in: payload) {
                guard subField == 4, subWire == 2 else { continue }
                for (tokField, tokWire, tokVal) in ProtoWire.varints(in: subPayload) where tokWire == 0 {
                    if tokField == 1 || tokField == 2 || tokField == 3 || tokField == 5 {
                        total = saturatingAdd(total, Int(clamping: tokVal))
                    }
                }
            }
        }
        return total
    }

    private static func saturatingAdd(_ a: Int, _ b: Int) -> Int {
        let (sum, overflow) = a.addingReportingOverflow(b)
        return overflow ? Int.max : sum
    }
}

private enum ProtoWire {
    static func fields(in data: Data) -> [(field: Int, wireType: Int, payload: Data)] {
        var out: [(Int, Int, Data)] = []
        var idx = data.startIndex
        while idx < data.endIndex {
            guard let (tag, next) = readVarint(data, from: idx) else { break }
            idx = next
            let field = Int(tag >> 3)
            let wire = Int(tag & 0x07)
            switch wire {
            case 0:
                guard let (_, after) = readVarint(data, from: idx) else { return out }
                idx = after
            case 1:
                guard idx + 8 <= data.endIndex else { return out }
                idx += 8
            case 2:
                guard let (len, start) = readVarint(data, from: idx), len <= UInt64(data.endIndex - start) else {
                    return out
                }
                let end = start + Int(len)
                out.append((field, wire, data[start..<end]))
                idx = end
            case 5:
                guard idx + 4 <= data.endIndex else { return out }
                idx += 4
            default:
                return out
            }
        }
        return out
    }

    static func varints(in data: Data) -> [(field: Int, wireType: Int, value: UInt64)] {
        var out: [(Int, Int, UInt64)] = []
        var idx = data.startIndex
        while idx < data.endIndex {
            guard let (tag, next) = readVarint(data, from: idx) else { break }
            idx = next
            let field = Int(tag >> 3)
            let wire = Int(tag & 0x07)
            switch wire {
            case 0:
                guard let (val, after) = readVarint(data, from: idx) else { return out }
                out.append((field, wire, val))
                idx = after
            case 1:
                guard idx + 8 <= data.endIndex else { return out }
                idx += 8
            case 2:
                guard let (len, start) = readVarint(data, from: idx), len <= UInt64(data.endIndex - start) else {
                    return out
                }
                idx = start + Int(len)
            case 5:
                guard idx + 4 <= data.endIndex else { return out }
                idx += 4
            default:
                return out
            }
        }
        return out
    }

    private static func readVarint(_ data: Data, from start: Data.Index) -> (UInt64, Data.Index)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var idx = start
        while idx < data.endIndex {
            let byte = data[idx]
            idx = data.index(after: idx)
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 { return (result, idx) }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }
}
