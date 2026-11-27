import Foundation

/// Wing priority, highest first:
/// active alert > prayer under 10 min > AI at 80% or more > agent task running > Now Playing > other.
public enum WingPriority: Int, Comparable, Sendable {
    case other = 0
    case nowPlaying
    case agentRunning
    case aiUsageHigh
    case prayerSoon
    case alert

    public static func < (lhs: WingPriority, rhs: WingPriority) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What the collapsed notch shows.
public struct WingLayout: Equatable, Sendable {
    public var left: LiveActivity?
    public var right: LiveActivity?
    /// Shown in the right wing instead of `right` right now: the third activity on its 8 s turn,
    /// or an alert pinned. `nil` means it is `right`'s turn (or there is no third activity).
    public var rotating: LiveActivity?

    /// What the right wing displays at this moment.
    public var rightWingShown: LiveActivity? { rotating ?? right }

    public init(left: LiveActivity? = nil, right: LiveActivity? = nil, rotating: LiveActivity? = nil) {
        self.left = left
        self.right = right
        self.rotating = rotating
    }
}

/// Chooses what goes in each wing and rotates a third activity.
///
/// - Prayer always takes the left wing and AI usage the right (fixed positions build habit).
///   An empty home wing is filled with the highest-priority remaining activity.
/// - The rest form the pool, ordered by priority. The pool shares the right wing with AI:
///   the cycle is `[AI] + pool` (just the pool when there is no AI), each shown for `rotationInterval`.
///   `rotating` is `nil` on AI's turn, otherwise the pool item whose turn it is.
/// - While an alert is in the pool it is pinned in the right wing and hides AI; no cycling.
public struct ActivityArbiter {
    public static let defaultRotationInterval: TimeInterval = 8
    public static let prayerSoonWindow: TimeInterval = 10 * 60

    public var rotationInterval: TimeInterval
    public var thresholds: UsageThresholds

    private var rotatingID: String?
    private var shownSince: Date?

    public init(
        rotationInterval: TimeInterval = ActivityArbiter.defaultRotationInterval,
        thresholds: UsageThresholds = .default
    ) {
        self.rotationInterval = rotationInterval
        self.thresholds = thresholds
    }

    public func priority(of activity: LiveActivity, at now: Date) -> WingPriority {
        if activity.isAlert { return .alert }
        switch activity.source {
        case .prayer:
            if let deadline = activity.deadline {
                let remaining = deadline.timeIntervalSince(now)
                if remaining >= 0 && remaining < Self.prayerSoonWindow { return .prayerSoon }
            }
            return .other
        case .aiUsage:
            if let fraction = activity.usageFraction, thresholds.level(for: fraction) >= .warning {
                return .aiUsageHigh
            }
            return .other
        case .agent: return .agentRunning
        case .nowPlaying: return .nowPlaying
        case .other: return .other
        }
    }

    /// Activities sorted by priority, highest first; ties keep input order.
    public func ranked(_ activities: [LiveActivity], at now: Date) -> [LiveActivity] {
        activities.enumerated()
            .sorted { a, b in
                let pa = priority(of: a.element, at: now)
                let pb = priority(of: b.element, at: now)
                return pa != pb ? pa > pb : a.offset < b.offset
            }
            .map(\.element)
    }

    /// Advances the rotating right-wing slot immediately on the next `layout(for:at:)` call.
    /// Pinned alerts still take precedence until cleared.
    public mutating func advanceRotation() {
        guard rotatingID != nil else { return }
        shownSince = .distantPast
    }

    /// Computes the layout for `now`. Call on every tick; it advances the rotation when due.
    public mutating func layout(for activities: [LiveActivity], at now: Date) -> WingLayout {
        var pool = ranked(activities, at: now)

        func takeFirst(_ source: ActivitySource) -> LiveActivity? {
            guard let index = pool.firstIndex(where: { $0.source == source }) else { return nil }
            return pool.remove(at: index)
        }

        var left = takeFirst(.prayer)
        var right = takeFirst(.aiUsage)
        // An alert never fills an empty home wing: it belongs in the rotating slot, pinned.
        if left == nil, let index = pool.firstIndex(where: { !$0.isAlert }) { left = pool.remove(at: index) }
        if right == nil, let index = pool.firstIndex(where: { !$0.isAlert }) { right = pool.remove(at: index) }

        return WingLayout(left: left, right: right, rotating: nextRotating(right: right, pool: pool, at: now))
    }

    private mutating func nextRotating(right: LiveActivity?, pool: [LiveActivity], at now: Date) -> LiveActivity? {
        guard !pool.isEmpty else {
            rotatingID = nil
            shownSince = nil
            return nil
        }

        if let alert = pool.first(where: \.isAlert) {
            return show(alert, at: now, keepTimer: alert.id == rotatingID, isRight: false)
        }

        let cycle = (right.map { [$0] } ?? []) + pool
        guard let currentIndex = cycle.firstIndex(where: { $0.id == rotatingID }),
              let since = shownSince else {
            return show(cycle[0], at: now, keepTimer: false, isRight: cycle[0].id == right?.id)
        }

        if now.timeIntervalSince(since) >= rotationInterval {
            let next = cycle[(currentIndex + 1) % cycle.count]
            return show(next, at: now, keepTimer: false, isRight: next.id == right?.id)
        }
        let current = cycle[currentIndex]
        return current.id == right?.id ? nil : current
    }

    private mutating func show(_ activity: LiveActivity, at now: Date, keepTimer: Bool, isRight: Bool) -> LiveActivity? {
        if !keepTimer || shownSince == nil { shownSince = now }
        rotatingID = activity.id
        return isRight ? nil : activity
    }
}
