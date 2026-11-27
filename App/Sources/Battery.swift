import Foundation
import IOKit.ps

/// The internal battery, for the System tile. Nil on Macs without one (the tile is then not shown).
struct BatteryStatus: Equatable {
    var percent: Int
    var isCharging: Bool
    var isPluggedIn: Bool

    var stateText: String {
        if isCharging { return "Charging" }
        if isPluggedIn { return percent >= 95 ? "Charged" : "Not charging" }
        return "On battery"
    }
}

enum BatteryReader {
    static func read() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description["Type"] as? String == "InternalBattery",
                  let current = description["Current Capacity"] as? Int,
                  let maximum = description["Max Capacity"] as? Int, maximum > 0
            else { continue }
            let percent = Int((Double(current) / Double(maximum) * 100).rounded())
            return BatteryStatus(
                percent: min(max(percent, 0), 100),
                isCharging: description["Is Charging"] as? Bool ?? false,
                isPluggedIn: description["Power Source State"] as? String == "AC Power")
        }
        return nil
    }
}
