import Foundation

/// One peek at a time; critical alerts jump the queue.
///
/// - FIFO within a priority; critical events go ahead of every waiting normal one.
/// - A critical event preempts a normal peek on screen; the interrupted peek goes back to the
///   front of the normal queue and later shows for its full duration.
/// - A peek auto-dismisses after its duration. Hover holds it; on release the remaining time resumes.
/// - Enqueueing an id already waiting replaces that entry (no duplicate alerts).
///
/// Time is passed in, so the queue is deterministic and testable; the app calls `tick(at:)`.
public struct PeekQueue {
    public private(set) var current: PeekEvent?
    public private(set) var pending: [PeekEvent] = []

    private var deadline: Date?
    private var heldRemaining: TimeInterval?

    public init() {}

    public var isHeld: Bool { heldRemaining != nil }

    public mutating func enqueue(_ event: PeekEvent, at now: Date) {
        if current?.id == event.id {
            current = event
            return
        }
        pending.removeAll { $0.id == event.id }

        if let shown = current, event.priority > shown.priority {
            current = nil
            deadline = nil
            heldRemaining = nil
            insert(shown, atFrontOfPriority: true)
            insert(event, atFrontOfPriority: false)
            advance(at: now)
            return
        }

        insert(event, atFrontOfPriority: false)
        if current == nil { advance(at: now) }
    }

    /// Dismisses the current peek when its time is up (unless held) and shows the next one.
    public mutating func tick(at now: Date) {
        guard current != nil, heldRemaining == nil, let deadline, now >= deadline else { return }
        current = nil
        advance(at: now)
    }

    /// Esc or a click: dismiss now and show the next one.
    public mutating func dismissCurrent(at now: Date) {
        current = nil
        deadline = nil
        heldRemaining = nil
        advance(at: now)
    }

    /// Pointer over the peek holds it; leaving resumes the remaining time.
    public mutating func setHovering(_ hovering: Bool, at now: Date) {
        guard current != nil else { return }
        if hovering {
            guard heldRemaining == nil, let deadline else { return }
            heldRemaining = max(0, deadline.timeIntervalSince(now))
        } else if let remaining = heldRemaining {
            deadline = now.addingTimeInterval(remaining)
            heldRemaining = nil
        }
    }

    /// Drops every waiting and shown peek from a module (e.g. when it is turned off).
    public mutating func removeAll(fromModule moduleID: String, at now: Date) {
        pending.removeAll { $0.moduleID == moduleID }
        if current?.moduleID == moduleID { dismissCurrent(at: now) }
    }

    private mutating func insert(_ event: PeekEvent, atFrontOfPriority front: Bool) {
        let index: Int
        if front {
            index = pending.firstIndex { $0.priority <= event.priority } ?? pending.endIndex
        } else {
            index = pending.firstIndex { $0.priority < event.priority } ?? pending.endIndex
        }
        pending.insert(event, at: index)
    }

    private mutating func advance(at now: Date) {
        heldRemaining = nil
        guard !pending.isEmpty else {
            current = nil
            deadline = nil
            return
        }
        let next = pending.removeFirst()
        current = next
        deadline = now.addingTimeInterval(next.duration)
    }
}
