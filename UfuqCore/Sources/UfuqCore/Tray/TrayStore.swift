import Foundation

public struct TrayItem: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case file, folder }

    public var id: UUID
    public var path: String
    public var name: String
    public var size: Int?
    public var addedAt: Date
    public var kind: Kind

    public var url: URL { URL(fileURLWithPath: path) }

    public init(id: UUID = UUID(), path: String, name: String? = nil, size: Int? = nil,
                addedAt: Date = Date(), kind: Kind = .file) {
        self.id = id
        self.path = path
        self.name = name ?? (path as NSString).lastPathComponent
        self.size = size
        self.addedAt = addedAt
        self.kind = kind
    }
}

/// `save()` refused because `tray.json` could not be read and must not be overwritten.
public struct TraySaveBlocked: Error, Equatable {}

/// Ordered tray items plus pinned folders, saved as `tray.json` (Application Support/Ufuq).
public final class TrayStore {
    public static let currentVersion = 1

    struct Document: Codable {
        var version: Int
        var items: [TrayItem]
        var pinnedFolders: [String]

        init(version: Int, items: [TrayItem], pinnedFolders: [String]) {
            self.version = version
            self.items = items
            self.pinnedFolders = pinnedFolders
        }

        // Tolerant: a file from an older version may lack keys.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
            items = try c.decodeIfPresent([TrayItem].self, forKey: .items) ?? []
            pinnedFolders = try c.decodeIfPresent([String].self, forKey: .pinnedFolders) ?? []
        }
    }

    public private(set) var items: [TrayItem] = []
    public private(set) var pinnedFolders: [String] = []

    private let reader: () throws -> Data?
    private let writer: (Data) throws -> Void

    /// `reader` returns nil when the file does not exist yet.
    public init(reader: @escaping () throws -> Data?, writer: @escaping (Data) throws -> Void) {
        self.reader = reader
        self.writer = writer
    }

    /// Default location: Application Support `Ufuq/tray.json`.
    public static func defaultPath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Ufuq/tray.json").path
    }

    public convenience init(path: String = TrayStore.defaultPath()) {
        self.init(
            reader: { FileManager.default.contents(atPath: path) },
            writer: { data in
                let url = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            })
    }

    /// True when a file exists but could not be used (corrupt or from a newer version):
    /// `save()` then refuses, so that file is never overwritten.
    public private(set) var saveBlocked = false

    /// Loads from disk. A missing, corrupt or newer-version file leaves the store empty.
    public func load() {
        guard let data = try? reader() else { return }
        guard let doc = try? JSONDecoder.tray.decode(Document.self, from: data),
              doc.version <= Self.currentVersion else { saveBlocked = true; return }
        items = doc.items
        pinnedFolders = doc.pinnedFolders
    }

    public func save() throws {
        if saveBlocked { throw TraySaveBlocked() }
        let doc = Document(version: Self.currentVersion, items: items, pinnedFolders: pinnedFolders)
        try writer(JSONEncoder.tray.encode(doc))
    }

    /// Adds `item` unless its path is already there. Returns whether it was added.
    @discardableResult
    public func add(_ item: TrayItem) -> Bool {
        guard !items.contains(where: { $0.path == item.path }) else { return false }
        items.append(item)
        return true
    }

    public func remove(id: UUID) { items.removeAll { $0.id == id } }

    public func move(from source: IndexSet, to destination: Int) {
        let moving = source.sorted().compactMap { items.indices.contains($0) ? items[$0] : nil }
        let before = source.filter { $0 < destination }.count
        for index in source.sorted(by: >) where items.indices.contains(index) { items.remove(at: index) }
        let target = min(max(destination - before, 0), items.count)
        items.insert(contentsOf: moving, at: target)
    }

    public func clear() { items.removeAll() }

    @discardableResult
    public func pin(folder path: String) -> Bool {
        guard !pinnedFolders.contains(path) else { return false }
        pinnedFolders.append(path)
        return true
    }

    public func unpin(folder path: String) { pinnedFolders.removeAll { $0 == path } }
}

private extension JSONEncoder {
    static var tray: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

private extension JSONDecoder {
    static var tray: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
