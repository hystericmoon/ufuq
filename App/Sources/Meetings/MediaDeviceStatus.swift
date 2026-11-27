import CoreAudio
import CoreMediaIO
import Foundation

struct MediaDeviceSnapshot: Equatable, Sendable {
    var isMicInUse = false
    var isMicMuted = false
    var canMuteMic = false
    var isCameraInUse = false
}

/// Reads mic/camera active state and mic mute via CoreAudio + CoreMediaIO (no TCC prompts).
@MainActor
final class MediaDeviceMonitor: ObservableObject {
    static let shared = MediaDeviceMonitor()

    @Published private(set) var snapshot = MediaDeviceSnapshot()

    func refresh() {
        let next = Self.readSnapshot()
        if next != snapshot {
            snapshot = next
        }
    }

    func toggleMicMute() {
        let device = Self.defaultInputDevice()
        guard device != kAudioObjectUnknown else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var isSettable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &addr),
              AudioObjectIsPropertySettable(device, &addr, &isSettable) == noErr,
              isSettable.boolValue else { return }
        var current: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &current) == noErr else { return }
        var next: UInt32 = current == 0 ? 1 : 0
        if AudioObjectSetPropertyData(device, &addr, 0, nil, size, &next) == noErr {
            refresh()
        }
    }

    nonisolated static func readSnapshot() -> MediaDeviceSnapshot {
        let inputDevice = defaultInputDevice()
        var micInUse = false
        var micMuted = false
        var canMute = false

        if inputDevice != kAudioObjectUnknown {
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectHasProperty(inputDevice, &runningAddr),
               AudioObjectGetPropertyData(inputDevice, &runningAddr, 0, nil, &runningSize, &running) == noErr {
                micInUse = running != 0
            }

            var mute: UInt32 = 0
            var muteSize = UInt32(MemoryLayout<UInt32>.size)
            var muteAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectHasProperty(inputDevice, &muteAddr),
               AudioObjectGetPropertyData(inputDevice, &muteAddr, 0, nil, &muteSize, &mute) == noErr {
                micMuted = mute != 0
                var settable: DarwinBoolean = false
                if AudioObjectIsPropertySettable(inputDevice, &muteAddr, &settable) == noErr {
                    canMute = settable.boolValue
                }
            }
        }

        return MediaDeviceSnapshot(
            isMicInUse: micInUse,
            isMicMuted: micMuted,
            canMuteMic: canMute,
            isCameraInUse: anyCameraRunning()
        )
    }

    private nonisolated static func defaultInputDevice() -> AudioDeviceID {
        var device = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        return status == noErr ? device : kAudioObjectUnknown
    }

    private nonisolated static func anyCameraRunning() -> Bool {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return false
        }
        let count = Int(dataSize) / MemoryLayout<CMIODeviceID>.size
        var devices = [CMIODeviceID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, dataSize, &used, &devices) == noErr else {
            return false
        }

        var runningAddr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        for device in devices {
            var running: UInt32 = 0
            var runningUsed: UInt32 = 0
            let runningSize = UInt32(MemoryLayout<UInt32>.size)
            if CMIOObjectHasProperty(device, &runningAddr),
               CMIOObjectGetPropertyData(device, &runningAddr, 0, nil, runningSize, &runningUsed, &running) == noErr,
               running != 0 {
                return true
            }
        }
        return false
    }
}
