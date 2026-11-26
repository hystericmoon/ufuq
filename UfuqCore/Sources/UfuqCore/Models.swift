import Foundation

/// Health of a module's data source. A broken source shows "unavailable"; it never crashes the app.
public enum ModuleStatus: Equatable, Sendable {
    case ok
    /// Last good data is older than expected; still shown, marked stale.
    case stale(since: Date)
    case unavailable(reason: String)

    public var isAvailable: Bool {
        if case .unavailable = self { return false }
        return true
    }
}

/// Where an activity comes from. Drives wing placement and priority.
public enum ActivitySource: String, Sendable, CaseIterable {
    case prayer
    case aiUsage
    case agent
    case nowPlaying
    case other
}

/// Notch wing. Prayer's home is the left wing, AI usage's home is the right.
public enum Wing: Sendable {
    case left
    case right
}

/// A UI-free description of what a module wants to show in the collapsed notch.
public struct LiveActivity: Identifiable, Equatable, Sendable {
    public var id: String
    public var moduleID: String
    public var source: ActivitySource
    /// Short text for the wing, e.g. "Ashar 12:04" or "82%".
    public var text: String
    /// One spoken summary, e.g. "Claude Work, 82 percent of session, resets in 1 hour 12 minutes".
    public var accessibilityLabel: String
    /// An active alert (e.g. adhan now, 95% reached). Highest wing priority.
    public var isAlert: Bool
    /// The moment the activity counts down to (next prayer, reset). Used for "prayer under 10 min".
    public var deadline: Date?
    /// Usage fraction 0...1 for AI activities (worst across providers). Used for "AI at 80% or more".
    public var usageFraction: Double?

    public init(
        id: String,
        moduleID: String,
        source: ActivitySource,
        text: String,
        accessibilityLabel: String,
        isAlert: Bool = false,
        deadline: Date? = nil,
        usageFraction: Double? = nil
    ) {
        self.id = id
        self.moduleID = moduleID
        self.source = source
        self.text = text
        self.accessibilityLabel = accessibilityLabel
        self.isAlert = isAlert
        self.deadline = deadline
        self.usageFraction = usageFraction
    }
}

/// A peek alert. One shows at a time; critical ones jump the queue.
public struct PeekEvent: Identifiable, Equatable, Sendable {
    public enum Priority: Int, Comparable, Sendable {
        case normal = 0
        /// 95% limits and adhan. Jump the queue and get a high-priority VoiceOver announcement.
        case critical = 1

        public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public static let defaultDuration: TimeInterval = 6

    public var id: String
    public var moduleID: String
    public var title: String
    public var message: String
    public var priority: Priority
    public var duration: TimeInterval
    /// Text posted as a VoiceOver announcement when the peek appears.
    public var announcement: String

    public init(
        id: String,
        moduleID: String,
        title: String,
        message: String,
        priority: Priority = .normal,
        duration: TimeInterval = PeekEvent.defaultDuration,
        announcement: String? = nil
    ) {
        self.id = id
        self.moduleID = moduleID
        self.title = title
        self.message = message
        self.priority = priority
        self.duration = duration
        self.announcement = announcement ?? "\(title). \(message)"
    }
}
