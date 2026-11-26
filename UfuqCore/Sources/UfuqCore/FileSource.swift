import Foundation

/// Small file-reading seam so parsers run on fixtures or in-memory data in tests.
public protocol FileSource: Sendable {
    /// All files under `directory` (recursive) whose name ends in `suffix`. Throws if the
    /// directory is missing or unreadable.
    func files(under directory: String, suffix: String) throws -> [String]
    func read(_ path: String) throws -> Data
}

public struct FileSourceError: Error, Equatable, CustomStringConvertible {
    public var description: String
    public init(_ description: String) { self.description = description }
}

/// Real disk access.
public struct LocalFileSource: FileSource {
    /// Files larger than this are read from their tail (whole lines only): the newest data is
    /// at the end of an append-only log, and a huge file must not be loaded whole.
    public var maxFileBytes: Int

    public init(maxFileBytes: Int = 256 * 1024 * 1024) { self.maxFileBytes = max(maxFileBytes, 1) }

    public func files(under directory: String, suffix: String) throws -> [String] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue else {
            throw FileSourceError("directory not found: \(directory)")
        }
        guard let enumerator = FileManager.default.enumerator(atPath: directory) else {
            throw FileSourceError("directory not readable: \(directory)")
        }
        var result: [String] = []
        for case let relative as String in enumerator where relative.hasSuffix(suffix) {
            let full = (directory as NSString).appendingPathComponent(relative)
            // Skip directories named like a log and dangling symlinks.
            var entryIsDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: full, isDirectory: &entryIsDir), !entryIsDir.boolValue else { continue }
            result.append(full)
        }
        return result.sorted()
    }

    public func read(_ path: String) throws -> Data {
        // Plain reads, not mmap: a file truncated while mapped would kill the app with SIGBUS.
        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw FileSourceError("file not readable: \(path)")
        }
        defer { try? handle.close() }
        do {
            let size = try handle.seekToEnd()
            let cap = UInt64(maxFileBytes)
            if size <= cap {
                try handle.seek(toOffset: 0)
                guard let data = try handle.read(upToCount: maxFileBytes) else { return Data() }
                return data
            }
            try handle.seek(toOffset: size - cap)
            var data = try handle.read(upToCount: maxFileBytes) ?? Data()
            if let newline = data.firstIndex(of: 0x0A) {
                data = Data(data[data.index(after: newline)...])
            } else {
                data = Data()
            }
            return data
        } catch {
            throw FileSourceError("file not readable: \(path)")
        }
    }
}

/// In-memory files, keyed by full path. A path in `unreadable` throws on read.
public struct InMemoryFileSource: FileSource {
    public var files: [String: Data]
    public var unreadable: Set<String>

    public init(files: [String: Data] = [:], unreadable: Set<String> = []) {
        self.files = files
        self.unreadable = unreadable
    }

    public init(strings: [String: String]) {
        self.init(files: strings.mapValues { Data($0.utf8) })
    }

    public func files(under directory: String, suffix: String) throws -> [String] {
        let prefix = directory.hasSuffix("/") ? directory : directory + "/"
        let all = Set(files.keys).union(unreadable)
        let matches = all.filter { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }
        // A directory that holds nothing and isn't registered is treated as missing.
        if matches.isEmpty, !files.keys.contains(where: { $0.hasPrefix(prefix) }) {
            throw FileSourceError("directory not found: \(directory)")
        }
        return matches.sorted()
    }

    public func read(_ path: String) throws -> Data {
        if unreadable.contains(path) { throw FileSourceError("file not readable: \(path)") }
        guard let data = files[path] else { throw FileSourceError("file not found: \(path)") }
        return data
    }
}

enum JSONLines {
    /// Calls `body` once per non-blank line: the parsed object, or nil if the line is not a JSON
    /// object. A final line with no trailing newline that fails to parse is a write in progress
    /// and is not reported at all.
    static func forEachObject(in data: Data, _ body: ([String: Any]?) -> Void) {
        var data = data
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = Data(data.dropFirst(3)) }
        let endsWithNewline = data.last == 0x0A
        let slices = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        for (i, slice) in slices.enumerated() {
            if slice.allSatisfy({ $0 == 0x20 || $0 == 0x0D || $0 == 0x09 }) { continue }
            let obj: [String: Any]?
            if exceedsDepth(slice) {
                obj = nil
            } else {
                obj = (try? JSONSerialization.jsonObject(with: Data(slice))) as? [String: Any]
            }
            if obj == nil, !endsWithNewline, i == slices.count - 1 { continue }
            body(obj)
        }
    }

    /// Splits on newlines; each line is parsed as a JSON object. Invalid lines come back as nil.
    static func objects(in data: Data) -> [[String: Any]?] {
        var out: [[String: Any]?] = []
        forEachObject(in: data) { out.append($0) }
        return out
    }

    /// Real log lines nest a few levels; refuse pathological nesting before it reaches the parser.
    private static func exceedsDepth(_ line: Data.SubSequence, limit: Int = 128) -> Bool {
        var depth = 0
        var inString = false
        var escaped = false
        for byte in line {
            if inString {
                if escaped { escaped = false } else if byte == 0x5C { escaped = true } else if byte == 0x22 { inString = false }
                continue
            }
            switch byte {
            case 0x22: inString = true
            case 0x5B, 0x7B:
                depth += 1
                if depth > limit { return true }
            case 0x5D, 0x7D: depth -= 1
            default: break
            }
        }
        return false
    }

    static func double(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        double(value).flatMap { $0.isFinite && abs($0) < 1e15 ? Int($0) : nil }
    }

    /// Epoch seconds, or milliseconds when the value is too large to be seconds.
    static func epochDate(_ value: Double) -> Date? {
        guard value.isFinite, value > 0 else { return nil }
        let seconds = value >= 1e11 ? value / 1000 : value
        guard seconds < 1e11 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private nonisolated(unsafe) static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private nonisolated(unsafe) static let plain = ISO8601DateFormatter()

    /// ISO 8601 string (any offset) or epoch number.
    static func date(_ value: Any?) -> Date? {
        if let s = value as? String {
            if let d = withFraction.date(from: s) { return d }
            return plain.date(from: s)
        }
        if let n = value as? NSNumber { return epochDate(n.doubleValue) }
        return nil
    }
}
