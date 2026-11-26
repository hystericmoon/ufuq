import Foundation

public enum PrayerModuleError: Error, Equatable, CustomStringConvertible {
    /// No times can be calculated for the place (e.g. polar regions).
    case noTimes

    public var description: String { "Prayer times unavailable for this location" }
}

/// Text helpers for the next-prayer countdown.
public enum PrayerFormat {
    /// "15:12" in the given zone (24-hour, locale independent).
    public static func clock(_ date: Date, in zone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// "1 hour 12 minutes", "45 minutes", "2 hours", "less than a minute". Rounds up to the minute.
    public static func spoken(_ interval: TimeInterval) -> String {
        let minutes = Int((max(0, interval) / 60).rounded(.up))
        if minutes == 0 { return "less than a minute" }
        let h = minutes / 60
        let m = minutes % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) \(h == 1 ? "hour" : "hours")") }
        if m > 0 { parts.append("\(m) \(m == 1 ? "minute" : "minutes")") }
        return parts.joined(separator: " ")
    }
}

/// Peek alerts around the adhan: a normal one shortly before, a critical one at the adhan time.
public enum PrayerPeeks {
    public static let defaultLead: TimeInterval = 10 * 60
    /// How long after the adhan time the critical alert still counts as due.
    public static let adhanWindow: TimeInterval = 60

    /// "Ashar in 10 minutes", normal priority.
    public static func preAdhan(for prayer: NextPrayer, zone: TimeZone, date: CivilDate, now: Date, lead: TimeInterval = defaultLead) -> PeekEvent? {
        let remaining = prayer.time.timeIntervalSince(now)
        guard remaining > 0, remaining <= lead else { return nil }
        let name = prayer.displayName
        let when = PrayerFormat.clock(prayer.time, in: zone)
        return PeekEvent(
            id: "prayer.pre.\(prayer.prayer.rawValue).\(date)",
            moduleID: "prayer",
            title: name,
            message: "in \(PrayerFormat.spoken(remaining)), at \(when)",
            priority: .normal,
            announcement: "\(name) in \(PrayerFormat.spoken(remaining))")
    }

    /// "Ashar now", critical priority.
    public static func adhan(prayer: Prayer, isJumuah: Bool, time: Date, zone: TimeZone, date: CivilDate) -> PeekEvent {
        let name = isJumuah ? "Jumat" : prayer.displayName
        return PeekEvent(
            id: "prayer.adhan.\(prayer.rawValue).\(date)",
            moduleID: "prayer",
            title: name,
            message: "Time for \(name), \(PrayerFormat.clock(time, in: zone))",
            priority: .critical,
            announcement: "Time for \(name)")
    }
}

/// The prayer module: left wing, next prayer with a countdown deadline, peeks around the adhan.
/// Everything is calculated locally, so it works offline.
public final class PrayerModule: UfuqModule {
    public let id = "prayer"
    public let title = "Prayer"
    public var isEnabled = true

    public var location: PrayerLocation
    public var settings: CalculationSettings
    public var preAdhanLead: TimeInterval
    private let calculator: PrayerCalculator
    private let clock: () -> Date

    public init(
        location: PrayerLocation = .jakarta,
        settings: CalculationSettings = CalculationSettings(),
        preAdhanLead: TimeInterval = PrayerPeeks.defaultLead,
        calculator: PrayerCalculator = PrayerCalculator(),
        clock: @escaping () -> Date = Date.init
    ) {
        self.location = location
        self.settings = settings
        self.preAdhanLead = preAdhanLead
        self.calculator = calculator
        self.clock = clock
    }

    public var status: ModuleStatus {
        snapshot(at: clock()) == nil ? .unavailable(reason: PrayerModuleError.noTimes.description) : .ok
    }

    public func snapshot(at now: Date) -> PrayerSnapshot? {
        PrayerSnapshots.at(now, location: location, settings: settings, calculator: calculator)
    }

    public func collapsedActivity(at now: Date) throws -> LiveActivity? {
        guard let snap = snapshot(at: now) else { throw PrayerModuleError.noTimes }
        // Right at the adhan the activity is an alert for the prayer that just began.
        if let due = justStarted(in: snap, at: now) {
            let name = due.isJumuah ? "Jumat" : due.prayer.displayName
            return LiveActivity(
                id: "prayer.next", moduleID: id, source: .prayer,
                text: "\(name) now",
                accessibilityLabel: "\(name) now",
                isAlert: true, deadline: due.time)
        }
        let next = snap.next
        return LiveActivity(
            id: "prayer.next", moduleID: id, source: .prayer,
            text: "\(next.displayName) \(PrayerFormat.clock(next.time, in: location.timeZone))",
            accessibilityLabel: "\(next.displayName) in \(PrayerFormat.spoken(next.remaining(from: now)))",
            deadline: next.time)
    }

    public func accessibilitySummary() -> String {
        let now = clock()
        guard let snap = snapshot(at: now) else { return "Prayer times unavailable" }
        let n = snap.next
        return "Next prayer \(n.displayName) at \(PrayerFormat.clock(n.time, in: location.timeZone)), in \(PrayerFormat.spoken(n.remaining(from: now)))"
    }

    /// The peek that is due at `now`, if any: critical at the adhan (within `adhanWindow`), otherwise
    /// the pre-adhan peek once the next prayer is within `preAdhanLead`.
    public func duePeek(at now: Date) -> PeekEvent? {
        guard let snap = snapshot(at: now) else { return nil }
        if let due = justStarted(in: snap, at: now) {
            return PrayerPeeks.adhan(prayer: due.prayer, isJumuah: due.isJumuah, time: due.time, zone: location.timeZone, date: snap.date)
        }
        return PrayerPeeks.preAdhan(for: snap.next, zone: location.timeZone, date: snap.date, now: now, lead: preAdhanLead)
    }

    /// Yields each due peek once, polling every 15 seconds. Ends when the consumer stops.
    public func peekEvents() -> AsyncStream<PeekEvent> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                var seen = Set<String>()
                while !Task.isCancelled {
                    guard let self else { break }
                    if let peek = self.duePeek(at: self.clock()), seen.insert(peek.id).inserted {
                        continuation.yield(peek)
                    }
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func justStarted(in snap: PrayerSnapshot, at now: Date) -> (prayer: Prayer, time: Date, isJumuah: Bool)? {
        for slot in snap.today where slot.prayer != .terbit {
            let elapsed = now.timeIntervalSince(slot.time)
            if elapsed >= 0, elapsed < PrayerPeeks.adhanWindow {
                return (slot.prayer, slot.time, slot.prayer == .dzuhur && snap.date.isFriday)
            }
        }
        return nil
    }
}
