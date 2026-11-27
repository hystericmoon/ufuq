import Foundation

/// One row of AI usage: a Claude account, Codex, or (later) Antigravity.
public struct AIUsageLine: Equatable, Sendable, Identifiable {
    public enum Value: Equatable, Sendable {
        /// Tokens in the current 5-hour block (Claude): a count, never a percent.
        case tokens(count: Int, resetsAt: Date?)
        /// Real limit readings (Codex).
        case limits([UsageWindowReading])
        case unavailable(reason: String)
    }

    public var id: String
    public var provider: UsageProvider
    public var name: String
    public var value: Value
    public var isBetaSource: Bool
    public var paceTokensPerHour: Int?
    public var estimatedCostUSD: Double?
    public var weeklyTokens: Int?
    public var weeklyEstimatedCostUSD: Double?

    public init(
        id: String,
        provider: UsageProvider,
        name: String,
        value: Value,
        isBetaSource: Bool = false,
        paceTokensPerHour: Int? = nil,
        estimatedCostUSD: Double? = nil,
        weeklyTokens: Int? = nil,
        weeklyEstimatedCostUSD: Double? = nil
    ) {
        self.id = id
        self.provider = provider
        self.name = name
        self.value = value
        self.isBetaSource = isBetaSource
        self.paceTokensPerHour = paceTokensPerHour
        self.estimatedCostUSD = estimatedCostUSD
        self.weeklyTokens = weeklyTokens
        self.weeklyEstimatedCostUSD = weeklyEstimatedCostUSD
    }
}

/// AI usage: Claude Code logs (every account) as token counts, and Codex limits when installed.
///
/// Claude shows a token count only: its live limit is not verified, so there is no %, no amber or
/// red and no alert for it. Codex shows its real rate-limit %.
public final class AIUsageModule: UfuqModule {
    public let id = "ai"
    public let title = "AI usage"
    public var isEnabled = true

    private struct Account: Sendable {
        var dir: String
        var name: String
        var result: UsageResult<ClaudeUsageReport>?
    }

    private struct State {
        var claude: [Account]
        var codex: UsageResult<CodexRateLimits>?
        var antigravity: UsageResult<AntigravityUsageReport>?
        var previousReadings: [String: UsageSnapshot] = [:]
        var peeks: AsyncStream<PeekEvent>.Continuation?
    }

    private let codexSessionsDir: String?
    private let antigravityDir: String?
    private let fileSource: FileSource
    private let directoryExists: @Sendable (String) -> Bool
    private let cache = ClaudeLogCache()
    private let lock = NSLock()
    private var state: State

    public init(
        claudeDirs: [String],
        codexSessionsDir: String?,
        antigravityDir: String? = nil,
        fileSource: FileSource = LocalFileSource(),
        directoryExists: @escaping @Sendable (String) -> Bool = AIUsageModule.defaultDirectoryExists
    ) {
        self.codexSessionsDir = codexSessionsDir
        self.antigravityDir = antigravityDir
        self.fileSource = fileSource
        self.directoryExists = directoryExists
        self.state = State(claude: claudeDirs.map { Account(dir: $0, name: ClaudeAccounts.label(forConfigDir: $0), result: nil) })
    }

