import Foundation

public enum TimerMode: String, Codable, Equatable, Sendable, CaseIterable {
    case countdown
    case pomodoroFocus
    case pomodoroShortBreak
    case pomodoroLongBreak

    public var displayName: String {
        switch self {
        case .countdown: return "Timer"
        case .pomodoroFocus: return "Focus"
        case .pomodoroShortBreak: return "Short break"
        case .pomodoroLongBreak: return "Long break"
        }
    }
}

public enum TimerStatus: String, Codable, Equatable, Sendable {
    case idle
    case running
    case paused
    case finished
}

public struct TimerSnapshot: Equatable, Sendable {
    public var mode: TimerMode
    public var status: TimerStatus
    public var totalDuration: TimeInterval
    public var remaining: TimeInterval
    public var targetDate: Date?
    public var cycleCount: Int

    public init(
        mode: TimerMode,
        status: TimerStatus,
        totalDuration: TimeInterval,
        remaining: TimeInterval,
        targetDate: Date? = nil,
        cycleCount: Int = 0
    ) {
        self.mode = mode
        self.status = status
        self.totalDuration = totalDuration
        self.remaining = max(0, remaining)
        self.targetDate = targetDate
        self.cycleCount = cycleCount
    }

    public var progress: Double {
        guard totalDuration > 0 else { return 0 }
        let elapsed = totalDuration - remaining
        return min(1, max(0, elapsed / totalDuration))
    }

    public var formattedRemaining: String {
        TimerFormat.formatClock(remaining)
    }
}

public enum TimerFormat {
    public static func formatClock(_ seconds: TimeInterval) -> String {
        let clamped = max(0, Int(ceil(seconds)))
        let h = clamped / 3600
        let m = (clamped % 3600) / 60
        let s = clamped % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    public static func accessibilityDuration(_ seconds: TimeInterval) -> String {
        let clamped = max(0, Int(ceil(seconds)))
        let h = clamped / 3600
        let m = (clamped % 3600) / 60
        let s = clamped % 60
        var parts: [String] = []
        if h > 0 { parts.append(h == 1 ? "1 hour" : "\(h) hours") }
        if m > 0 { parts.append(m == 1 ? "1 minute" : "\(m) minutes") }
        if s > 0 || parts.isEmpty { parts.append(s == 1 ? "1 second" : "\(s) seconds") }
        return parts.joined(separator: " ")
    }
}

public final class TimerModule: UfuqModule, @unchecked Sendable {
    public let id = "timer"
    public let title = "Timer"
    public var isEnabled: Bool

    public let focusDuration: TimeInterval
    public let shortBreakDuration: TimeInterval
    public let longBreakDuration: TimeInterval
    public let cyclesBeforeLongBreak: Int

    private struct State {
        var mode: TimerMode = .countdown
        var status: TimerStatus = .idle
        var totalDuration: TimeInterval = 0
        var pausedRemaining: TimeInterval = 0
        var targetDate: Date?
        var finishedAt: Date?
        var cycleCount: Int = 0
        var runSequence: Int = 0
        var peekedRunSequence: Int = 0
        var peeks: AsyncStream<PeekEvent>.Continuation?
    }

    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var state = State()

    public init(
        focusDuration: TimeInterval = 25 * 60,
        shortBreakDuration: TimeInterval = 5 * 60,
        longBreakDuration: TimeInterval = 15 * 60,
        cyclesBeforeLongBreak: Int = 4,
        isEnabled: Bool = true,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.focusDuration = max(1, focusDuration)
        self.shortBreakDuration = max(1, shortBreakDuration)
        self.longBreakDuration = max(1, longBreakDuration)
        self.cyclesBeforeLongBreak = max(1, cyclesBeforeLongBreak)
        self.isEnabled = isEnabled
        self.clock = clock
    }

    public var status: ModuleStatus { .ok }

    public func refresh() async throws {
        tick(at: clock())
    }

    public func startCountdown(duration: TimeInterval, at now: Date? = nil) {
        let now = now ?? clock()
        let dur = max(1, duration)
        withLock { state in
            state.mode = .countdown
            state.status = .running
            state.totalDuration = dur
            state.pausedRemaining = dur
            state.targetDate = now.addingTimeInterval(dur)
            state.finishedAt = nil
            state.cycleCount = 0
            state.runSequence += 1
        }
    }

    public func startPomodoroFocus(at now: Date? = nil) {
        let now = now ?? clock()
        withLock { state in
            state.mode = .pomodoroFocus
            state.status = .running
            state.totalDuration = focusDuration
            state.pausedRemaining = focusDuration
            state.targetDate = now.addingTimeInterval(focusDuration)
            state.finishedAt = nil
            state.runSequence += 1
        }
    }

    public func pause(at now: Date? = nil) {
        let now = now ?? clock()
        withLock { state in
            guard state.status == .running, let target = state.targetDate else { return }
            state.pausedRemaining = max(0, target.timeIntervalSince(now))
            state.targetDate = nil
            state.status = .paused
        }
    }

    public func resume(at now: Date? = nil) {
        let now = now ?? clock()
        withLock { state in
            guard state.status == .paused, state.pausedRemaining > 0 else { return }
            state.targetDate = now.addingTimeInterval(state.pausedRemaining)
            state.status = .running
        }
    }

    public func togglePause(at now: Date? = nil) {
        let now = now ?? clock()
        let current = withLock { $0.status }
        if current == .running {
            pause(at: now)
        } else if current == .paused {
            resume(at: now)
        }
    }

