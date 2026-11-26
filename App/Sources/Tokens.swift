import SwiftUI

/// Visual tokens from docs/spec.md. No other colors, radii or type sizes.
enum Tokens {
    static let notchBg = Color(hex: 0x000000)
    static let cardBg = Color(hex: 0x141416)
    static let controlBg = Color(hex: 0x1C1C1F)
    static let track = Color(hex: 0x2A2A2E)

    static let textPrimary = Color(hex: 0xFFFFFF)
    static let textSecondary = Color(hex: 0xA1A1A6)
    static let textMuted = Color(hex: 0x8E8E93)

    static let accentPrayer = Color(hex: 0x4FD1A5)
    static let stateWarning = Color(hex: 0xFFB340)
    static let stateCritical = Color(hex: 0xFF6B5E)

    enum Radius {
        static let collapsed: CGFloat = 14
        static let peek: CGFloat = 22
        static let expanded: CGFloat = 28
    }

    /// SF Pro (system font). Changing numbers add `.monospacedDigit()` at the call site.
    enum Typography {
        static let collapsed = Font.system(size: 13, weight: .semibold)
        static let title = Font.system(size: 26, weight: .bold)
        static let countdown = Font.system(size: 44, weight: .semibold)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1)
    }
}
