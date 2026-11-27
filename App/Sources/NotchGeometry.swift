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
    static let minWingWidth: CGFloat = 90
    /// Smallest collapsed height on a screen without a notch (also used when the menu bar is
    /// auto-hidden and reports 0).
    static let minMenuBarHeight: CGFloat = 24
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

    /// Menu bar height on this screen, at least `minMenuBarHeight`.
    static func menuBarHeight(_ m: ScreenMetrics) -> CGFloat {
        max(minMenuBarHeight, m.frame.maxY - m.visibleFrame.maxY)
    }

    /// Height of the black strip on top of the open panel: the camera housing on a notch screen,
    /// at least the collapsed height elsewhere, so the wings stay where they were.
    static func stripHeight(_ m: ScreenMetrics) -> CGFloat {
        max(collapsedSize.height, m.hasNotch ? m.safeAreaTop : menuBarHeight(m))
    }

    /// `smallTiles`: how many small bento tiles are live (they set the open panel's width).
    static func size(for kind: NotchState.Kind, metrics m: ScreenMetrics, smallTiles: Int = 0, trayRow: Bool = false) -> CGSize {
        let notch = notchWidth(m)
        switch kind {
        case .collapsed:
            guard m.hasNotch else {
                // No notch: a notch-like tab over the middle of the menu bar, as tall as the bar.
                return CGSize(width: collapsedSize.width, height: menuBarHeight(m))
            }
            let width = max(collapsedSize.width, notch + 2 * minWingWidth)
            return CGSize(width: width, height: max(collapsedSize.height, m.safeAreaTop))
        case .peek:
            return CGSize(width: max(peekSize.width, notch), height: peekSize.height)
        case .expanded:
            return BentoLayout.size(smallTiles: smallTiles, stripHeight: stripHeight(m), trayRow: trayRow)
        }
    }

    /// Window frame for a state: always flush with the top edge of the screen. Notch screen:
    /// centered on the notch. Other screens: centered, overlapping the middle of the menu bar.
    static func windowFrame(for kind: NotchState.Kind, metrics m: ScreenMetrics, smallTiles: Int = 0, trayRow: Bool = false) -> CGRect {
        let size = size(for: kind, metrics: m, smallTiles: smallTiles, trayRow: trayRow)
        let midX = notchRect(m)?.midX ?? m.frame.midX
        return CGRect(
            x: midX - size.width / 2,
            y: m.frame.maxY - size.height,
            width: size.width,
            height: size.height)
    }
}