    public func stop() {
        withLock { state in
            state.status = .idle
            state.totalDuration = 0
            state.pausedRemaining = 0
            state.targetDate = nil
            state.finishedAt = nil
            state.cycleCount = 0
        }
    }

    public func advancePomodoro(at now: Date? = nil) {
        let now = now ?? clock()
        withLock { state in
            let nextMode: TimerMode
            let nextDuration: TimeInterval
            switch state.mode {
            case .pomodoroFocus, .countdown:
                state.cycleCount += 1
                if state.cycleCount % cyclesBeforeLongBreak == 0 {
                    nextMode = .pomodoroLongBreak
                    nextDuration = longBreakDuration
                } else {
                    nextMode = .pomodoroShortBreak
                    nextDuration = shortBreakDuration
                }
            case .pomodoroShortBreak, .pomodoroLongBreak:
                nextMode = .pomodoroFocus
                nextDuration = focusDuration
            }
            state.mode = nextMode
            state.status = .running
            state.totalDuration = nextDuration
            state.pausedRemaining = nextDuration
            state.targetDate = now.addingTimeInterval(nextDuration)
            state.finishedAt = nil
            state.runSequence += 1
        }
    }

    public func snapshot(at now: Date? = nil) -> TimerSnapshot? {
        let now = now ?? clock()
        return withLock { state in
            guard state.status != .idle else { return nil }
            let remaining: TimeInterval
            switch state.status {
            case .idle:
                return nil
            case .running:
                remaining = max(0, (state.targetDate ?? now).timeIntervalSince(now))
            case .paused:
                remaining = state.pausedRemaining
            case .finished:
                remaining = 0
            }
            return TimerSnapshot(
                mode: state.mode,
                status: state.status,
                totalDuration: state.totalDuration,
                remaining: remaining,
                targetDate: state.targetDate,
                cycleCount: state.cycleCount
            )
        }
    }

    public func tick(at now: Date? = nil) {
        let now = now ?? clock()
        let (continuation, peek): (AsyncStream<PeekEvent>.Continuation?, PeekEvent?) = withLock { state in
            guard state.status == .running, let target = state.targetDate, now >= target else {
                return (nil, nil)
            }
            state.status = .finished
            state.pausedRemaining = 0
            state.targetDate = nil
            state.finishedAt = now
            guard state.peekedRunSequence != state.runSequence else { return (nil, nil) }
            state.peekedRunSequence = state.runSequence
            let title: String
            let message: String
            switch state.mode {
            case .countdown:
                title = "Timer done"
                message = "\(TimerFormat.accessibilityDuration(state.totalDuration)) elapsed"
            case .pomodoroFocus:
                title = "Focus finished"
                message = "Time for a break"
            case .pomodoroShortBreak, .pomodoroLongBreak:
                title = "Break finished"
                message = "Ready for focus"
            }
            let event = PeekEvent(
                id: "timer.done.\(state.runSequence)",
                moduleID: id,
                title: title,
                message: message,
                priority: .normal
            )
            return (state.peeks, event)
        }
        if let peek {
            continuation?.yield(peek)
        }
    }

    public func collapsedActivity(at now: Date) throws -> LiveActivity? {
        guard isEnabled else { return nil }
        let (snap, finishedAt) = withLock { state -> (TimerSnapshot?, Date?) in
            guard state.status != .idle else { return (nil, nil) }
            let remaining: TimeInterval
            switch state.status {
            case .idle: return (nil, nil)
            case .running: remaining = max(0, (state.targetDate ?? now).timeIntervalSince(now))
            case .paused: remaining = state.pausedRemaining
            case .finished: remaining = 0
            }
            return (
                TimerSnapshot(
                    mode: state.mode,
                    status: state.status,
                    totalDuration: state.totalDuration,
                    remaining: remaining,
                    targetDate: state.targetDate,
                    cycleCount: state.cycleCount
                ),
                state.finishedAt
            )
        }
        guard let snap else { return nil }
        switch snap.status {
        case .idle:
            return nil
        case .running:
            let text = snap.formattedRemaining
            return LiveActivity(
                id: "timer.active",
                moduleID: id,
                source: .other,
                text: text,
                accessibilityLabel: "\(snap.mode.displayName), \(TimerFormat.accessibilityDuration(snap.remaining)) remaining",
                isAlert: snap.remaining <= 10,
                deadline: snap.targetDate
            )
        case .paused:
            let text = "Paused \(snap.formattedRemaining)"
            return LiveActivity(
                id: "timer.active",
                moduleID: id,
                source: .other,
                text: text,
                accessibilityLabel: "\(snap.mode.displayName) paused, \(TimerFormat.accessibilityDuration(snap.remaining)) remaining"
            )
        case .finished:
            if let finishedAt, now.timeIntervalSince(finishedAt) <= 30 {
                return LiveActivity(
                    id: "timer.finished",
                    moduleID: id,
                    source: .other,
                    text: "Timer done",
                    accessibilityLabel: "\(snap.mode.displayName) finished",
                    isAlert: true
                )
            }
            return nil
        }
    }

    public func peekEvents() -> AsyncStream<PeekEvent> {
        AsyncStream { continuation in
            withLock { $0.peeks = continuation }
        }
    }

    public func accessibilitySummary() -> String {
        guard let snap = snapshot() else { return "Timer idle" }
        return "\(snap.mode.displayName), \(snap.status.rawValue), \(TimerFormat.accessibilityDuration(snap.remaining))"
    }

    private func withLock<T>(_ body: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }
}
