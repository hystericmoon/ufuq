import Foundation

public enum HUDKind: String, Equatable, Sendable, CaseIterable {
    case volume
    case brightness
    case keyboardBacklight

    public var displayName: String {
        switch self {
        case .volume: return "Volume"
        case .brightness: return "Brightness"
        case .keyboardBacklight: return "Keyboard backlight"
        }
    }
}

public struct HUDReading: Equatable, Sendable {
    public var kind: HUDKind
    public var level: Double
    public var isMuted: Bool
    public var timestamp: Date

    public init(kind: HUDKind, level: Double, isMuted: Bool = false, timestamp: Date = Date()) {
        self.kind = kind
        self.level = level.isFinite ? min(max(level, 0), 1) : 0
        self.isMuted = isMuted
        self.timestamp = timestamp
    }

    public var percent: Int {
        isMuted ? 0 : Int((level * 100).rounded())
    }

    public var iconName: String {
        switch kind {
        case .volume:
            if isMuted || level <= 0.001 { return "speaker.slash.fill" }
            if level < 0.34 { return "speaker.wave.1.fill" }
            if level < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .keyboardBacklight:
            return level < 0.5 ? "light.min" : "light.max"
        }
    }

    public var accessibilityLabel: String {
        if kind == .volume && isMuted {
            return "Volume muted"
        }
        return "\(kind.displayName) \(percent) percent"
    }
}

/// Tracks baselines per HUD kind so app launch never flashes a stale HUD, and triggers only on
/// real level or mute changes.
public struct HUDStateTracker: Equatable, Sendable {
    public var displayDuration: TimeInterval
    public private(set) var active: HUDReading?
    private var baselines: [HUDKind: HUDReading] = [:]

    public init(displayDuration: TimeInterval = 1.6) {
        self.displayDuration = displayDuration
    }

    @discardableResult
    public mutating func ingest(_ reading: HUDReading) -> HUDReading? {
        guard let prev = baselines[reading.kind] else {
            baselines[reading.kind] = reading
            return nil
        }
        let changed = abs(reading.level - prev.level) >= 0.005 || reading.isMuted != prev.isMuted
        guard changed else { return nil }
        baselines[reading.kind] = reading
        active = reading
        return reading
    }

    @discardableResult
    public mutating func expire(at now: Date) -> Bool {
        guard let active, now.timeIntervalSince(active.timestamp) >= displayDuration else {
            return false
        }
        self.active = nil
        return true
    }
}
