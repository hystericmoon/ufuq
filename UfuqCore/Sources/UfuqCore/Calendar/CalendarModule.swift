import Foundation

/// Calendar & Meetings module: next meeting, Join link 5 min before, wing countdown, and pre-meeting peeks.
public final class CalendarModule: UfuqModule {
    public let id = "calendar"
    public let title = "Calendar"
    public var isEnabled: Bool

    /// Wing appears starting 15 min before a meeting; Join peek & alert start 5 min before.
    public static let wingLeadWindow: TimeInterval = 15 * 60
    public static let joinLeadWindow: TimeInterval = 5 * 60
    public static let lookaheadWindow: TimeInterval = 24 * 3600

    private struct State {
        var events: [MeetingEvent] = []
        var status: ModuleStatus = .ok
        var notifiedJoinIDs: Set<String> = []
        var peeks: AsyncStream<PeekEvent>.Continuation?
    }

    private let source: any CalendarEventSource
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var state = State()

    public init(
        source: any CalendarEventSource,
        isEnabled: Bool = true,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.isEnabled = isEnabled
        self.clock = clock
    }

    public var status: ModuleStatus { withLock { $0.status } }

    public func refresh() async throws {
        guard isEnabled else {
            withLock {
                $0.events = []
                $0.status = .ok
            }
            return
        }
        let now = clock()
        let start = now.addingTimeInterval(-6 * 3600)
        let end = now.addingTimeInterval(Self.lookaheadWindow)
        do {
            let fetched = try await source.events(from: start, to: end)
                .sorted { $0.startDate < $1.startDate }
            let (continuation, peeks) = withLock { state -> (AsyncStream<PeekEvent>.Continuation?, [PeekEvent]) in
                state.events = fetched
                state.status = .ok
                let due = Self.dueJoinPeeks(in: fetched, at: now, seen: &state.notifiedJoinIDs)
                return (state.peeks, due)
            }
            for event in peeks {
                continuation?.yield(event)
            }
        } catch {
            withLock {
                $0.events = []
                $0.status = .unavailable(reason: Self.describe(error))
            }
            throw error
        }
    }

    /// Evaluates peek transitions on the cached event list without hitting EventKit every second.
    public func checkPeeks(at now: Date) {
        guard isEnabled else { return }
        let (continuation, peeks) = withLock { state -> (AsyncStream<PeekEvent>.Continuation?, [PeekEvent]) in
            let due = Self.dueJoinPeeks(in: state.events, at: now, seen: &state.notifiedJoinIDs)
            return (state.peeks, due)
        }
        for event in peeks {
            continuation?.yield(event)
        }
    }

    /// Upcoming and ongoing non-all-day events at `now`, sorted by start date.
    public func upcomingMeetings(at now: Date) -> [MeetingEvent] {
        guard isEnabled else { return [] }
        return withLock { $0.events }
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
    }

    /// Ongoing meeting first, else the earliest upcoming meeting.
    public func nextMeeting(at now: Date) -> MeetingEvent? {
        let upcoming = upcomingMeetings(at: now)
        if let ongoing = upcoming.first(where: { $0.isOngoing(at: now) }) {
            return ongoing
        }
        return upcoming.first
    }

    /// Ongoing non-all-day meeting (used for Auto DND and live status).
    public func ongoingMeeting(at now: Date) -> MeetingEvent? {
        upcomingMeetings(at: now).first { $0.isOngoing(at: now) }
    }

    public func collapsedActivity(at now: Date) throws -> LiveActivity? {
        guard isEnabled, status.isAvailable else { return nil }
        guard let meeting = nextMeeting(at: now) else { return nil }

        if meeting.isOngoing(at: now) {
            let short = Self.compactTitle(meeting.title)
            return LiveActivity(
                id: "calendar",
                moduleID: id,
                source: .other,
                text: meeting.hasVideoLink ? "In \(meeting.provider?.displayName ?? "Meeting")" : short,
                accessibilityLabel: "\(meeting.title) in progress",
                isAlert: false,
                deadline: meeting.endDate
            )
        }

        let untilStart = meeting.timeUntilStart(at: now)
        guard untilStart > 0, untilStart <= Self.wingLeadWindow else { return nil }

        let mins = max(1, Int((untilStart / 60).rounded(.up)))
        if untilStart <= Self.joinLeadWindow {
            let label = meeting.hasVideoLink ? "Join · \(mins)m" : "\(Self.compactTitle(meeting.title)) · \(mins)m"
            return LiveActivity(
                id: "calendar",
                moduleID: id,
                source: .other,
                text: label,
                accessibilityLabel: "\(meeting.title) starts in \(mins) minutes" + (meeting.hasVideoLink ? ", join link ready" : ""),
                isAlert: meeting.hasVideoLink,
                deadline: meeting.startDate
            )
        }

        return LiveActivity(
            id: "calendar",
            moduleID: id,
            source: .other,
            text: "\(Self.compactTitle(meeting.title)) · \(mins)m",
            accessibilityLabel: "\(meeting.title) in \(mins) minutes",
            isAlert: false,
            deadline: meeting.startDate
        )
    }

    public func peekEvents() -> AsyncStream<PeekEvent> {
        AsyncStream { continuation in
            withLock { $0.peeks = continuation }
            continuation.onTermination = { [weak self] _ in self?.withLock { $0.peeks = nil } }
        }
    }

    public func accessibilitySummary() -> String {
        let now = clock()
        guard isEnabled else { return "Calendar disabled" }
        guard status.isAvailable else { return "Calendar unavailable" }
        guard let next = nextMeeting(at: now) else { return "No upcoming meetings" }
        if next.isOngoing(at: now) {
            return "In meeting: \(next.title)"
        }
        let mins = max(1, Int((next.timeUntilStart(at: now) / 60).rounded(.up)))
        return "Next meeting: \(next.title) in \(mins) minutes"
    }

    private static func dueJoinPeeks(
        in events: [MeetingEvent],
        at now: Date,
        seen: inout Set<String>
    ) -> [PeekEvent] {
        var result: [PeekEvent] = []
        for event in events where !event.isAllDay {
            let untilStart = event.timeUntilStart(at: now)
            guard untilStart >= -60, untilStart <= joinLeadWindow else { continue }
            guard event.hasVideoLink else { continue }
            guard seen.insert(event.id).inserted else { continue }

            let mins = max(0, Int((untilStart / 60).rounded(.up)))
            let timing = mins <= 0 ? "Starting now" : "In \(mins) min"
            let provider = event.provider?.displayName ?? "Meeting"
            result.append(PeekEvent(
                id: "calendar.join.\(event.id)",
                moduleID: "calendar",
                title: event.title,
                message: "\(timing) · \(provider)",
                priority: .normal,
                duration: 8,
                announcement: "\(event.title), \(timing), \(provider) link ready",
                actionTitle: "Join",
                actionURL: event.joinURL?.absoluteString
            ))
        }
        return result
    }

    private static func compactTitle(_ raw: String, limit: Int = 8) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit - 1)) + "…"
    }

    private static func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let text = localized.errorDescription {
            return text
        }
        return String(describing: error)
    }

    private func withLock<T>(_ body: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }
}
