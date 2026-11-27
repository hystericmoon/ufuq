import Foundation

/// Claude Code session status (running / waiting / done), read from the state files `ufuq-hook` writes.
public final class AgentStatusModule: UfuqModule {
    public let id = "agent"
    public let title = "Agents"
    public var isEnabled = true

    /// Sessions not updated for this long are hidden everywhere (crashed sessions never send SessionEnd).
    public static let staleAfter: TimeInterval = 6 * 3600
    /// A finished session leaves the wing after this long (tile and sync keep it until `staleAfter`).
    public static let doneWingWindow: TimeInterval = 5 * 60
    /// A turn must run this long before its end earns a "Task done" peek.
    public static let donePeekThreshold: TimeInterval = 30

    private struct State {
        var sessions: [AgentSession] = []
        var previous: [String: AgentSession] = [:]
        var hasBaseline = false
        var peeks: AsyncStream<PeekEvent>.Continuation?
    }

    private let directory: String
    private let fileSource: FileSource
    private let lock = NSLock()
    private var state = State()

    public init(directory: String, fileSource: FileSource = LocalFileSource()) {
        self.directory = directory
        self.fileSource = fileSource
    }

    /// Hooks not installed yet (no directory) is not an error.
    public var status: ModuleStatus { .ok }

    // MARK: - Refresh

    public func refresh() async throws {
        let paths = (try? fileSource.files(under: directory, suffix: ".json")) ?? []
        var sessions: [AgentSession] = []
        for path in paths {
            guard let data = try? fileSource.read(path), let session = try? AgentSession.decode(data) else { continue }
            sessions.append(session)
        }

        let (continuation, events) = withLock { state -> (AsyncStream<PeekEvent>.Continuation?, [PeekEvent]) in
            let events = state.hasBaseline ? peeks(from: state.previous, to: sessions) : []
            state.sessions = sessions
            state.previous = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            state.hasBaseline = true
            return (state.peeks, events)
        }
        for event in events { continuation?.yield(event) }
    }

    // MARK: - Sessions

    /// Sessions for the tile: not idle, updated within 6 h, newest first.
    public func sessions(at now: Date) -> [AgentSession] {
        withLock { $0.sessions }
            .filter { $0.state != .idle && now.timeIntervalSince($0.updatedAt) < Self.staleAfter }
            .sorted { $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.id < $1.id }
    }

    public func syncAgents(at now: Date) -> [SyncAgent] {
        sessions(at: now).compactMap { session in
            let state: SyncAgentState
            switch session.state {
            case .running: state = .running
            case .waiting: state = .waiting
            case .done: state = .done
            case .idle: return nil
            }
            return SyncAgent(id: session.id, title: session.title, state: state, updatedAt: session.updatedAt)
        }
    }

    // MARK: - Collapsed activity

    public func collapsedActivity(at now: Date) throws -> LiveActivity? {
        let visible = sessions(at: now)
        let waiting = visible.filter { $0.state == .waiting }
        let running = visible.filter { $0.state == .running }
        let done = visible.filter { $0.state == .done && now.timeIntervalSince($0.finishedAt ?? $0.updatedAt) <= Self.doneWingWindow }

        if let first = waiting.first {
            let extra = waiting.count - 1
            return LiveActivity(
                id: "agent", moduleID: id, source: .agent,
                // The right-wing slot fits ~11 characters: the title lives in the peek, tile and label.
                text: waiting.count == 1 ? "Needs input" : "\(waiting.count) need input",
                accessibilityLabel: "Claude Code, \(first.title), needs input"
                    + (extra > 0 ? ", plus \(extra) more waiting" : ""),
                isAlert: true)
        }
        if let first = running.first {
            if running.count == 1 {
                let elapsed = Self.wingElapsed(now.timeIntervalSince(first.runningSince ?? first.updatedAt))
                return LiveActivity(id: "agent", moduleID: id, source: .agent,
                                    text: "\(first.title) · \(elapsed)",
                                    accessibilityLabel: "Claude Code, \(first.title), running")
            }
            return LiveActivity(id: "agent", moduleID: id, source: .agent,
                                text: "\(running.count) agents running",
                                accessibilityLabel: "Claude Code, \(running.count) agents running")
        }
        if let first = done.first {
            return LiveActivity(id: "agent", moduleID: id, source: .agent,
                                text: "\(first.title) done",
                                accessibilityLabel: "Claude Code, \(first.title), done")
        }
        return nil
    }

    public func accessibilitySummary() -> String {
        (try? collapsedActivity(at: Date()))?.accessibilityLabel ?? "No agents running"
    }

    // MARK: - Peeks

    /// One consumer at a time, like `AIUsageModule`.
    public func peekEvents() -> AsyncStream<PeekEvent> {
        AsyncStream { continuation in
            withLock { $0.peeks = continuation }
            continuation.onTermination = { [weak self] _ in self?.withLock { $0.peeks = nil } }
        }
    }

    private func peeks(from previous: [String: AgentSession], to sessions: [AgentSession]) -> [PeekEvent] {
        var events: [PeekEvent] = []
        for session in sessions.sorted(by: { $0.id < $1.id }) {
            let before = previous[session.id]
            if session.state == .waiting, before?.state != .waiting {
                events.append(PeekEvent(
                    id: "agent.waiting.\(session.id)", moduleID: id,
                    title: "Claude needs input", message: session.title, priority: .critical))
            } else if session.state == .done, before?.state == .running {
                let start = session.runningSince ?? before?.runningSince
                let end = session.finishedAt ?? session.updatedAt
                guard let start else { continue }
                let elapsed = end.timeIntervalSince(start)
                guard elapsed >= Self.donePeekThreshold else { continue }
                events.append(PeekEvent(
                    id: "agent.done.\(session.id)", moduleID: id,
                    title: "Task done", message: "\(session.title) · \(Self.peekElapsed(elapsed))"))
            }
        }
        return events
    }

    // MARK: - Formats

    /// Wing: `<1m`, `4m`, `1h 5m`.
    static func wingElapsed(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        if total < 60 { return "<1m" }
        let minutes = total / 60
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }

    /// Done peek: `45s`, `4m 12s`, `1h 5m`.
    static func peekElapsed(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m \(total % 60)s" }
        return "\(total / 3600)h \(total % 3600 / 60)m"
    }

    private func withLock<T>(_ body: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }
}
