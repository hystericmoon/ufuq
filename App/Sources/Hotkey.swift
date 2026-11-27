import Carbon.HIToolbox
import Foundation

/// A global hotkey through Carbon `RegisterEventHotKey`; needs no accessibility permission.
final class Hotkey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    private let id: UInt32

    /// Default: Option + Space.
    static let defaultKeyCode = UInt32(kVK_Space)
    static let defaultModifiers = UInt32(optionKey)
    /// Open the file tray: Option + Shift + T.
    static let trayKeyCode = UInt32(kVK_ANSI_T)
    static let trayModifiers = UInt32(optionKey | shiftKey)

    /// Returns nil if the system refuses the registration (e.g. the combination is taken).
    init?(keyCode: UInt32 = Hotkey.defaultKeyCode,
          modifiers: UInt32 = Hotkey.defaultModifiers,
          id: UInt32 = 1,
          action: @escaping () -> Void) {
        self.action = action
        self.id = id

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))

        let proc: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<Hotkey>.fromOpaque(userData).takeUnretainedValue()
            // Every handler sees every hotkey press; act only on our own.
            var pressed = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard status == noErr, pressed.id == hotkey.id else { return OSStatus(eventNotHandledErr) }
            hotkey.action()
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(), proc, 1, &eventType, selfPtr, &handlerRef)
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x5546_5131), id: id)  // 'UFQ1'
        let registerStatus = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registerStatus == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
