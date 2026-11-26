import Foundation

/// One line of a timetable: a day, its Hijri date and its prayer times.
public struct TimetableRow: Equatable, Sendable {
    public var schedule: PrayerSchedule
    public var hijri: HijriDate
    public var date: CivilDate { schedule.date }
}

/// The monthly timetable and the Ramadan imsakiyah: the same per-day schedule Today shows, laid out
/// for a month. `schedule` is the calculator bound to the saved location, so a table can never
/// disagree with Today. There is deliberately no Imsak column.
public enum Timetable {
    /// Days where the calculator returns nil (polar regions) are left out.
    public static func month(year: Int, month: Int, hijriAdjustment: Int, schedule: (CivilDate) -> PrayerSchedule?) -> [TimetableRow] {
        let first = CivilDate(year: year, month: month, day: 1)
        return rows(from: first, count: first.daysInMonth, hijriAdjustment: hijriAdjustment, schedule: schedule)
    }

    /// The days of the Ramadan `from` falls in, or of the next one when `from` is outside it, in
    /// order (29 or 30 days). Nil if none starts within about a year, which cannot happen.
    public static func ramadan(from: CivilDate, hijriAdjustment: Int, schedule: (CivilDate) -> PrayerSchedule?) -> [TimetableRow]? {
        func isRamadan(_ d: CivilDate) -> Bool { HijriCalendar.of(d, adjustmentDays: hijriAdjustment).month == 9 }
        var start = from
        if isRamadan(start) {
            while isRamadan(start.plusDays(-1)) { start = start.plusDays(-1) }
        } else {
            var scanned = 0
            while !isRamadan(start) {
                start = start.plusDays(1)
                scanned += 1
                if scanned > 400 { return nil }
            }
        }
        var count = 0
        while isRamadan(start.plusDays(count)) { count += 1 }
        return rows(from: start, count: count, hijriAdjustment: hijriAdjustment, schedule: schedule)
    }

    private static func rows(from first: CivilDate, count: Int, hijriAdjustment: Int, schedule: (CivilDate) -> PrayerSchedule?) -> [TimetableRow] {
        (0..<count).compactMap { i in
            let date = first.plusDays(i)
            return schedule(date).map { TimetableRow(schedule: $0, hijri: HijriCalendar.of(date, adjustmentDays: hijriAdjustment)) }
        }
    }
}
