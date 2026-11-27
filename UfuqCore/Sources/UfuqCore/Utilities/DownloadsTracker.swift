import Foundation

public struct ActiveDownload: Equatable, Identifiable, Sendable {
    public var id: String
    public var fileName: String
    public var path: String
    public var byteCount: Int64
    public var modifiedAt: Date
    public var isInProgress: Bool

    public init(
        path: String,
        fileName: String,
        byteCount: Int64,
        modifiedAt: Date,
        isInProgress: Bool
    ) {
        self.id = path
        self.path = path
        self.fileName = fileName
        self.byteCount = max(0, byteCount)
        self.modifiedAt = modifiedAt
        self.isInProgress = isInProgress
    }
}

public final class DownloadsModule: UfuqModule, @unchecked Sendable {
    public let id = "downloads"
    public let title = "Downloads"
    public var isEnabled: Bool

    public static let partialExtensions: Set<String> = [
        "download", "crdownload", "part", "opdownload", "partial", "tmp"
    ]

    public static func isPartialFile(_ fileName: String) -> Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return partialExtensions.contains(ext)
    }

    public static func displayName(for fileName: String) -> String {
        guard isPartialFile(fileName) else { return fileName }
        let stripped = (fileName as NSString).deletingPathExtension
        return stripped.isEmpty ? fileName : stripped
    }

    private struct State {
        var status: ModuleStatus = .ok
        var hasBaseline = false
        var knownPaths: Set<String> = []
        var activePartialNames: Set<String> = []
        var currentActive: [ActiveDownload] = []
        var peeks: AsyncStream<PeekEvent>.Continuation?
    }

    private let scanner: @Sendable () -> [ActiveDownload]
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var state = State()

    public init(
        scanner: @escaping @Sendable () -> [ActiveDownload],
        isEnabled: Bool = true,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.scanner = scanner
        self.isEnabled = isEnabled
        self.clock = clock
    }

    public var status: ModuleStatus { withLock { $0.status } }

    public var activeDownloads: [ActiveDownload] {
        guard isEnabled else { return [] }
        return withLock { $0.currentActive }
    }

    public func refresh() async throws {
        guard isEnabled else {
            withLock {
                $0.currentActive = []
                $0.status = .ok
            }
            return
        }
        let scanned = scanner()
        let (continuation, peeks) = withLock { state -> (AsyncStream<PeekEvent>.Continuation?, [PeekEvent]) in
            state.status = .ok
            let active = scanned.filter(\.isInProgress)
            let completed = scanned.filter { !$0.isInProgress }
            state.currentActive = active

            if !state.hasBaseline {
                state.hasBaseline = true
                state.knownPaths = Set(scanned.map(\.path))
                state.activePartialNames = Set(active.map { Self.displayName(for: $0.fileName) })
                return (nil, [])
            }

            var events: [PeekEvent] = []
            for item in completed {
                let isNewPath = !state.knownPaths.contains(item.path)
                let wasPartial = state.activePartialNames.contains(item.fileName)
                if isNewPath || wasPartial {
                    events.append(PeekEvent(
                        id: "download.ready.\(item.path)",
                        moduleID: id,
                        title: "Download ready",
                        message: item.fileName,
                        priority: .normal
                    ))
                    state.activePartialNames.remove(item.fileName)
                }
            }

            state.knownPaths = Set(scanned.map(\.path))
            for item in active {
                state.activePartialNames.insert(Self.displayName(for: item.fileName))
            }
            return (state.peeks, events)
        }
        for event in peeks {
            continuation?.yield(event)
        }
    }

    public func collapsedActivity(at now: Date) throws -> LiveActivity? {
        guard isEnabled else { return nil }
        let active = withLock { $0.currentActive }
        guard !active.isEmpty else { return nil }
        let totalBytes = active.reduce(Int64(0)) { $0 + $1.byteCount }
        let text: String
        let spoken: String
        if active.count == 1, let first = active.first {
            let size = Self.compactByteCount(first.byteCount)
            text = "↓ \(size)"
            spoken = "Downloading \(first.fileName), \(size)"
        } else {
            let size = Self.compactByteCount(totalBytes)
            text = "↓ \(active.count) files"
            spoken = "Downloading \(active.count) files, \(size)"
        }
        return LiveActivity(
            id: "downloads.active",
            moduleID: id,
            source: .other,
            text: text,
            accessibilityLabel: spoken
        )
    }

    public func peekEvents() -> AsyncStream<PeekEvent> {
        AsyncStream { continuation in
            withLock { $0.peeks = continuation }
        }
    }

    public func accessibilitySummary() -> String {
        let active = activeDownloads
        if active.isEmpty { return "No active downloads" }
        return "\(active.count) active downloads"
    }

    public static func compactByteCount(_ bytes: Int64) -> String {
        let b = max(0, bytes)
        if b < 1024 { return "\(b) B" }
        let kb = Double(b) / 1024
        if kb < 1024 { return "\(Int(kb.rounded())) KB" }
        let mb = kb / 1024
        if mb < 1024 { return "\(Int(mb.rounded())) MB" }
        return String(format: "%.1f GB", mb / 1024)
    }

    private func withLock<T>(_ body: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }
}
