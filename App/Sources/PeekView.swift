import SwiftUI
import UfuqCore

/// One alert. The controller posts the VoiceOver announcement when the peek appears
/// (see `NotchController.announce`), because this view is also rendered in snapshot tests.
struct PeekView: View {
    let event: PeekEvent
    let topInset: CGFloat
    var onAction: ((URL) -> Void)? = nil

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
                        .lineLimit(1)
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
            if let actionTitle = event.actionTitle,
               let urlString = event.actionURL,
               let url = URL(string: urlString) {
                Button {
                    onAction?(url)
                } label: {
                    Text(actionTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tokens.notchBg)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 28)
                        .background(Capsule().fill(Tokens.accentPrayer))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(actionTitle), \(event.title)")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, topInset + 4)
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: event.actionTitle == nil ? .ignore : .contain)
        .accessibilityLabel(event.announcement)
    }
}
