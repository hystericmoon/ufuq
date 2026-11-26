import Foundation

public enum UsageProvider: String, Sendable, CaseIterable, Codable {
    case claude, codex, antigravity
}

/// One tracked account. For Claude, `configDir` is the account's `CLAUDE_CONFIG_DIR`.
public struct UsageAccount: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var provider: UsageProvider
    public var displayName: String
    public var configDir: String?

    public init(id: String, provider: UsageProvider, displayName: String, configDir: String? = nil) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.configDir = configDir
    }
}

public enum UsageWindowKind: Equatable, Hashable, Sendable {
    case session5h
    case weekly
    /// Antigravity-style quota per model group.
    case modelGroup(String)
}

/// A limit window reading for one account. `isEstimated` marks numbers computed locally
/// instead of read from the provider; the UI labels them "estimated".
public struct UsageWindowReading: Equatable, Sendable {
    public var kind: UsageWindowKind
    public var snapshot: UsageSnapshot
    public var isEstimated: Bool

    public init(kind: UsageWindowKind, snapshot: UsageSnapshot, isEstimated: Bool = false) {
        self.kind = kind
        self.snapshot = snapshot
        self.isEstimated = isEstimated
    }
}

/// A parse or fetch outcome. A broken source is `.unavailable`, never a crash.
public enum UsageResult<Value: Sendable>: Sendable {
    case available(Value)
    case unavailable(reason: String)

    public var value: Value? {
        if case .available(let v) = self { return v }
        return nil
    }

    public var status: ModuleStatus {
        switch self {
        case .available: return .ok
        case .unavailable(let reason): return .unavailable(reason: reason)
        }
    }
}

extension UsageResult: Equatable where Value: Equatable {}

public enum UsageSummary {
    /// The reading with the highest fraction, or nil when there are none (or none finite).
    public static func worst(of readings: [UsageWindowReading]) -> UsageWindowReading? {
        readings
            .filter { $0.snapshot.fraction.isFinite }
            .max { $0.snapshot.fraction < $1.snapshot.fraction }
    }

    /// Worst fraction (0...1, clamped) for the collapsed ring text; nil when there are no readings.
    public static func worstFraction(of readings: [UsageWindowReading]) -> Double? {
        worst(of: readings).map { min(max($0.snapshot.fraction, 0), 1) }
    }

    /// Whole-number percent for the collapsed text, e.g. 0.874 -> 87.
    public static func worstPercent(of readings: [UsageWindowReading]) -> Int? {
        worstFraction(of: readings).map { Int(($0 * 100).rounded(.down)) }
    }
}
