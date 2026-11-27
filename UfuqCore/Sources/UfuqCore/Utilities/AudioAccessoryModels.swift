import Foundation

public enum AudioAccessoryKind: String, Codable, Equatable, Sendable {
    case airPods
    case headphones
    case speaker
    case other
}

public struct AudioAccessory: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: AudioAccessoryKind
    public var batteryPercent: Int?
    public var leftBatteryPercent: Int?
    public var rightBatteryPercent: Int?
    public var caseBatteryPercent: Int?

    public init(
        id: String,
        name: String,
        kind: AudioAccessoryKind = .other,
        batteryPercent: Int? = nil,
        leftBatteryPercent: Int? = nil,
        rightBatteryPercent: Int? = nil,
        caseBatteryPercent: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.batteryPercent = batteryPercent.map { min(100, max(0, $0)) }
        self.leftBatteryPercent = leftBatteryPercent.map { min(100, max(0, $0)) }
        self.rightBatteryPercent = rightBatteryPercent.map { min(100, max(0, $0)) }
        self.caseBatteryPercent = caseBatteryPercent.map { min(100, max(0, $0)) }
    }

    public var displayBattery: String? {
        if let left = leftBatteryPercent, let right = rightBatteryPercent {
            if abs(left - right) >= 5 {
                return "L \(left)% · R \(right)%"
            }
            return "\(min(left, right))%"
        }
        if let battery = batteryPercent ?? leftBatteryPercent ?? rightBatteryPercent {
            return "\(battery)%"
        }
        return nil
    }

    public var shortWingLabel: String {
        let base = kind == .airPods ? "AirPods" : name
        if let battery = displayBattery {
            return "\(base) \(battery)"
        }
        return base
    }
}

public final class AudioAccessoryModule: UfuqModule, @unchecked Sendable {
    public let id = "audioAccessory"
    public let title = "Audio Devices"
    public var isEnabled: Bool

    public static let connectionWingWindow: TimeInterval = 20

    private struct State {
        var status: ModuleStatus = .ok
        var hasBaseline = false
        var knownIDs: Set<String> = []
        var connected: [AudioAccessory] = []
        var recentConnection: (device: AudioAccessory, at: Date)?
        var peeks: AsyncStream<PeekEvent>.Continuation?
    }

    private let provider: @Sendable () -> [AudioAccessory]
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var state = State()

    public init(
        provider: @escaping @Sendable () -> [AudioAccessory],
        isEnabled: Bool = true,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.isEnabled = isEnabled
        self.clock = clock
    }

    public var status: ModuleStatus { withLock { $0.status } }

    public var connectedAccessories: [AudioAccessory] {
        guard isEnabled else { return [] }
        return withLock { $0.connected }
    }

    public func refresh() async throws {
        guard isEnabled else {
            withLock {
                $0.connected = []
                $0.recentConnection = nil
                $0.status = .ok
            }
            return
        }
        let now = clock()
        let devices = provider()
        let (continuation, peeks) = withLock { state -> (AsyncStream<PeekEvent>.Continuation?, [PeekEvent]) in
            state.status = .ok
            state.connected = devices
            let currentIDs = Set(devices.map(\.id))

            if !state.hasBaseline {
                state.hasBaseline = true
                state.knownIDs = currentIDs
                return (nil, [])
            }

            var events: [PeekEvent] = []
            for device in devices where !state.knownIDs.contains(device.id) {
                state.recentConnection = (device, now)
                let message = device.displayBattery.map { "Battery \($0)" } ?? "Bluetooth audio ready"
                events.append(PeekEvent(
                    id: "audio.connected.\(device.id)",
                    moduleID: id,
                    title: "\(device.name) connected",
                    message: message,
                    priority: .normal
                ))
            }
            state.knownIDs = currentIDs
            return (state.peeks, events)
        }
        for event in peeks {
            continuation?.yield(event)
        }
    }

    public func collapsedActivity(at now: Date) throws -> LiveActivity? {
        guard isEnabled else { return nil }
        return withLock { state in
            guard let recent = state.recentConnection,
                  now.timeIntervalSince(recent.at) <= Self.connectionWingWindow else {
                return nil
            }
            return LiveActivity(
                id: "audio.recent.\(recent.device.id)",
                moduleID: id,
                source: .other,
                text: recent.device.shortWingLabel,
                accessibilityLabel: "\(recent.device.name) connected" + (recent.device.displayBattery.map { ", battery \($0)" } ?? "")
            )
        }
    }

    public func peekEvents() -> AsyncStream<PeekEvent> {
        AsyncStream { continuation in
            withLock { $0.peeks = continuation }
        }
    }

    public func accessibilitySummary() -> String {
        let list = connectedAccessories
        if list.isEmpty { return "No Bluetooth audio connected" }
        return list.map { $0.shortWingLabel }.joined(separator: ", ")
    }

    private func withLock<T>(_ body: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }
}
