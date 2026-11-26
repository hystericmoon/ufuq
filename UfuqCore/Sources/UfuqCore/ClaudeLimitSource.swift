import Foundation

/// Live Claude limits (the 5-hour and weekly %). The real endpoint is unverified, so the app
/// target implements this later; core code and tests only see the protocol.
public protocol ClaudeLimitSource: Sendable {
    func fetchLimits(for account: UsageAccount) async throws -> [UsageWindowReading]
}

/// Test double: returns fixed readings or throws.
public struct FakeClaudeLimitSource: ClaudeLimitSource {
    public var result: Result<[UsageWindowReading], Error>

    public init(result: Result<[UsageWindowReading], Error>) { self.result = result }

    public func fetchLimits(for account: UsageAccount) async throws -> [UsageWindowReading] {
        try result.get()
    }
}

/// Fallback when the live source fails: local token counts against assumed budgets.
/// Every reading is labelled `isEstimated = true`.
public struct UsageEstimate: Equatable, Sendable {
    /// Tokens assumed to fill the 5-hour window / the week. Plan-dependent; user-configurable.
    public var sessionBudgetTokens: Int
    public var weeklyBudgetTokens: Int

    public init(sessionBudgetTokens: Int, weeklyBudgetTokens: Int) {
        self.sessionBudgetTokens = sessionBudgetTokens
        self.weeklyBudgetTokens = weeklyBudgetTokens
    }

    public func readings(from report: ClaudeUsageReport, at now: Date) -> [UsageWindowReading] {
        var out: [UsageWindowReading] = []
        if sessionBudgetTokens > 0 {
            let block = report.currentBlock(at: now)
            let used = block?.tokens.total ?? 0
            out.append(UsageWindowReading(
                kind: .session5h,
                snapshot: UsageSnapshot(fraction: Double(used) / Double(sessionBudgetTokens),
                                        capturedAt: now, resetsAt: block?.end),
                isEstimated: true))
        }
        if weeklyBudgetTokens > 0 {
            let used = report.weeklyTokens(at: now).total
            out.append(UsageWindowReading(
                kind: .weekly,
                snapshot: UsageSnapshot(fraction: Double(used) / Double(weeklyBudgetTokens), capturedAt: now),
                isEstimated: true))
        }
        return out
    }
}

public enum ClaudeUsageResolver {
    /// Live readings when the source works, else the estimate from local logs, else unavailable.
    public static func readings(
        for account: UsageAccount,
        live: ClaudeLimitSource?,
        estimate: UsageEstimate,
        fileSource: FileSource = LocalFileSource(),
        now: Date = Date()
    ) async -> UsageResult<[UsageWindowReading]> {
        var liveFailure = "no live source"
        if let live {
            do {
                let readings = try await live.fetchLimits(for: account)
                if !readings.isEmpty { return .available(readings) }
                liveFailure = "live source returned no windows"
            } catch {
                liveFailure = "live source failed: \(error)"
            }
        }
        let dir = account.configDir ?? ClaudeLogParser.defaultConfigDir()
        switch ClaudeLogParser.parse(configDir: dir, source: fileSource) {
        case .available(let report):
            return .available(estimate.readings(from: report, at: now))
        case .unavailable(let reason):
            return .unavailable(reason: "\(liveFailure); \(reason)")
        }
    }
}
