import CoreGraphics

/// Where a file drag is relative to the notch body; the motion layer reads it to grow the neck.
struct FileDragState: Equatable {
    /// Points below the top edge of the screen.
    var distance: CGFloat
    /// Pointer x relative to the body's centre (negative is left).
    var x: CGFloat

    /// A drag this close to the top edge reaches toward the pointer.
    static let reach: CGFloat = 160
    /// A drag this close opens the tray drop zone.
    static let dropZone: CGFloat = 60
    /// Only a drag this near the body's centre counts. Kept below half of the narrowest open
    /// panel (248 pt) so a pointer outside the panel is never inside the zone.
    static let horizontalReach: CGFloat = 240

    var overDropZone: Bool { distance < Self.dropZone }

    /// 0 at the edge of the reach, 1 at the top edge.
    var closeness: CGFloat { min(1, max(0, 1 - distance / Self.reach)) }

    /// `pointer` and `screenFrame` are in AppKit screen coordinates (origin bottom-left).
    static func make(pointer: CGPoint, screenFrame: CGRect, bodyMidX: CGFloat) -> FileDragState? {
        guard pointer.x >= screenFrame.minX, pointer.x <= screenFrame.maxX,
              pointer.y >= screenFrame.minY else { return nil }
        let distance = max(0, screenFrame.maxY - pointer.y)
        let x = pointer.x - bodyMidX
        guard distance <= reach, abs(x) <= horizontalReach else { return nil }
        return FileDragState(distance: distance, x: x)
    }
}
