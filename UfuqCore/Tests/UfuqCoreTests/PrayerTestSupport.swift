import Foundation
@testable import UfuqCore

enum PrayerTestSupport {
    static let jakartaZone = TimeZone(identifier: "Asia/Jakarta")!

    /// A local wall-clock moment in `zone`.
    static func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0, zone: TimeZone = jakartaZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    /// "HH:mm" local time as minutes since midnight.
    static func minutes(_ date: Date, in zone: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return c.hour! * 60 + c.minute!
    }

    static func parse(_ hhmm: String) -> Int {
        let p = hhmm.split(separator: ":").map { Int($0)! }
        return p[0] * 60 + p[1]
    }
}
