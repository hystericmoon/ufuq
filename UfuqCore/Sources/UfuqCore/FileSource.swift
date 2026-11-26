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
    public init() {}

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
            result.append((directory as NSString).appendingPathComponent(relative))
        }
        return result.sorted()
    }

    public func read(_ path: String) throws -> Data {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw FileSourceError("file not readable: \(path)")
        }
        return data
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
    /// Splits on newlines; each line is parsed as a JSON object. Invalid lines come back as nil.
    static func objects(in data: Data) -> [[String: Any]?] {
        var out: [[String: Any]?] = []
        for slice in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            let line = Data(slice)
            if line.allSatisfy({ $0 == 0x20 || $0 == 0x0D || $0 == 0x09 }) { continue }
            let obj = try? JSONSerialization.jsonObject(with: line)
            out.append(obj as? [String: Any])
        }
        return out
    }

    static func double(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        double(value).flatMap { $0.isFinite && abs($0) < 1e15 ? Int($0) : nil }
    }

    static func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        return ISO8601DateFormatter().date(from: s)
    }
}
