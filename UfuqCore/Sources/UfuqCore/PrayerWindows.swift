import Foundation

public enum WindowType: Equatable, Sendable, CaseIterable {
    case morningAdhkar
    case eveningAdhkar
    /// After praying Subuh until the sun has fully risen.
    case prohibitedAfterSubuh
    /// Short window at zawal, just before Dzuhur.
    case prohibitedZawal
    /// After praying Ashar until Maghrib.
    case prohibitedAfterAshar
    case duha
    case witr

    public var isProhibited: Bool {
        self == .prohibitedAfterSubuh || self == .prohibitedZawal || self == .prohibitedAfterAshar
    }
}

public struct TimeWindow: Equatable, Sendable {
    public var type: WindowType
    public var start: Date
    public var end: Date

    public init(type: WindowType, start: Date, end: Date) {
        self.type = type
        self.start = start
        self.end = end
    }

    public func contains(_ t: Date) -> Bool { t >= start && t < end }
}

/// Derives the day's windows from prayer times:
///  - Morning adhkar: Subuh to sunrise. Evening adhkar: Ashar to Maghrib.
///  - Prohibited: Subuh to sunrise + rise minutes; Dzuhur - zawal minutes to Dzuhur; Ashar to Maghrib.
///  - Duha: end of the sunrise prohibition to the start of the zawal window.
///  - Witr: Isya to next day's Subuh.
/// The after-Subuh and after-Ashar prohibitions begin once that prayer has been prayed; the UI says
/// so in words because the app cannot know when the user prayed.
public enum PrayerWindows {
    public static func forDay(today: PrayerSchedule, tomorrowSubuh: Date, sunriseRiseMinutes: Int, zawalMinutes: Int) -> [TimeWindow] {
        let risen = today.terbit.addingTimeInterval(Double(sunriseRiseMinutes) * 60)
        let zawalStart = today.dzuhur.addingTimeInterval(-Double(zawalMinutes) * 60)
        return [
            TimeWindow(type: .morningAdhkar, start: today.subuh, end: today.terbit),
            TimeWindow(type: .prohibitedAfterSubuh, start: today.subuh, end: risen),
            TimeWindow(type: .duha, start: risen, end: zawalStart),
            TimeWindow(type: .prohibitedZawal, start: zawalStart, end: today.dzuhur),
            TimeWindow(type: .eveningAdhkar, start: today.ashar, end: today.maghrib),
            TimeWindow(type: .prohibitedAfterAshar, start: today.ashar, end: today.maghrib),
            TimeWindow(type: .witr, start: today.isya, end: tomorrowSubuh),
        ].filter { $0.end > $0.start }
    }

    /// Windows active at `now`, most relevant first. Pass yesterday's windows too so that the witr
    /// window running from last night's Isya to this morning's Subuh is found after midnight.
    public static func active(at now: Date, in windows: [TimeWindow]) -> [TimeWindow] {
        windows.filter { $0.contains(now) }
            .sorted { (priority.firstIndex(of: $0.type) ?? 0) < (priority.firstIndex(of: $1.type) ?? 0) }
    }

    private static let priority: [WindowType] = [
        .prohibitedZawal, .morningAdhkar, .eveningAdhkar, .prohibitedAfterSubuh, .prohibitedAfterAshar, .duha, .witr,
    ]
}
