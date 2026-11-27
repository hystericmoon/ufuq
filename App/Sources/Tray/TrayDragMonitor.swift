import AppKit

/// Watches for a file drag anywhere on screen (global mouse monitor + the drag pasteboard) and
/// reports pointer moves, shakes and the end of the drag. Needs no accessibility permission:
/// global monitors of mouse events do not require it.
@MainActor
final class TrayDragMonitor {
    /// Pointer position (AppKit screen coordinates) while files are being dragged.
    var onFileDrag: (NSPoint) -> Void = { _ in }
    var onShake: (NSPoint) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    private var monitor: Any?
    private var endTimer: Timer?
    private var shake = ShakeDetector()
    private var changeCountAtMouseDown = 0
    private var dragging = false

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            let type = event.type
            let time = event.timestamp
            MainActor.assumeIsolated { self?.handle(type: type, time: time) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        endTimer?.invalidate()
        endTimer = nil
    }

    private func handle(type: NSEvent.EventType, time: TimeInterval) {
        switch type {
        case .leftMouseDown:
            changeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
            shake.reset()
        case .leftMouseDragged:
            guard Self.isFileDrag(changeCountAtMouseDown: changeCountAtMouseDown) else { return }
            let point = NSEvent.mouseLocation
            beginIfNeeded()
            onFileDrag(point)
            if shake.add(x: point.x, at: time) { onShake(point) }
        case .leftMouseUp:
            endDrag()
        default:
            break
        }
    }

    /// The drag pasteboard changed since the press (so this drag filled it) and holds file URLs.
    static func isFileDrag(changeCountAtMouseDown: Int) -> Bool {
        let board = NSPasteboard(name: .drag)
        guard board.changeCount != changeCountAtMouseDown else { return false }
        return board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    private func beginIfNeeded() {
        guard !dragging else { return }
        dragging = true
        // A drop onto our own panel ends the drag without a global mouse-up; poll the button too.
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if NSEvent.pressedMouseButtons & 1 == 0 { self?.endDrag() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        endTimer = timer
    }

    private func endDrag() {
        shake.reset()
        endTimer?.invalidate()
        endTimer = nil
        guard dragging else { return }
        dragging = false
        onDragEnded()
    }
}
