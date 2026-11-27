import Foundation

/// Recognized video conferencing providers for meeting Join actions.
public enum MeetingProvider: String, Equatable, Codable, Sendable, CaseIterable {
    case googleMeet
    case zoom
    case teams
    case webex
    case facetime
    case other

    public var displayName: String {
        switch self {
        case .googleMeet: return "Meet"
        case .zoom: return "Zoom"
        case .teams: return "Teams"
        case .webex: return "Webex"
        case .facetime: return "FaceTime"
        case .other: return "Meeting"
        }
    }
}

/// Extracts video meeting join URLs from event URL, location, and notes fields.
public enum MeetingURLParser {
    private static let knownPatterns: [(provider: MeetingProvider, pattern: String)] = [
        (.googleMeet, #"https?://meet\.google\.com/[A-Za-z0-9\-_?=&/]+"#),
        (.zoom, #"(?:https?://(?:[A-Za-z0-9\-]+\.)?zoom\.us/(?:j|wc|my)/[^\s<>)"']+|zoommtg://[^\s<>)"']+)"#),
        (.teams, #"(?:https?://teams\.(?:microsoft|live)\.com/(?:l/meetup-join|meet)/[^\s<>)"']+|msteams://[^\s<>)"']+)"#),
        (.webex, #"https?://[A-Za-z0-9\-]+\.webex\.com/(?:meet|join)/[^\s<>)"']+"#),
        (.facetime, #"https?://facetime\.apple\.com/join[^\s<>)"']*"#),
    ]

    public static func extractJoinLink(url: URL?, location: String?, notes: String?) -> (url: URL, provider: MeetingProvider)? {
        let candidates = [url?.absoluteString, location, notes].compactMap { $0 }
        for text in candidates {
            for (provider, pattern) in knownPatterns {
                if let matched = firstMatch(pattern: pattern, in: text),
                   let parsed = URL(string: matched) {
                    return (parsed, provider)
                }
            }
        }
        if let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return (url, provider(for: url))
        }
        return nil
    }

    public static func provider(for url: URL) -> MeetingProvider {
        let host = url.host?.lowercased() ?? ""
        let scheme = url.scheme?.lowercased() ?? ""
        if host == "meet.google.com" { return .googleMeet }
        if host == "zoom.us" || host.hasSuffix(".zoom.us") || scheme == "zoommtg" { return .zoom }
        if host.contains("teams.microsoft.com") || host.contains("teams.live.com") || scheme == "msteams" { return .teams }
        if host.hasSuffix(".webex.com") { return .webex }
        if host == "facetime.apple.com" { return .facetime }
        return .other
    }

    private static func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let swiftRange = Range(match.range, in: text) else {
            return nil
        }
        let raw = String(text[swiftRange])
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}>\"'"))
    }
}

public struct MeetingEvent: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var joinURL: URL?
    public var provider: MeetingProvider?
    public var calendarName: String?
    public var isAllDay: Bool

    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        joinURL: URL? = nil,
        provider: MeetingProvider? = nil,
        calendarName: String? = nil,
        isAllDay: Bool = false
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.joinURL = joinURL
        self.provider = provider ?? joinURL.map { MeetingURLParser.provider(for: $0) }
        self.calendarName = calendarName
        self.isAllDay = isAllDay
    }

    public var hasVideoLink: Bool { joinURL != nil }

    public func isOngoing(at now: Date) -> Bool {
        startDate <= now && now < endDate
    }

    /// True starting `lead` seconds before the meeting (default 5 min) until it ends.
    public func canJoin(at now: Date, lead: TimeInterval = 5 * 60) -> Bool {
        guard joinURL != nil else { return false }
        return now >= startDate.addingTimeInterval(-lead) && now < endDate
    }

    public func timeUntilStart(at now: Date) -> TimeInterval {
        startDate.timeIntervalSince(now)
    }

    public func timeUntilEnd(at now: Date) -> TimeInterval {
        endDate.timeIntervalSince(now)
    }
}

/// Abstract calendar source so `CalendarModule` runs deterministically in `UfuqCore` tests.
public protocol CalendarEventSource: Sendable {
    func events(from start: Date, to end: Date) async throws -> [MeetingEvent]
}

public enum AutoDNDTransition: Equatable, Sendable {
    case none
    case enable(MeetingEvent)
    case disable
}

/// Tracks transitions into and out of active meetings for Auto DND.
public struct AutoDNDTracker: Equatable, Sendable {
    public private(set) var activeMeetingID: String?

    public init() {}

    public mutating func update(
        enabled: Bool,
        ongoingMeeting: MeetingEvent?,
        requireVideoLink: Bool = true
    ) -> AutoDNDTransition {
        guard enabled else {
            if activeMeetingID != nil {
                activeMeetingID = nil
                return .disable
            }
            return .none
        }

        let eligible: MeetingEvent? = ongoingMeeting.flatMap { event in
            guard !event.isAllDay else { return nil }
            if requireVideoLink && !event.hasVideoLink { return nil }
            return event
        }

        if let meeting = eligible {
            if activeMeetingID != meeting.id {
                activeMeetingID = meeting.id
                return .enable(meeting)
            }
            return .none
        } else if activeMeetingID != nil {
            activeMeetingID = nil
            return .disable
        }
        return .none
    }
}
