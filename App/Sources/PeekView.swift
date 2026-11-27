import SwiftUI
import UfuqCore

/// One alert. The controller posts the VoiceOver announcement when the peek appears
/// (see `NotchController.announce`), because this view is also rendered in snapshot tests.
struct PeekView: View {
    let event: PeekEvent
    let topInset: CGFloat

    private var isCritical: Bool { event.priority == .critical }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isCritical ? "exclamationmark.circle.fill" : "bell.fill")
                .font(Tokens.Typography.collapsed)
                .foregroundStyle(isCritical ? Tokens.stateCritical : Tokens.accentPrayer)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(Tokens.Typography.collapsed)
                        .foregroundStyle(Tokens.textPrimary)
                    if isCritical {
                        // Color never carries meaning alone: the word says it too.
                        Text("Alert")
                            .font(Tokens.Typography.collapsed)
                            .foregroundStyle(Tokens.stateCritical)
                    }
                }
                Text(event.message)
                    .font(Tokens.Typography.collapsed)
                    .foregroundStyle(Tokens.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, topInset + 4)
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.announcement)
    }
}