    public static let defaultDirectoryExists: @Sendable (String) -> Bool = { path in
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: - Refresh

    public func refresh() async throws {
        let (dirs, codexDir, agDir) = withLock { ($0.claude.map(\.dir), codexSessionsDir, antigravityDir) }
        let source = fileSource
        let exists = directoryExists
        let cache = cache
        let (claude, codex, antigravity) = await Task.detached {
            () -> ([UsageResult<ClaudeUsageReport>], UsageResult<CodexRateLimits>?, UsageResult<AntigravityUsageReport>?) in
            let claude = dirs.map { ClaudeLogParser.parse(configDir: $0, source: source, cache: cache) }
            var codex: UsageResult<CodexRateLimits>?
            if let codexDir, exists(codexDir) {
                codex = CodexParser.parse(sessionsDir: codexDir, source: source, now: Date())
            }
            var antigravity: UsageResult<AntigravityUsageReport>?
            if let agDir, exists(agDir) {
                antigravity = AntigravityParser.parse(configDir: agDir, now: Date())
            }
            return (claude, codex, antigravity)
        }.value

        let (continuation, events) = withLock { state -> (AsyncStream<PeekEvent>.Continuation?, [PeekEvent]) in
            for (i, result) in claude.enumerated() where i < state.claude.count { state.claude[i].result = result }
            state.codex = codex
            state.antigravity = antigravity
            return (state.peeks, updatePeeks(&state))
        }
        for event in events { continuation?.yield(event) }
    }

    // MARK: - Lines

    public func lines(at now: Date) -> [AIUsageLine] {
        let snapshot = withLock { $0 }
        var out: [AIUsageLine] = []
        for account in snapshot.claude {
            guard let result = account.result else { continue }
            let id = "claude.\(account.dir)"
            switch result {
            case .available(let report):
                let block = report.currentBlock(at: now)
                let pace: Int?
                let cost: Double?
                if let block {
                    let blockEntries = report.entries.filter { $0.timestamp >= block.start && $0.timestamp < block.end }
                    pace = ClaudePace.tokensPerHour(entries: blockEntries, resetsAt: block.end)
                    let usd = ClaudeCost.estimateUSD(entries: blockEntries)
                    cost = usd > 0 ? usd : nil
                } else {
                    pace = nil
                    cost = nil
                }
                let weekStart = now.addingTimeInterval(-ClaudeLogParser.weekLength)
                let weeklyEntries = report.entries.filter { $0.timestamp > weekStart && $0.timestamp <= now }
                let weeklyTotal = weeklyEntries.reduce(TokenCounts()) { $0 + $1.tokens }.total
                let weeklyUSD = ClaudeCost.estimateUSD(entries: weeklyEntries)
                out.append(AIUsageLine(
                    id: id,
                    provider: .claude,
                    name: account.name,
                    value: .tokens(count: block?.tokens.total ?? 0, resetsAt: block?.end),
                    paceTokensPerHour: pace,
                    estimatedCostUSD: cost,
                    weeklyTokens: weeklyTotal > 0 ? weeklyTotal : nil,
                    weeklyEstimatedCostUSD: weeklyUSD > 0 ? weeklyUSD : nil
                ))
            case .unavailable(let reason):
                out.append(AIUsageLine(id: id, provider: .claude, name: account.name, value: .unavailable(reason: reason)))
            }
        }
        switch snapshot.codex {
        case .available(let limits):
            out.append(AIUsageLine(id: "codex", provider: .codex, name: "Codex", value: .limits(limits.readings)))
        case .unavailable(let reason):
            out.append(AIUsageLine(id: "codex", provider: .codex, name: "Codex", value: .unavailable(reason: reason)))
        case nil:
            break
        }
        switch snapshot.antigravity {
        case .available(let report):
            out.append(AIUsageLine(
                id: "antigravity",
                provider: .antigravity,
                name: "Antigravity",
                value: .tokens(count: report.tokens, resetsAt: report.resetsAt),
                isBetaSource: true,
                weeklyTokens: report.weeklyTokens > 0 ? report.weeklyTokens : nil
            ))
        case .unavailable(let reason):
            out.append(AIUsageLine(
                id: "antigravity",
                provider: .antigravity,
                name: "Antigravity",
                value: .unavailable(reason: reason),
                isBetaSource: true
            ))
        case nil:
            break
        }
        return out
    }

    public var status: ModuleStatus {
        let lines = lines(at: Date())
        let broken = lines.compactMap { line -> String? in
            if case .unavailable(let reason) = line.value { return reason }
            return nil
        }
        // Unavailable only when every source is broken; one broken account must not hide the rest.
        if !lines.isEmpty, broken.count == lines.count { return .unavailable(reason: broken[0]) }
        return .ok
    }

    // MARK: - Collapsed activity

    public func collapsedActivity(at now: Date) throws -> LiveActivity? {
        let lines = lines(at: now)

        var worst: (line: AIUsageLine, reading: UsageWindowReading)?
        for line in lines {
            guard case .limits(let readings) = line.value, let reading = UsageSummary.worst(of: readings) else { continue }
            if worst == nil || reading.snapshot.fraction > worst!.reading.snapshot.fraction { worst = (line, reading) }
        }
        if let worst, let percent = UsageSummary.worstPercent(of: [worst.reading]),
           let fraction = UsageSummary.worstFraction(of: [worst.reading]) {
            return LiveActivity(
                id: "ai.usage", moduleID: id, source: .aiUsage,
                text: "\(percent)%",
                accessibilityLabel: "\(worst.line.name), \(Self.windowName(worst.reading.kind)), \(percent) percent used"
                    + Self.resetPhrase(worst.reading.snapshot.resetsAt, now: now),
                usageFraction: fraction)
        }

        var top: (line: AIUsageLine, count: Int, resetsAt: Date?)?
        for line in lines {
            guard case .tokens(let count, let resetsAt) = line.value else { continue }
            if top == nil || count > top!.count { top = (line, count, resetsAt) }
        }
        guard let top, top.count > 0 else { return nil }
        let first = top.line.name.split(separator: " ").first.map(String.init) ?? top.line.name
        return LiveActivity(
            id: "ai.usage", moduleID: id, source: .aiUsage,
            text: "\(first) \(TokenFormat.compact(top.count))",
            accessibilityLabel: "\(top.line.name), 5-hour session, \(TokenFormat.spoken(top.count)) used"
                + Self.resetPhrase(top.resetsAt, now: now),
            deadline: top.resetsAt)
    }

    public func accessibilitySummary() -> String {
        guard let activity = try? collapsedActivity(at: Date()) else {
            return status.isAvailable ? "No AI usage yet" : "AI usage unavailable"
        }
        return activity.accessibilityLabel
    }

    // MARK: - Peeks

    /// Alerts for Codex limits only (80%, 95%, reset). Claude token counts never alert.
    /// One consumer at a time, like the registry uses it.
    public func peekEvents() -> AsyncStream<PeekEvent> {
        AsyncStream { continuation in
            withLock { $0.peeks = continuation }
            continuation.onTermination = { [weak self] _ in self?.withLock { $0.peeks = nil } }
        }
    }

    /// Compares the new Codex readings with the previous refresh. Call with the lock held.
    private func updatePeeks(_ state: inout State) -> [PeekEvent] {
        guard case .available(let limits)? = state.codex else { return [] }
        var events: [PeekEvent] = []
        var current: [String: UsageSnapshot] = [:]
        for reading in limits.readings {
            let key = "codex.\(Self.windowKey(reading.kind))"
            current[key] = reading.snapshot
            guard let alert = UsageThresholds.default.alert(from: state.previousReadings[key], to: reading.snapshot) else { continue }
            let percent = Int((min(max(reading.snapshot.fraction, 0), 1) * 100).rounded(.down))
            let window = Self.windowName(reading.kind)
            let message: String
            switch alert {
            case .reachedWarning, .reachedCritical: message = "Codex \(window) at \(percent)%"
            case .reset: message = "Codex \(window) reset"
            }
            events.append(PeekEvent(
                id: "ai.\(key).\(alert).\(Int(reading.snapshot.resetsAt?.timeIntervalSince1970 ?? 0)).\(percent / 5)",
                moduleID: id, title: "Codex", message: message,
                priority: alert.peekPriority, announcement: message))
        }
        state.previousReadings = current
        return events
    }

    // MARK: - Helpers

    private func withLock<T>(_ body: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }

    private static func windowName(_ kind: UsageWindowKind) -> String {
        switch kind {
        case .session5h: return "5-hour session"
        case .weekly: return "weekly limit"
        case .modelGroup(let name): return name
        }
    }

    private static func windowKey(_ kind: UsageWindowKind) -> String {
        switch kind {
        case .session5h: return "5h"
        case .weekly: return "week"
        case .modelGroup(let name): return "group.\(name)"
        }
    }

    /// ", resets in 2 hours 10 minutes", or "" when there is no future reset.
    private static func resetPhrase(_ date: Date?, now: Date) -> String {
        guard let date, date > now else { return "" }
        return ", resets in \(PrayerFormat.spoken(date.timeIntervalSince(now)))"
    }
}
