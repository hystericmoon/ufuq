import SwiftUI
import UfuqCore

struct NotchRootView: View {
    @ObservedObject var model: NotchModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let kind = model.state.kind
        let size = model.shapeSize
        let radius = Self.radius(for: kind)

        content
            // Content always cross-fades; only the shape morph is dropped under Reduce Motion.
            .animation(.easeInOut(duration: 0.18), value: kind)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: radius,
                    bottomTrailingRadius: radius, topTrailingRadius: 0)
                    // The open panel draws its own black strip and glass body.
                    .fill(kind == .expanded ? Color.clear : Tokens.notchBg))
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: radius,
                    bottomTrailingRadius: radius, topTrailingRadius: 0)
                    .stroke(Tokens.textMuted, lineWidth: contrast == .increased && kind != .expanded ? 1 : 0))
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82), value: kind)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .collapsed:
            CollapsedView(layout: model.layout, centerGap: model.centerGap)
                .contentShape(Rectangle())
                .onTapGesture { model.onTapCollapsed() }
                .transition(.opacity)
        case .peek(let event):
            PeekView(event: event, topInset: model.topInset)
                .transition(.opacity)
        case .expanded:
            ExpandedView(
                content: model.content,
                layout: model.layout,
                centerGap: model.centerGap,
                stripHeight: model.stripHeight,
                focusedTile: $model.focusedTile,
                focusToken: model.focusToken,
                onEscape: model.onEscape)
                .transition(.opacity)
        }
    }

    static func radius(for kind: NotchState.Kind) -> CGFloat {
        switch kind {
        case .collapsed: return Tokens.Radius.collapsed
        case .peek: return Tokens.Radius.peek
        case .expanded: return Tokens.Radius.expanded
        }
    }
}
