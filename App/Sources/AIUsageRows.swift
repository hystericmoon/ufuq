import Foundation
import UfuqCore

/// Turns the AI module's lines into rows for the open panel's AI tile. Pure, so it is unit tested.
enum AIUsageRows {
    static func rows(from lines: [AIUsageLine], now: Date) -> [AIUsageRow] {
        lines.map { row(from: $0, now: now) }
    }

    private static func row(from line: AIUsageLine, now: Date) -> AIUsageRow {
        var row = AIUsageRow(id: line.id, provider: line.provider, name: line.name, fraction: 0, detail: "",
                             isBetaSource: line.isBetaSource)
        switch line.value {
        case .tokens(let count, let resetsAt):
            row.tokens = count
            let future = resetsAt.flatMap { $0 > now ? $0 : nil }
            if let future {
                var parts: [String] = []
                if let pace = line.paceTokensPerHour, pace > 0 {
                    parts.append("\(TokenFormat.compact(pace))/h")
                }
                if let cost = line.estimatedCostUSD, cost > 0 {
                    parts.append(ClaudeCost.formatUSD(cost))
                }
                if parts.isEmpty {
                    row.detail = "Resets in \(duration(future.timeIntervalSince(now)))"
                } else {
                    parts.append(shortDuration(future.timeIntervalSince(now)))
                    row.detail = parts.joined(separator: " · ")
                }
            } else {
                row.detail = "No session running"
            }
            let spoken = TokenFormat.spoken(count)
            var a11y = "\(spoken) used in this 5-hour session"
            if let pace = line.paceTokensPerHour, pace > 0 {
                a11y += ", pace \(TokenFormat.spoken(pace)) per hour"
            }
            if let cost = line.estimatedCostUSD, cost > 0 {
                a11y += ", estimated cost \(ClaudeCost.spokenUSD(cost))"
            }
            if let future {
                a11y += ", resets in \(PrayerFormat.spoken(future.timeIntervalSince(now)))"
            }
            row.accessibilityValue = a11y
        case .limits(let readings):
            guard let worst = UsageSummary.worst(of: readings),
                  let fraction = UsageSummary.worstFraction(of: readings) else {
                row.isUnavailable = true
                row.detail = "Unavailable"
                row.accessibilityValue = "unavailable"
                return row
            }
            row.fraction = fraction
            let percent = Int((fraction * 100).rounded(.down))
            let window = windowName(worst.kind)
            let reset = worst.snapshot.resetsAt.flatMap { $0 > now ? $0 : nil }
            var detail = "\(window) \(percent)%" + (worst.isEstimated ? " est." : "")
            if let reset { detail += " · resets in \(duration(reset.timeIntervalSince(now)))" }
            row.detail = detail
            row.accessibilityValue = "\(percent) percent of the \(window.lowercased()) limit used"
                + (worst.isEstimated ? ", estimated" : "")
                + (reset.map { ", resets in \(PrayerFormat.spoken($0.timeIntervalSince(now)))" } ?? "")
        case .unavailable:
            row.isUnavailable = true
            row.detail = "Unavailable"
            row.accessibilityValue = "unavailable"
        }
        return row
    }

    private static func windowName(_ kind: UsageWindowKind) -> String {
        switch kind {
        case .session5h: return "5-hour"
        case .weekly: return "Week"
        case .modelGroup(let name): return name
        }
    }

    /// "2 h 10 min", "38 min", "2 h", "under 1 min". Rounds up to the minute.
    static func duration(_ interval: TimeInterval) -> String {
        if interval < 60 { return "under 1 min" }
        let minutes = Int((interval / 60).rounded(.up))
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// Compact reset suffix when paired with pace/cost: "2 h 10 m", "38 m", "2 h", "<1 m".
    static func shortDuration(_ interval: TimeInterval) -> String {
        if interval < 60 { return "<1 m" }
        let minutes = Int((interval / 60).rounded(.up))
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) m" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) m"
    }
}
