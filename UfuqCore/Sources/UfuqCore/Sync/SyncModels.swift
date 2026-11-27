import Foundation

/// Wire models for the Mac -> phone sync (see `docs/sync.md`). Dates travel as ISO 8601 UTC
/// with whole seconds, e.g. `2026-11-26T09:00:00Z`.
public enum SyncProtocol {
    public static let version = 1
    /// Associated data for every sealed box.
    public static let associatedData = Data("ufuq-sync-v1".utf8)
    public static let nonceLength = 12
    public static let tagLength = 16
    /// A client rejects a payload whose `generatedAt` is further than this from its own clock.
    public static let maxClockSkew: TimeInterval = 5 * 60
    public static let longPollTimeout: TimeInterval = 30
    public static let authHeader = "X-Ufuq-Auth"
    public static let bonjourType = "_ufuq._tcp"
    /// Plaintext prefix of the request token; followed by the client's Unix time in seconds.
    public static let authPrefix = "ufuq-sync-auth:"
}

/// One limit window reading for one account (`UsageWindowReading` plus its account).
public struct SyncReading: Codable, Equatable, Sendable {
    public var accountId: String
    public var accountName: String
    public var provider: UsageProvider
    /// `session5h`, `weekly` or `modelGroup`.
    public var kind: String
    /// The model group name when `kind` is `modelGroup`.
    public var group: String?
    /// 0...1 of the limit used.
    public var fraction: Double
    public var capturedAt: Date
    public var resetsAt: Date?
    public var isEstimated: Bool

    public init(
        accountId: String, accountName: String, provider: UsageProvider, kind: String,
        group: String? = nil, fraction: Double, capturedAt: Date, resetsAt: Date? = nil,
        isEstimated: Bool = false
    ) {
        self.accountId = accountId
        self.accountName = accountName
        self.provider = provider
        self.kind = kind
        self.group = group
        self.fraction = fraction
        self.capturedAt = capturedAt
        self.resetsAt = resetsAt
        self.isEstimated = isEstimated
    }

    public init(account: UsageAccount, reading: UsageWindowReading) {
        var kind: String
        var group: String?
        switch reading.kind {
        case .session5h: kind = "session5h"
        case .weekly: kind = "weekly"
        case .modelGroup(let name): kind = "modelGroup"; group = name
        }
        self.init(
            accountId: account.id, accountName: account.displayName, provider: account.provider,
            kind: kind, group: group, fraction: reading.snapshot.fraction,
            capturedAt: reading.snapshot.capturedAt, resetsAt: reading.snapshot.resetsAt,
            isEstimated: reading.isEstimated)
    }
}

public enum SyncAgentState: String, Codable, Sendable {
    case running, waiting, done
}

public struct SyncAgent: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var state: SyncAgentState
    public var updatedAt: Date

    public init(id: String, title: String, state: SyncAgentState, updatedAt: Date) {
        self.id = id
        self.title = title
        self.state = state
        self.updatedAt = updatedAt
    }
}

/// `GET /v1/snapshot`.
public struct SyncSnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var generatedAt: Date
    public var readings: [SyncReading]
    public var agents: [SyncAgent]

    public init(version: Int = SyncProtocol.version, generatedAt: Date, readings: [SyncReading], agents: [SyncAgent]) {
        self.version = version
        self.generatedAt = generatedAt
        self.readings = readings
        self.agents = agents
    }
}

public enum SyncEventPriority: String, Codable, Sendable {
    case normal, critical
}

/// A peek event for the phone (`PeekEvent` plus a sequence number).
public struct SyncEvent: Codable, Equatable, Sendable {
    public var seq: Int
    public var id: String
    public var moduleId: String
    public var title: String
    public var message: String
    public var priority: SyncEventPriority
    public var createdAt: Date

    public init(seq: Int, id: String, moduleId: String, title: String, message: String,
                priority: SyncEventPriority, createdAt: Date) {
        self.seq = seq
        self.id = id
        self.moduleId = moduleId
        self.title = title
        self.message = message
        self.priority = priority
        self.createdAt = createdAt
    }
}

/// `GET /v1/events?since=<seq>`.
public struct SyncEventBatch: Codable, Equatable, Sendable {
    public var version: Int
    public var generatedAt: Date
    /// The cursor: the last event in `events`, or the request's `since` when empty. Pass it as `since` next time.
    public var latestSeq: Int
    public var events: [SyncEvent]

    public init(version: Int = SyncProtocol.version, generatedAt: Date, latestSeq: Int, events: [SyncEvent]) {
        self.version = version
        self.generatedAt = generatedAt
        self.latestSeq = latestSeq
        self.events = events
    }
}

/// Seals and opens payloads. The CryptoKit implementation lives in the Mac app (CryptoKit is
/// not on Linux). Layout: `nonce (12) || ciphertext || tag (16)`, associated data
/// `SyncProtocol.associatedData`.
public protocol SyncSealer: Sendable {
    func seal(_ plaintext: Data) throws -> Data
    func open(_ sealed: Data) throws -> Data
}
