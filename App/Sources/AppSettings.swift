import Foundation
import UfuqCore

enum AppSettings {
    /// Open the expanded panel when the pointer enters the notch. Default off.
    static let hoverKey = "hoverToOpen"

    static var hoverEnabled: Bool {
        UserDefaults.standard.bool(forKey: hoverKey)
    }

    /// Show an island on every display, not only the notch display. Default on.
    static let allDisplaysKey = "islandOnAllDisplays"

    static var allDisplays: Bool {
        UserDefaults.standard.object(forKey: allDisplaysKey) as? Bool ?? true
    }

    /// Share usage and agent status with a paired phone on the local network. Default off.
    static let syncKey = "shareWithPhone"

    static var syncEnabled: Bool {
        UserDefaults.standard.bool(forKey: syncKey)
    }

    /// Sparkle keeps its own automatic-check preference; this only names the feed host
    /// shown in the privacy line in Settings.
    static let updateDisclosure = "Ufuq contacts GitHub to check for new versions."

    /// Jakarta, the default until the prayer settings arrive.
    static let defaultLocation = PrayerLocation(
        name: "Jakarta", latitude: -6.2088, longitude: 106.8456,
        timeZone: TimeZone(identifier: "Asia/Jakarta") ?? TimeZone(secondsFromGMT: 7 * 3600) ?? .current)
}
