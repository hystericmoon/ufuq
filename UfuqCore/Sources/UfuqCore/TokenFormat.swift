import Foundation

/// Token counts: "4.2M" on screen, "4.2 million tokens" for the screen reader.
public enum TokenFormat {
    private static func scaled(_ n: Int) -> (text: String, scale: Int) {
        let v = Double(max(n, 0))
        if v >= 1e9 { return (one(v / 1e9), 3) }
        if v >= 1e6 { return (one(v / 1e6), 2) }
        if v >= 1e3 { return (one(v / 1e3), 1) }
        return (String(max(n, 0)), 0)
    }

    /// One decimal below 100 ("4.2", "12.5"), none from 100 ("250"); a trailing ".0" is dropped.
    private static func one(_ x: Double) -> String {
        let text = x < 100 ? String(format: "%.1f", x) : String(format: "%.0f", x)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    /// "812", "12.5K", "4.2M", "250M", "1.1B". Negatives count as 0.
    public static func compact(_ n: Int) -> String {
        let (text, scale) = scaled(n)
        return text + ["", "K", "M", "B"][scale]
    }

    /// "812 tokens", "4.2 million tokens".
    public static func spoken(_ n: Int) -> String {
        let (text, scale) = scaled(n)
        switch scale {
        case 3: return "\(text) billion tokens"
        case 2: return "\(text) million tokens"
        case 1: return "\(text) thousand tokens"
        default: return text == "1" ? "1 token" : "\(text) tokens"
        }
    }
}
