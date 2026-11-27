import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Directory of per-session state files, written by `ufuq-hook` and read by `AgentStatusModule`.
public struct AgentStateStore: Sendable {
    public static let pruneAge: TimeInterval = 24 * 3600

    public let directory: String

    public init(directory: String) { self.directory = directory }

    public init(environment: [String: String]) {
        self.init(directory: Self.resolveDirectory(environment: environment))
    }

    /// `$UFUQ_AGENT_DIR` if set, else Application Support `Ufuq/agents`.
    public static func resolveDirectory(environment: [String: String]) -> String {
        if let dir = environment["UFUQ_AGENT_DIR"], !dir.isEmpty { return dir }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Ufuq/agents").path
    }

    /// session_id with every character outside `[A-Za-z0-9._-]` replaced by `_`, plus `.json`.
    public static func fileName(forSessionID id: String) -> String {
        let mapped = id.unicodeScalars.map { s -> Character in
            switch s.value {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2E, 0x2D, 0x5F: return Character(s)
            default: return "_"
            }
        }
        return String(mapped) + ".json"
    }

    /// Parse -> lock -> read -> state machine -> atomic write or delete. Never throws: bad input
    /// or a disk error leaves the state unchanged. Returns what was applied.
    @discardableResult
    public func apply(stdin: Data, now: Date = Date(), environment: [String: String] = [:]) -> AgentSessionUpdate {
        guard let event = AgentHookEvent.parse(stdin) else { return .unchanged }
        let fm = FileManager.default
        do { try fm.createDirectory(atPath: directory, withIntermediateDirectories: true) } catch { return .unchanged }

        let lockFD = open((directory as NSString).appendingPathComponent(".lock"), O_CREAT | O_RDWR, 0o600)
        if lockFD >= 0 { _ = flock(lockFD, LOCK_EX) }
        defer { if lockFD >= 0 { _ = flock(lockFD, LOCK_UN); close(lockFD) } }

        let path = (directory as NSString).appendingPathComponent(Self.fileName(forSessionID: event.sessionID))
        let existing = fm.contents(atPath: path).flatMap { try? AgentSession.decode($0) }
        let update = AgentStateMachine.apply(event, to: existing, now: now, appBundleID: environment["__CFBundleIdentifier"])

        if event.hookEventName == "SessionStart" { prune(now: now) }

        switch update {
        case .write(let session):
            guard let data = try? session.encoded() else { return .unchanged }
            let tmp = (directory as NSString).appendingPathComponent(".\(UUID().uuidString).tmp")
            guard fm.createFile(atPath: tmp, contents: data, attributes: [.posixPermissions: 0o600]) else { return .unchanged }
            if rename(tmp, path) != 0 {
                try? fm.removeItem(atPath: tmp)
                return .unchanged
            }
        case .delete:
            try? fm.removeItem(atPath: path)
        case .unchanged:
            break
        }
        return update
    }

    /// Removes state files whose `updatedAt` is older than 24 h. Unreadable files are left alone.
    private func prune(now: Date) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory) else { return }
        for name in names where name.hasSuffix(".json") && !name.hasPrefix(".") {
            let path = (directory as NSString).appendingPathComponent(name)
            guard let data = fm.contents(atPath: path), let session = try? AgentSession.decode(data) else { continue }
            if now.timeIntervalSince(session.updatedAt) > Self.pruneAge { try? fm.removeItem(atPath: path) }
        }
    }
}
