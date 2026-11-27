import CoreGraphics

/// Geometry of the open panel (design canvas option A, "Bento 5×2", owner pick 27 Nov 2026):
/// a black strip at the notch, then Prayer and AI as tall tiles and the small tiles in columns of two.
/// The panel is as wide as its tiles; nothing is reserved for modules that are not live.
enum BentoLayout {
    /// Outer padding of the body; tile radius is concentric with the panel (28 − 12 = 16).
    static let padding: CGFloat = 12
    static let gap: CGFloat = 8
    static let tilePadding: CGFloat = 12
    static let rowHeight: CGFloat = 112
    static let prayerWidth: CGFloat = 216
    static let aiWidth: CGFloat = 248
    static let smallWidth: CGFloat = 144
    static let smallTilesPerColumn = 2

    static var tileRadius: CGFloat { Tokens.Radius.expanded - padding }
    /// Two rows and the gap between them: the height of Prayer, AI and a lone small tile.
    static var bodyHeight: CGFloat { 2 * rowHeight + gap }

    static func columns(smallTiles: Int) -> Int {
        let n = max(0, smallTiles)
        return (n + smallTilesPerColumn - 1) / smallTilesPerColumn
    }

    static func width(smallTiles: Int) -> CGFloat {
        2 * padding + prayerWidth + gap + aiWidth + CGFloat(columns(smallTiles: smallTiles)) * (gap + smallWidth)
    }

    static func height(stripHeight: CGFloat) -> CGFloat {
        stripHeight + 2 * padding + bodyHeight
    }

    static func size(smallTiles: Int, stripHeight: CGFloat) -> CGSize {
        CGSize(width: width(smallTiles: smallTiles), height: height(stripHeight: stripHeight))
    }
}
