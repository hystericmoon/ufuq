import SwiftUI
import UfuqCore

/// Compact capsule budding from the notch for volume, brightness, and keyboard backlight.
struct HUDCapsuleView: View {
    let reading: HUDReading
    let topInset: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fillFraction: CGFloat {
        reading.isMuted ? 0 : CGFloat(min(max(reading.level, 0), 1))
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: reading.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(reading.isMuted ? Tokens.textMuted : Tokens.textPrimary)
                .frame(width: 18)
                .accessibilityHidden(true)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Tokens.Fill.track)
                    Capsule()
                        .fill(reading.isMuted ? Tokens.textMuted : Tokens.textPrimary)
                        .frame(width: max(0, geo.size.width * fillFraction))
                        .animation(Jelly.resolved(Jelly.touch, reduceMotion: reduceMotion), value: fillFraction)
                }
            }
            .frame(height: 6)

            Text(reading.isMuted ? "Muted" : "\(reading.percent)%")
                .font(Tokens.Typography.caption)
                .monospacedDigit()
                .foregroundStyle(reading.isMuted ? Tokens.textMuted : Tokens.textSecondary)
                .frame(minWidth: 34, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.top, topInset + 2)
        .padding(.bottom, 6)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.accessibilityLabel)
    }
}
