import SwiftUI
import UfuqCore

/// Left wing = prayer, right wing = AI plus the rotating third activity.
/// Each wing is one accessibility element.
struct CollapsedView: View {
    let layout: WingLayout
    let centerGap: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            leftWing
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: centerGap, height: 1)
            rightWing
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.25), value: layout.rotating?.id)
    }

    @ViewBuilder
    private var leftWing: some View {
        if let left = layout.left {
            Text(left.text)
                .font(Tokens.Typography.collapsed)
                .monospacedDigit()
                .foregroundStyle(Tokens.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(left.accessibilityLabel)
        }
    }

    @ViewBuilder
    private var rightWing: some View {
        HStack(spacing: 6) {
            if let right = layout.right {
                Text(right.text)
                    .font(Tokens.Typography.collapsed)
                    .monospacedDigit()
                    .foregroundStyle(Tokens.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(right.accessibilityLabel)
            }
            if let rotating = layout.rotating {
                if rotating.source == .agent, rotating.isAlert { WaitingDot() }
                Text(rotating.text)
                    .font(Tokens.Typography.collapsed)
                    .monospacedDigit()
                    .foregroundStyle(Tokens.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .id(rotating.id)
                    .transition(.opacity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(rotating.accessibilityLabel)
            }
        }
    }
}

/// 6 pt dot before a waiting agent's text: pulses 1 → 0.4 over 1.2 s, static under Reduce Motion.
/// Hidden from VoiceOver; the wing's label already says "needs input".
struct WaitingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(Tokens.stateWarning)
            .frame(width: 6, height: 6)
            .opacity(dimmed && !reduceMotion ? 0.4 : 1)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: dimmed)
            .onAppear { dimmed = true }
            .accessibilityHidden(true)
    }
}
