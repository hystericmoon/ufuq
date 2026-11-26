import CoreGraphics

/// Plain values taken from an `NSScreen`, so the math is testable without AppKit.
struct ScreenMetrics: Equatable {
    var frame: CGRect
    var visibleFrame: CGRect
    /// `safeAreaInsets.top`; above 0 only on screens with a notch.
    var safeAreaTop: CGFloat
    /// `auxiliaryTopLeftArea?.width`, 0 when nil.
    var auxLeftWidth: CGFloat
    /// `auxiliaryTopRightArea?.width`, 0 when nil.
    var auxRightWidth: CGFloat

    var hasNotch: Bool { safeAreaTop > 0 }
}

/// Panel frames in screen coordinates (origin bottom-left, like AppKit).
enum NotchGeometry {
    /// Spec sizes. On a notch screen the collapsed panel is widened so each wing keeps at least
    /// `minWingWidth` beside the camera housing (300 pt alone leaves ~56 pt per wing).
    static let collapsedSize = CGSize(width: 300, height: 32)
    static let peekSize = CGSize(width: 352, height: 92)
    static let expandedSize = CGSize(width: 640, height: 360)
    static let minWingWidth: CGFloat = 90
    /// Gap between the menu bar and the floating pill on screens without a notch.
    static let pillGap: CGFloat = 8
    /// Fallback when the system reports a notch but no auxiliary areas.
    static let fallbackNotchWidth: CGFloat = 200

    static func notchWidth(_ m: ScreenMetrics) -> CGFloat {
        guard m.hasNotch else { return 0 }
        guard m.auxLeftWidth > 0, m.auxRightWidth > 0 else { return fallbackNotchWidth }
        return max(0, m.frame.width - m.auxLeftWidth - m.auxRightWidth)
    }

    /// The camera housing, or nil on a screen without a notch.
    static func notchRect(_ m: ScreenMetrics) -> CGRect? {
        guard m.hasNotch else { return nil }
        let width = notchWidth(m)
        let x: CGFloat
        if m.auxLeftWidth > 0, m.auxRightWidth > 0 {
            x = m.frame.minX + m.auxLeftWidth
        } else {
            x = m.frame.midX - width / 2
        }
        return CGRect(x: x, y: m.frame.maxY - m.safeAreaTop, width: width, height: m.safeAreaTop)
    }

    static func size(for kind: NotchState.Kind, metrics m: ScreenMetrics) -> CGSize {
        let notch = notchWidth(m)
        switch kind {
        case .collapsed:
            let width = max(collapsedSize.width, notch + 2 * minWingWidth)
            return CGSize(width: width, height: max(collapsedSize.height, m.safeAreaTop))
        case .peek:
            return CGSize(width: max(peekSize.width, notch), height: peekSize.height)
        case .expanded:
            return expandedSize
        }
    }

    /// Window frame for a state. Notch screen: centered on the notch, flush with the top edge.
    /// Other screens: centered, `pillGap` below the menu bar.
    static func windowFrame(for kind: NotchState.Kind, metrics m: ScreenMetrics) -> CGRect {
        let size = size(for: kind, metrics: m)
        if let notch = notchRect(m) {
            return CGRect(
                x: notch.midX - size.width / 2,
                y: m.frame.maxY - size.height,
                width: size.width,
                height: size.height)
        }
        let top = m.visibleFrame.maxY - pillGap
        return CGRect(
            x: m.frame.midX - size.width / 2,
            y: top - size.height,
            width: size.width,
            height: size.height)
    }
}
