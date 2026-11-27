import CoreGraphics
import Foundation

/// Detects a shake in a stream of pointer x positions: `reversals` direction changes within
/// `window` seconds, each a move of at least `minMove` points against the previous direction.
/// Pure value; the drag monitor feeds it.
struct ShakeDetector: Equatable {
    static let reversals = 3
    static let window: TimeInterval = 0.5
    static let minMove: CGFloat = 24

    /// -1 left, 1 right, 0 not yet moving.
    private var direction = 0
    private var extreme: CGFloat = 0
    private var started = false
    private var times: [TimeInterval] = []

    init() {}

    mutating func reset() { self = ShakeDetector() }

    /// Returns true once, when the third reversal lands inside the window; the detector then resets.
    mutating func add(x: CGFloat, at time: TimeInterval) -> Bool {
        guard started else {
            started = true
            extreme = x
            return false
        }
        switch direction {
        case 0:
            if abs(x - extreme) >= Self.minMove {
                direction = x > extreme ? 1 : -1
                extreme = x
            }
        case 1:
            if x > extreme {
                extreme = x
            } else if extreme - x >= Self.minMove {
                direction = -1
                extreme = x
                times.append(time)
            }
        default:
            if x < extreme {
                extreme = x
            } else if x - extreme >= Self.minMove {
                direction = 1
                extreme = x
                times.append(time)
            }
        }
        times.removeAll { time - $0 > Self.window }
        if times.count >= Self.reversals {
            reset()
            return true
        }
        return false
    }
}
