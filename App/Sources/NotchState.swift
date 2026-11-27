import Foundation
import UfuqCore

/// What the notch shows. Pure value; no AppKit.
enum NotchState: Equatable {
    case collapsed
    case peek(PeekEvent)
    case expanded

    enum Kind: Equatable {
        case collapsed, peek, expanded
    }

    var kind: Kind {
        switch self {
        case .collapsed: return .collapsed
        case .peek: return .peek
        case .expanded: return .expanded
        }
    }
}

extension NotchState {
    /// What one display's island shows: the full state on the active display; elsewhere an
    /// expanded panel stays a collapsed pill (the peek, if one is waiting, still shows).
    static func shown(_ state: NotchState, onActiveDisplay: Bool, peek: PeekEvent? = nil) -> NotchState {
        guard state == .expanded, !onActiveDisplay else { return state }
        return peek.map { .peek($0) } ?? .collapsed
    }
}

/// How the expanded panel was opened. Only hover-opened panels close when the mouse leaves.
enum ExpandOrigin: Equatable {
    case hotkey
    case click
    case hover
}

/// Pure state machine for the notch. The controller feeds it events and applies the result.
///
/// - Expanded wins over a peek; when expanded closes, a waiting peek shows.
/// - Hotkey toggles expanded; Esc closes expanded, otherwise dismisses the current peek.
/// - Mouse exit collapses only a panel that hover opened.
/// - The peek content comes from `PeekQueue.current`, which the controller passes to `setPeek`.
struct NotchStateMachine: Equatable {
    enum EscapeResult: Equatable {
        case ignored
        case collapsed
        case dismissedPeek
    }

    private(set) var isExpanded = false
    private(set) var origin: ExpandOrigin?
    private(set) var currentPeek: PeekEvent?

    init() {}

    var state: NotchState {
        if isExpanded { return .expanded }
        if let currentPeek { return .peek(currentPeek) }
        return .collapsed
    }

    mutating func setPeek(_ event: PeekEvent?) {
        currentPeek = event
    }

    mutating func open(origin: ExpandOrigin) {
        isExpanded = true
        self.origin = origin
    }

    mutating func collapse() {
        isExpanded = false
        origin = nil
    }

    mutating func toggleWithHotkey() {
        if isExpanded {
            collapse()
        } else {
            open(origin: .hotkey)
        }
    }

    mutating func escape() -> EscapeResult {
        if isExpanded {
            collapse()
            return .collapsed
        }
        if currentPeek != nil {
            currentPeek = nil
            return .dismissedPeek
        }
        return .ignored
    }

    /// Pointer entered the panel. Opens it only when the hover setting is on.
    mutating func mouseEntered(hoverEnabled: Bool) {
        guard hoverEnabled, !isExpanded else { return }
        open(origin: .hover)
    }

    /// Pointer left the panel. Collapses only a hover-opened panel.
    mutating func mouseExited() {
        guard isExpanded, origin == .hover else { return }
        collapse()
    }
}
