import Foundation

/// Estimates API-equivalent USD cost and token burn pace for Claude Code sessions.
public enum ClaudeCost {
    private struct Rates {
        var input: Double
        var output: Double
        var cacheWrite: Double
        var cacheRead: Double
    }

    private static let opus45 = Rates(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.50)
    private static let opusLegacy = Rates(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.50)
    private static let sonnet = Rates(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.30)
    private static let haiku45 = Rates(input: 1, output: 5, cacheWrite: 1.25, cacheRead: 0.10)
    private static let haikuLegacy = Rates(input: 0.80, output: 4, cacheWrite: 1.0, cacheRead: 0.08)

    private static func rates(for model: String?) -> Rates {
        let m = (model ?? "").lowercased()
        if m.contains("opus") {
            if m.contains("4-5") || m.contains("4.5") || m.contains("4-6") || m.contains("4.6") {
                return opus45
            }
            return opusLegacy
        }
        if m.contains("haiku") {
            if m.contains("4-5") || m.contains("4.5") {
                return haiku45
            }
            return haikuLegacy
        }
        return sonnet
    }

    /// Estimated USD cost for a single entry using per-million-token API rates.
    public static func costUSD(for entry: ClaudeUsageEntry) -> Double {
        let r = rates(for: entry.model)
        let t = entry.tokens
        return (
            Double(max(0, t.input)) * r.input
            + Double(max(0, t.output)) * r.output
            + Double(max(0, t.cacheCreation)) * r.cacheWrite
            + Double(max(0, t.cacheRead)) * r.cacheRead
        ) / 1_000_000.0
    }

    /// Total estimated USD cost across entries.
    public static func estimateUSD(entries: [ClaudeUsageEntry]) -> Double {
        entries.reduce(0) { $0 + costUSD(for: $1) }
    }

    /// Compact display format, e.g. "~$4.20" or "~$0.01".
    public static func formatUSD(_ amount: Double) -> String {
        guard amount.isFinite, amount > 0 else { return "~$0.00" }
        if amount < 0.01 { return "~$0.01" }
        return String(format: "~$%.2f", amount)
    }

    /// Spoken accessibility format, e.g. "4 dollars 20 cents".
    public static func spokenUSD(_ amount: Double) -> String {
        guard amount.isFinite, amount > 0 else { return "0 dollars" }
        let cents = max(1, Int((amount * 100).rounded()))
        let dollars = cents / 100
        let rem = cents % 100
        if dollars == 0 { return "\(rem) \(rem == 1 ? "cent" : "cents")" }
        if rem == 0 { return "\(dollars) \(dollars == 1 ? "dollar" : "dollars")" }
        return "\(dollars) \(dollars == 1 ? "dollar" : "dollars") \(rem) \(rem == 1 ? "cent" : "cents")"
    }
}

/// Computes Claude token burn pace (tokens/hour) using `BurnRate`.
public enum ClaudePace {
    private static let scale = 1_000_000.0

    /// Returns tokens per hour over the recent window, or nil when fewer than `BurnRate.minimumSpan` of samples exist.
    public static func tokensPerHour(entries: [ClaudeUsageEntry], resetsAt: Date?) -> Int? {
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        var cumulative = 0
        var samples: [UsageSnapshot] = []
        samples.reserveCapacity(sorted.count)
        for entry in sorted {
            cumulative += max(0, entry.tokens.total)
            samples.append(UsageSnapshot(
                fraction: Double(cumulative) / scale,
                capturedAt: entry.timestamp,
                resetsAt: resetsAt
            ))
        }
        guard let estimate = BurnRate.estimate(samples: samples), estimate.fractionPerHour > 0 else {
            return nil
        }
        return Int((estimate.fractionPerHour * scale).rounded())
    }
}
