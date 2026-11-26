import Foundation

public struct SlotTime: Equatable, Sendable {
    public var prayer: Prayer
    public var time: Date
}

/// The next obligatory prayer. On Fridays Dzuhur is Jumat (Jumuah).
public struct NextPrayer: Equatable, Sendable {
    public var prayer: Prayer
    public var time: Date
    public var isJumuah: Bool

    /// Name to show: "Jumat" for Friday's Dzuhur, otherwise the prayer's name.
    public var displayName: String { isJumuah ? "Jumat" : prayer.displayName }

    /// Time left until the prayer, never negative.
    public func remaining(from now: Date) -> TimeInterval { max(0, time.timeIntervalSince(now)) }
}

/// What glanceable surfaces show at a moment.
public struct PrayerSnapshot: Equatable, Sendable {
    public var locationName: String
    public var timeZone: TimeZone
    public var date: CivilDate
    /// Today's six times, in order.
    public var today: [SlotTime]
    public var next: NextPrayer

    /// The slot in `today` that `next` refers to, or nil when the next prayer is tomorrow's Subuh.
    public var nextSlot: Prayer? { today.first { $0.time == next.time }?.prayer }
}

public enum PrayerSnapshots {
    /// Nil when the calculator cannot produce times for the place (polar regions).
    public static func at(
        _ now: Date,
        location: PrayerLocation,
        settings: CalculationSettings = CalculationSettings(),
        calculator: PrayerCalculator = PrayerCalculator()
    ) -> PrayerSnapshot? {
        let date = CivilDate(now, in: location.timeZone)
        guard let today = calculator.schedule(date: date, location: location, settings: settings),
              let tomorrow = calculator.schedule(date: date.plusDays(1), location: location, settings: settings)
        else { return nil }
        return PrayerSnapshot(
            locationName: location.name,
            timeZone: location.timeZone,
            date: date,
            today: today.all.map { SlotTime(prayer: $0.prayer, time: $0.time) },
            next: nextPrayer(after: now, in: [today, tomorrow]))
    }

    /// The first of the five prayers strictly after `now`, across the given consecutive days.
    public static func nextPrayer(after now: Date, in days: [PrayerSchedule]) -> NextPrayer {
        for day in days {
            for prayer in Prayer.five {
                let time = day.time(prayer)
                if time > now {
                    return NextPrayer(prayer: prayer, time: time, isJumuah: prayer == .dzuhur && day.date.isFriday)
                }
            }
        }
        // Callers pass today and tomorrow, so tomorrow's Subuh is always after now.
        let last = days[days.count - 1]
        return NextPrayer(prayer: .subuh, time: last.subuh, isJumuah: false)
    }

    /// When glanceable surfaces next need redrawing: the next of today's six times, or the start
    /// of tomorrow.
    public static func nextRefresh(after now: Date, snapshot: PrayerSnapshot) -> Date {
        snapshot.today.map(\.time).first { $0 > now }
            ?? snapshot.date.plusDays(1).startOfDay(in: snapshot.timeZone)
    }
}
