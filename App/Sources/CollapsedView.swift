import SwiftUI
import UfuqCore

/// Left wing = prayer, right wing = AI and the third activity, taking turns.
/// Each wing is one accessibility element.
struct CollapsedView: View {
    let layout: WingLayout
    let centerGap: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .animation(Jelly.resolved(Jelly.morph, reduceMotion: reduceMotion), value: layout.rightWingShown?.id)
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

    /// One element: shows `rotating ?? right`; the label always carries both so VoiceOver
    /// never depends on the 8 s phase.
    @ViewBuilder
    private var rightWing: some View {
        if let shown = layout.rotating ?? layout.right {
            HStack(spacing: 6) {
                if shown.source == .agent, shown.isAlert { WaitingDot() }
                Text(shown.text)
                    .font(Tokens.Typography.collapsed)
                    .monospacedDigit()
                    .foregroundStyle(Tokens.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.middle)
                    .id(shown.id)
                    .transition(.opacity)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rightWingLabel)
        }
    }

    private var rightWingLabel: String {
        [layout.right?.accessibilityLabel, layout.rotating?.accessibilityLabel]
            .compactMap { $0 }.joined(separator: ". ")
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
