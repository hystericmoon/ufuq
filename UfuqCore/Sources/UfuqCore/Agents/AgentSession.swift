import Foundation

public enum AgentSessionState: String, Codable, Equatable, Sendable {
    case idle, running, waiting, done
}

/// One Claude Code session, as stored in `<agents dir>/<session>.json`.
public struct AgentSession: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var cwd: String
    public var state: AgentSessionState
    public var updatedAt: Date
    public var runningSince: Date?
    public var finishedAt: Date?
    /// Bundle id of the app the session runs in (hook's `__CFBundleIdentifier`), for click-to-jump.
    public var appBundleID: String?

    public init(id: String, title: String, cwd: String, state: AgentSessionState, updatedAt: Date,
                runningSince: Date? = nil, finishedAt: Date? = nil, appBundleID: String? = nil) {
        self.id = id
        self.title = title
        self.cwd = cwd
        self.state = state
        self.updatedAt = updatedAt
        self.runningSince = runningSince
        self.finishedAt = finishedAt
        self.appBundleID = appBundleID
    }

    public func encoded() throws -> Data { try SyncCoding.encode(self) }

    public static func decode(_ data: Data) throws -> AgentSession {
        try SyncCoding.decode(AgentSession.self, from: data)
    }
}

public enum AgentSessionUpdate: Equatable, Sendable {
    case write(AgentSession)
    case delete
    case unchanged
}
