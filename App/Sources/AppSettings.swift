import Foundation
import UfuqCore

enum AppSettings {
    /// Open the expanded panel when the pointer enters the notch. Default off.
    static let hoverKey = "hoverToOpen"

    static var hoverEnabled: Bool {
        UserDefaults.standard.bool(forKey: hoverKey)
    }

    /// Jakarta, the default until the prayer settings arrive.
    static let defaultLocation = PrayerLocation(
        name: "Jakarta", latitude: -6.2088, longitude: 106.8456,
        timeZone: TimeZone(identifier: "Asia/Jakarta") ?? TimeZone(secondsFromGMT: 7 * 3600) ?? .current)
}
