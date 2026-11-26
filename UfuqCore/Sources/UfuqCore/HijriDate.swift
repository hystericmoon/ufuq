import Foundation

public struct HijriDate: Equatable, Sendable {
    public var day: Int
    public var month: Int
    public var year: Int

    public init(day: Int, month: Int, year: Int) {
        self.day = day
        self.month = month
        self.year = year
    }
}

/// Hijri date from the Umm al-Qura calendar, shifted by the user's adjustment (-1, 0, +1 days)
/// to match local sighting.
public enum HijriCalendar {
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .islamicUmmAlQura)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    public static func of(_ date: CivilDate, adjustmentDays: Int) -> HijriDate {
        let shifted = date.plusDays(min(1, max(-1, adjustmentDays)))
        // Noon UTC of the civil day, so no zone shift can move it to another day.
        let instant = Date(timeIntervalSince1970: Double(shifted.daysSinceEpoch) * 86_400 + 43_200)
        let c = calendar.dateComponents([.year, .month, .day], from: instant)
        return HijriDate(day: c.day ?? 1, month: c.month ?? 1, year: c.year ?? 1)
    }

    public static let monthNames = [
        "Muharram", "Safar", "Rabiul Awal", "Rabiul Akhir", "Jumadil Awal", "Jumadil Akhir",
        "Rajab", "Syaban", "Ramadhan", "Syawal", "Dzulqadah", "Dzulhijjah",
    ]
}
