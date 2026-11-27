@preconcurrency import EventKit
import Foundation
import UfuqCore

@MainActor
enum CalendarControl {
    static var refresh: () -> Void = {}
}

enum CalendarAccessError: Error, LocalizedError {
    case denied

    var errorDescription: String? { "Calendar access denied" }
}

/// Reads upcoming events from EventKit once authorized; never triggers a permission prompt on launch.
final class EventKitCalendarSource: CalendarEventSource, @unchecked Sendable {
    static let shared = EventKitCalendarSource()

    private let store = EKEventStore()
    private let lock = NSLock()

    static var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    static var isAuthorized: Bool {
        let status = authorizationStatus
        if status == .fullAccess { return true }
        #if !os(macOS)
        return false
        #else
        if #unavailable(macOS 14.0) {
            return status == .authorized
        }
        return false
        #endif
    }

    static var isDenied: Bool {
        let status = authorizationStatus
        return status == .denied || status == .restricted
    }

    func requestAccess() async -> Bool {
        if Self.isAuthorized { return true }
        do {
            let granted = try await store.requestFullAccessToEvents()
            return granted
        } catch {
            NSLog("Ufuq: Calendar access request failed: \(error)")
            return false
        }
    }

    func events(from start: Date, to end: Date) async throws -> [MeetingEvent] {
        if Self.isDenied {
            throw CalendarAccessError.denied
        }
        guard Self.isAuthorized else {
            return []
        }

        return withLock {
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            let ekEvents = store.events(matching: predicate)
            return ekEvents.compactMap { Self.convert($0) }
        }
    }

    private static func convert(_ event: EKEvent) -> MeetingEvent? {
        guard event.status != .canceled else { return nil }
        let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = (title?.isEmpty == false) ? title! : "Untitled Event"
        let link = MeetingURLParser.extractJoinLink(url: event.url, location: event.location, notes: event.notes)
        let identifier = event.calendarItemIdentifier + "@" + String(Int(event.startDate.timeIntervalSince1970))
        return MeetingEvent(
            id: identifier,
            title: resolvedTitle,
            startDate: event.startDate,
            endDate: event.endDate,
            joinURL: link?.url,
            provider: link?.provider,
            calendarName: event.calendar.title,
            isAllDay: event.isAllDay
        )
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
