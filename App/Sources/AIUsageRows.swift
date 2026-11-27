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
            row.detail = future.map { "Resets in \(duration($0.timeIntervalSince(now)))" } ?? "No session running"
            let spoken = TokenFormat.spoken(count)
            row.accessibilityValue = future.map {
                "\(spoken) used in this 5-hour session, resets in \(PrayerFormat.spoken($0.timeIntervalSince(now)))"
            } ?? "\(spoken) used in this 5-hour session"
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
}
