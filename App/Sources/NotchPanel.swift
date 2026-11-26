import AppKit

/// Borderless transparent panel that floats above the menu bar.
final class NotchPanel: NSPanel {
    var onCancel: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        title = "Ufuq"
        setAccessibilityLabel("Ufuq notch")
    }

    /// Needed for keyboard focus when expanded.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// The system would push a window below the menu bar; the notch panel must sit above it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Esc.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
