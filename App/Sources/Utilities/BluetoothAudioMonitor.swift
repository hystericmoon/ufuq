import CoreAudio
import Foundation
import IOKit
import UfuqCore

enum BluetoothAudioMonitor {
    static func connectedDevices() -> [AudioAccessory] {
        let audioDevices = bluetoothAudioDeviceNames()
        let batteries = hidBatteryReadings()

        if !audioDevices.isEmpty {
            return audioDevices.map { id, name in
                let kind: AudioAccessoryKind = name.localizedCaseInsensitiveContains("AirPods") ? .airPods : .headphones
                let match = batteries.first { reading in
                    reading.product.localizedCaseInsensitiveContains(name)
                        || name.localizedCaseInsensitiveContains(reading.product)
                        || (kind == .airPods && reading.product.localizedCaseInsensitiveContains("AirPods"))
                }
                return AudioAccessory(
                    id: id,
                    name: name,
                    kind: kind,
                    batteryPercent: match?.battery,
                    leftBatteryPercent: match?.left,
                    rightBatteryPercent: match?.right,
                    caseBatteryPercent: match?.caseBattery
                )
            }
        }
        return []
    }

    private struct HIDBattery {
        var product: String
        var battery: Int?
        var left: Int?
        var right: Int?
        var caseBattery: Int?
    }

    private static func bluetoothAudioDeviceNames() -> [(id: String, name: String)] {
        var prop = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &prop, 0, nil, &size) == noErr,
              size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.stride
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &prop, 0, nil, &size, &ids) == noErr else {
            return []
        }

        var result: [(String, String)] = []
        var seenNames = Set<String>()
        for deviceID in ids {
            var transport: UInt32 = 0
            var tSize = UInt32(MemoryLayout<UInt32>.size)
            var tProp = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyData(deviceID, &tProp, 0, nil, &tSize, &transport) == noErr else { continue }
            guard transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE else {
                continue
            }

            var nameRef: Unmanaged<CFString>?
            var nSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var nProp = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyData(deviceID, &nProp, 0, nil, &nSize, &nameRef) == noErr,
                  let cfName = nameRef?.takeRetainedValue() else { continue }
            let name = cfName as String
            if seenNames.insert(name).inserted {
                result.append((name, name))
            }
        }
        return result
    }

    private static func hidBatteryReadings() -> [HIDBattery] {
        guard let matching = IOServiceMatching("AppleDeviceManagementHIDEventService") else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var readings: [HIDBattery] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = propsRef?.takeRetainedValue() as? [String: Any] else { continue }
            guard let product = dict["Product"] as? String else { continue }
            readings.append(HIDBattery(
                product: product,
                battery: dict["BatteryPercent"] as? Int,
                left: dict["BatteryPercentLeft"] as? Int,
                right: dict["BatteryPercentRight"] as? Int,
                caseBattery: dict["BatteryPercentCase"] as? Int
            ))
        }
        return readings
    }
}
