import Foundation

/// A proleptic Gregorian calendar day with no time zone (the equivalent of Java's `LocalDate`).
public struct CivilDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `yyyy-MM-dd`.
    public init?(_ iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// The calendar day of `instant` in `zone`.
    public init(_ instant: Date, in zone: TimeZone) {
        let local = Int64(floor(instant.timeIntervalSince1970)) + Int64(zone.secondsFromGMT(for: instant))
        self.init(daysSinceEpoch: Int(floorDiv(local, 86_400)))
    }

    /// Days since 1970-01-01 (Howard Hinnant's civil-from-days).
    public init(daysSinceEpoch z0: Int) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.init(year: yoe + era * 400 + (m <= 2 ? 1 : 0), month: m, day: d)
    }

    public var daysSinceEpoch: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = month > 2 ? month - 3 : month + 9
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public func plusDays(_ n: Int) -> CivilDate { CivilDate(daysSinceEpoch: daysSinceEpoch + n) }

    public var dayOfYear: Int { daysSinceEpoch - CivilDate(year: year, month: 1, day: 1).daysSinceEpoch + 1 }

    /// 1 = Monday ... 7 = Sunday.
    public var isoWeekday: Int { ((daysSinceEpoch + 3) % 7 + 7) % 7 + 1 }

    public var isFriday: Bool { isoWeekday == 5 }

    public static func isLeapYear(_ y: Int) -> Bool { (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }

    public var daysInMonth: Int {
        switch month {
        case 2: return CivilDate.isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Midnight at the start of this day in `zone`.
    public func startOfDay(in zone: TimeZone) -> Date {
        let utcMidnight = Double(daysSinceEpoch) * 86_400
        // Offset at the approximate instant, then refined once for zones that change offset that day.
        let guess = Date(timeIntervalSince1970: utcMidnight)
        let first = Double(zone.secondsFromGMT(for: guess))
        let refined = Double(zone.secondsFromGMT(for: Date(timeIntervalSince1970: utcMidnight - first)))
        return Date(timeIntervalSince1970: utcMidnight - refined)
    }

    public static func < (a: CivilDate, b: CivilDate) -> Bool { a.daysSinceEpoch < b.daysSinceEpoch }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
    let q = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
}

func floorMod(_ a: Int64, _ b: Int64) -> Int64 { a - floorDiv(a, b) * b }
