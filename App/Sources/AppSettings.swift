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

    /// Show system HUDs (volume, brightness, keyboard backlight) as a notch capsule. Default on.
    static let hudKey = "systemHUDsEnabled"

    static var hudEnabled: Bool {
        UserDefaults.standard.object(forKey: hudKey) as? Bool ?? true
    }

    /// Keep recent text copies in memory in the Clipboard tile. Default on.
    static let clipboardKey = "clipboardHistoryEnabled"

    static var clipboardEnabled: Bool {
        UserDefaults.standard.object(forKey: clipboardKey) as? Bool ?? true
    }

    /// Show upcoming Calendar meetings and Join links. Default on (reads only once permission is granted).
    static let calendarKey = "calendarMeetingsEnabled"

    static var calendarEnabled: Bool {
        UserDefaults.standard.object(forKey: calendarKey) as? Bool ?? true
    }

    /// Show live mic and camera indicators in the Meetings tile. Default on.
    static let meetingDevicesKey = "meetingDeviceStatusEnabled"

    static var meetingDevicesEnabled: Bool {
        UserDefaults.standard.object(forKey: meetingDevicesKey) as? Bool ?? true
    }

    /// Automatically run the configured Focus Shortcut during active video meetings. Default off.
    static let autoDNDKey = "autoDNDEnabled"

    static var autoDNDEnabled: Bool {
        UserDefaults.standard.bool(forKey: autoDNDKey)
    }

    static let autoDNDShortcutKey = "autoDNDShortcutName"

    static var autoDNDShortcutName: String {
        UserDefaults.standard.string(forKey: autoDNDShortcutKey) ?? ""
    }

    static let accentKey = "appearanceAccent"
    static let glassStyleKey = "appearanceGlassStyle"
    static let shapeStyleKey = "appearanceShapeStyle"

    static var accent: UfuqAccent {
        let raw = UserDefaults.standard.string(forKey: accentKey) ?? ""
        return UfuqAccent(rawValue: raw) ?? .emerald
    }

    static var glassStyle: UfuqGlassStyle {
        let raw = UserDefaults.standard.string(forKey: glassStyleKey) ?? ""
        return UfuqGlassStyle(rawValue: raw) ?? .automatic
    }

    static var shapeStyle: UfuqShapeStyle {
        let raw = UserDefaults.standard.string(forKey: shapeStyleKey) ?? ""
        return UfuqShapeStyle(rawValue: raw) ?? .standard
    }

    static let systemStatsKey = "systemStatsEnabled"
    static var systemStatsEnabled: Bool {
        UserDefaults.standard.object(forKey: systemStatsKey) as? Bool ?? true
    }

    static let downloadsKey = "downloadsMonitorEnabled"
    static var downloadsEnabled: Bool {
        UserDefaults.standard.object(forKey: downloadsKey) as? Bool ?? true
    }

    static let audioAccessoryKey = "audioAccessoryEnabled"
    static var audioAccessoryEnabled: Bool {
        UserDefaults.standard.object(forKey: audioAccessoryKey) as? Bool ?? true
    }

    static let onboardingDoneKey = "hasCompletedOnboarding"
    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: onboardingDoneKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardingDoneKey) }
    }

    /// Sparkle keeps its own automatic-check preference; this only names the feed host
    /// shown in the privacy line in Settings.
    static let updateDisclosure = "Ufuq contacts GitHub to check for new versions."

    /// Jakarta, the default until the prayer settings arrive.
    static let defaultLocation = PrayerLocation(
        name: "Jakarta", latitude: -6.2088, longitude: 106.8456,
        timeZone: TimeZone(identifier: "Asia/Jakarta") ?? TimeZone(secondsFromGMT: 7 * 3600) ?? .current)
}
