import Foundation

/// Recent peek events with increasing sequence numbers, for `GET /v1/events` long-polls.
public actor SyncEventLog {
    private var events: [SyncEvent] = []
    private var nextSeq = 1
    private let capacity: Int
    private let pollInterval: Duration

    public init(capacity: Int = 200, pollInterval: Duration = .milliseconds(200)) {
        self.capacity = capacity
        self.pollInterval = pollInterval
    }

    public var latestSeq: Int { nextSeq - 1 }

    @discardableResult
    public func append(id: String, moduleId: String, title: String, message: String,
                       priority: SyncEventPriority, at date: Date) -> SyncEvent {
        let event = SyncEvent(seq: nextSeq, id: id, moduleId: moduleId, title: title, message: message,
                              priority: priority, createdAt: date)
        nextSeq += 1
        events.append(event)
        if events.count > capacity { events.removeFirst(events.count - capacity) }
        return event
    }

    @discardableResult
    public func append(_ peek: PeekEvent, at date: Date) -> SyncEvent {
        append(id: peek.id, moduleId: peek.moduleID, title: peek.title, message: peek.message,
               priority: peek.priority == .critical ? .critical : .normal, at: date)
    }

    public func events(since seq: Int) -> [SyncEvent] {
        events.filter { $0.seq > seq }
    }

    /// Returns as soon as an event newer than `seq` exists, or an empty list after `timeout` seconds.
    public func wait(since seq: Int, timeout: TimeInterval) async -> [SyncEvent] {
        let deadline = ContinuousClock.now + .seconds(timeout)
        while true {
            let found = events(since: seq)
            if !found.isEmpty || ContinuousClock.now >= deadline || Task.isCancelled { return found }
            try? await Task.sleep(for: pollInterval)
        }
    }
}
