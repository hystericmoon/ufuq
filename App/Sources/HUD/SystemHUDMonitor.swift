import AudioToolbox
import CoreAudio
import CoreGraphics
import Foundation
import ObjectiveC
import UfuqCore

/// Monitors system volume (CoreAudio), display brightness (DisplayServices), and keyboard
/// backlight (CoreBrightness) without requiring Accessibility permissions.
@MainActor
final class SystemHUDMonitor {
    var onReading: ((HUDReading) -> Void)?

    private var tracker = HUDStateTracker()
    private var timer: Timer?
    private var defaultDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var devicePropertyListener: AudioObjectPropertyListenerBlock?

    private typealias DisplayServicesGetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias KeyboardBrightnessGetterIMP = @convention(c) (AnyObject, Selector, UInt64) -> Float

    private lazy var displayServicesGetBrightness: DisplayServicesGetBrightnessFn? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let sym = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(sym, to: DisplayServicesGetBrightnessFn.self)
    }()

    private lazy var keyboardBrightnessClient: AnyObject? = {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        guard let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        return cls.init()
    }()

    func start() {
        stop()
        let now = Date()
        if let vol = readVolume(at: now) { _ = tracker.ingest(vol) }
        if let bright = readBrightness(at: now) { _ = tracker.ingest(bright) }
        if let kbd = readKeyboardBacklight(at: now) { _ = tracker.ingest(kbd) }

        registerCoreAudioListeners()

        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        unregisterCoreAudioListeners()
    }

    private func poll() {
        guard AppSettings.hudEnabled else { return }
        let now = Date()
        if let vol = readVolume(at: now), let event = tracker.ingest(vol) {
            onReading?(event)
        }
        if let bright = readBrightness(at: now), let event = tracker.ingest(bright) {
            onReading?(event)
        }
        if let kbd = readKeyboardBacklight(at: now), let event = tracker.ingest(kbd) {
            onReading?(event)
        }
    }

    private func handleVolumeCallback() {
        guard AppSettings.hudEnabled else { return }
        if let vol = readVolume(at: Date()), let event = tracker.ingest(vol) {
            onReading?(event)
        }
    }

    // MARK: - Readers

    private func readVolume(at now: Date) -> HUDReading? {
        let device = currentDefaultOutputDevice()
        guard device != kAudioObjectUnknown else { return nil }

        var volume: Float32 = 0
        var volSize = UInt32(MemoryLayout<Float32>.size)
        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &volAddr),
              AudioObjectGetPropertyData(device, &volAddr, 0, nil, &volSize, &volume) == noErr else {
            return nil
        }

        var muted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let hasMute = AudioObjectHasProperty(device, &muteAddr)
            && AudioObjectGetPropertyData(device, &muteAddr, 0, nil, &muteSize, &muted) == noErr

        return HUDReading(
            kind: .volume,
            level: Double(volume),
            isMuted: hasMute && muted != 0,
            timestamp: now
        )
    }

    private func readBrightness(at now: Date) -> HUDReading? {
        guard let fn = displayServicesGetBrightness else { return nil }
        var level: Float = 0
        let status = fn(CGMainDisplayID(), &level)
        guard status == 0, level.isFinite else { return nil }
        return HUDReading(kind: .brightness, level: Double(level), timestamp: now)
    }

    private func readKeyboardBacklight(at now: Date) -> HUDReading? {
        guard let client = keyboardBrightnessClient else { return nil }
        let sel = NSSelectorFromString("brightnessForKeyboard:")
        guard client.responds(to: sel),
              let cls: AnyClass = object_getClass(client),
              let method = class_getInstanceMethod(cls, sel) else {
            return nil
        }
        let imp = unsafeBitCast(method_getImplementation(method), to: KeyboardBrightnessGetterIMP.self)
        let level = imp(client, sel, 1)
        guard level.isFinite, level >= 0 else { return nil }
        return HUDReading(kind: .keyboardBacklight, level: Double(level), timestamp: now)
    }

    // MARK: - CoreAudio Listeners

    private func currentDefaultOutputDevice() -> AudioDeviceID {
        var device = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size, &device
        )
        return status == noErr ? device : kAudioObjectUnknown
    }

    private func registerCoreAudioListeners() {
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let defaultBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.rebindDeviceListeners()
                self?.handleVolumeCallback()
            }
        }
        defaultDeviceListener = defaultBlock
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddr,
            DispatchQueue.main,
            defaultBlock
        )
        rebindDeviceListeners()
    }

    private func rebindDeviceListeners() {
        unregisterDeviceListeners()
        let device = currentDefaultOutputDevice()
        guard device != kAudioObjectUnknown else { return }
        defaultDeviceID = device

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleVolumeCallback()
            }
        }
        devicePropertyListener = block

        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(device, &volAddr, DispatchQueue.main, block)

        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(device, &muteAddr, DispatchQueue.main, block)
    }

    private func unregisterCoreAudioListeners() {
        unregisterDeviceListeners()
        if let block = defaultDeviceListener {
            var defaultAddr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultAddr,
                DispatchQueue.main,
                block
            )
            defaultDeviceListener = nil
        }
    }

    private func unregisterDeviceListeners() {
        guard defaultDeviceID != kAudioObjectUnknown, let block = devicePropertyListener else { return }
        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(defaultDeviceID, &volAddr, DispatchQueue.main, block)

        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(defaultDeviceID, &muteAddr, DispatchQueue.main, block)
        defaultDeviceID = kAudioObjectUnknown
        devicePropertyListener = nil
    }
}
