import Foundation

/// Usage level for a limit window. Color always comes with the % in the UI.
public enum UsageLevel: Int, Comparable, Sendable {
    case normal = 0
    /// Amber, from 80%.
    case warning
    /// Red, from 95%.
    case critical

    public static func < (lhs: UsageLevel, rhs: UsageLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Amber at 80%, red at 95%. Also the two peek-alert points.
public struct UsageThresholds: Equatable, Sendable {
    public static let `default` = UsageThresholds(warning: 0.80, critical: 0.95)

    public var warning: Double
    public var critical: Double

    public init(warning: Double, critical: Double) {
        precondition(warning < critical, "warning must be below critical")
        self.warning = warning
        self.critical = critical
    }

    /// `fraction` is 0...1 (values outside are clamped).
    public func level(for fraction: Double) -> UsageLevel {
        let value = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        if value >= critical { return .critical }
        if value >= warning { return .warning }
        return .normal
    }

    /// The alert to peek when usage moves from `previous` to `current`, or nil.
    ///
    /// Fires once when crossing up into amber or red, and once on a window reset
    /// (`resetsAt` moved forward).
    public func alert(from previous: UsageSnapshot?, to current: UsageSnapshot) -> UsageAlert? {
        guard let previous else { return nil }
        if let old = previous.resetsAt, let new = current.resetsAt, new > old {
            return .reset
        }
        let before = level(for: previous.fraction)
        let after = level(for: current.fraction)
        guard after > before else { return nil }
        return after == .critical ? .reachedCritical : .reachedWarning
    }
}

public enum UsageAlert: Equatable, Sendable {
    case reachedWarning
    /// 95%: a critical peek that jumps the queue.
    case reachedCritical
    case reset

    public var peekPriority: PeekEvent.Priority {
        self == .reachedCritical ? .critical : .normal
    }
}

/// One reading of a limit window (e.g. Claude 5-hour session).
public struct UsageSnapshot: Equatable, Sendable {
    /// 0...1 of the limit used.
    public var fraction: Double
    public var capturedAt: Date
    /// When the window resets, if known.
    public var resetsAt: Date?

    public init(fraction: Double, capturedAt: Date, resetsAt: Date? = nil) {
        self.fraction = fraction
        self.capturedAt = capturedAt
        self.resetsAt = resetsAt
    }
}

/// "At this pace: session limit in 38 min."
public struct BurnRateEstimate: Equatable, Sendable {
    /// Fraction of the limit used per hour.
    public var fractionPerHour: Double
    /// Seconds from the latest sample until 100%, or nil when usage isn't rising.
    public var timeToLimit: TimeInterval?
    /// True when the limit is hit before the window resets (or no reset time is known).
    public var hitsLimitBeforeReset: Bool
}

public enum BurnRate {
    /// Minimum span of samples before an estimate is shown; avoids wild numbers from noise.
    public static let minimumSpan: TimeInterval = 5 * 60
    /// Only samples this recent count, so the estimate follows the current pace.
    public static let lookback: TimeInterval = 60 * 60

    /// Least-squares slope over recent samples of the current window.
    ///
    /// Samples before the latest reset (a drop in usage or a later `resetsAt`) are ignored.
    /// Returns nil with fewer than two samples or a span shorter than `minimumSpan`.
    public static func estimate(
        samples: [UsageSnapshot],
        minimumSpan: TimeInterval = BurnRate.minimumSpan,
        lookback: TimeInterval = BurnRate.lookback
    ) -> BurnRateEstimate? {
        let sorted = samples
            .filter { $0.fraction.isFinite }
            .sorted { $0.capturedAt < $1.capturedAt }
        guard let latest = sorted.last else { return nil }

        // Keep only the current window: everything after the last reset.
        var windowStart = 0
        for i in 1..<max(sorted.count, 1) {
            let prev = sorted[i - 1], cur = sorted[i]
            let resetMoved = (prev.resetsAt != nil && cur.resetsAt != nil && cur.resetsAt! > prev.resetsAt!)
            if cur.fraction < prev.fraction || resetMoved { windowStart = i }
        }
        let cutoff = latest.capturedAt.addingTimeInterval(-lookback)
        let window = sorted[windowStart...].filter { $0.capturedAt >= cutoff }

        guard window.count >= 2,
              let first = window.first,
              latest.capturedAt.timeIntervalSince(first.capturedAt) >= minimumSpan else { return nil }

        let origin = first.capturedAt
        let xs = window.map { $0.capturedAt.timeIntervalSince(origin) }
        let ys = window.map(\.fraction)
        let n = Double(window.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0
        for (x, y) in zip(xs, ys) {
            sxy += (x - meanX) * (y - meanY)
            sxx += (x - meanX) * (x - meanX)
        }
        guard sxx > 0 else { return nil }
        let perSecond = sxy / sxx

        guard perSecond > 0 else {
            return BurnRateEstimate(fractionPerHour: max(perSecond, 0) * 3600, timeToLimit: nil, hitsLimitBeforeReset: false)
        }

        let timeToLimit = max(0, 1 - latest.fraction) / perSecond
        let hitsBeforeReset: Bool
        if let resetsAt = latest.resetsAt {
            hitsBeforeReset = latest.capturedAt.addingTimeInterval(timeToLimit) < resetsAt
        } else {
            hitsBeforeReset = true
        }
        return BurnRateEstimate(fractionPerHour: perSecond * 3600, timeToLimit: timeToLimit, hitsLimitBeforeReset: hitsBeforeReset)
    }
}
