import SwiftUI
import UfuqCore

/// The black jelly (`docs/motion.md`). One `JellyShape` hangs from the top edge; its width and
/// height are driven by springs (height lags width by 40 ms when it grows). While a peek buds
/// off or is reabsorbed, or a file drag reaches for the notch, the body is drawn as goo for the
/// length of the spring's settling time, then the crisp shape takes over again.
struct NotchRootView: View {
    @ObservedObject var model: NotchModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    /// Drawn size and radius; -1 until the first layout, then the model's values are used.
    @State private var dw: CGFloat = -1
    @State private var dh: CGFloat = -1
    @State private var dr: CGFloat = -1
    @State private var lastKind: NotchState.Kind?

    // Goo (peek bud).
    @State private var gooOn = false
    @State private var gooBase = CGSize.zero
    @State private var budSize = CGSize.zero
    @State private var budP: CGFloat = 0
    @State private var budTask: Task<Void, Never>?

    // Goo (file neck).
    @State private var neckGoo = false
    @State private var neckLen: CGFloat = 0
    @State private var neckX: CGFloat = 0
    @State private var neckTask: Task<Void, Never>?

    // One-shot reactions.
    @State private var swallowAmount: CGFloat = 0
    @State private var jiggle: CGFloat = 0
    @State private var reactionTask: Task<Void, Never>?

    var body: some View {
        let kind = model.state.kind
        let box = contentSize(kind)

        ZStack(alignment: .top) {
            bodyLayer(kind: kind)
            self.content
                .frame(width: box.width, height: box.height, alignment: .top)
                .animation(Jelly.resolved(Jelly.contentIn, reduceMotion: reduceMotion), value: kind)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .onAppear {
            lastKind = kind
            let size = model.shapeSize
            dw = size.width
            dh = size.height
            dr = Self.radius(for: kind)
        }
        .onChange(of: model.shapeSize) { _, new in retarget(to: new) }
        .onChange(of: model.state) { old, new in reactToState(from: old, to: new) }
        .onChange(of: model.fileDrag) { _, new in updateNeck(new) }
        .onChange(of: model.swallowToken) { _, _ in swallow() }
    }

    // MARK: Layers

    private var shownSize: CGSize {
        CGSize(width: dw < 0 ? model.shapeSize.width : dw, height: dh < 0 ? model.shapeSize.height : dh)
    }

    private func shownRadius(_ kind: NotchState.Kind) -> CGFloat {
        dr < 0 ? Self.radius(for: kind) : dr
    }

    private var lowPower: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    private func contentSize(_ kind: NotchState.Kind) -> CGSize {
        guard gooOn else { return shownSize }
        return (kind == .peek || kind == .hud) ? budSize : gooBase
    }

    @ViewBuilder
    private func bodyLayer(kind: NotchState.Kind) -> some View {
        if (gooOn || neckGoo) && !reduceMotion && kind != .expanded {
            let base = gooOn ? gooBase : shownSize
            JellyGoo(
                width: base.width, height: base.height,
                bud: gooOn ? min(budP, 1 + Jelly.overshootFraction) : 0,
                neckLength: neckLen, neckX: neckX,
                bodyRadius: gooOn ? Tokens.Radius.collapsed : shownRadius(kind),
                budSize: budSize, budRadius: Tokens.Radius.peek)
        } else {
            crispBody(kind: kind)
        }
    }

    private func crispBody(kind: NotchState.Kind) -> some View {
        let shown = shownSize
        let radius = shownRadius(kind)
        let touch = Jelly.touchShape(
            pointer: kind == .expanded ? JellyPointer() : model.pointer,
            width: shown.width, reduceMotion: reduceMotion)
        var width = shown.width * touch.scaleX
        let height = shown.height * touch.scaleY
        var bulge: CGFloat = 0
        var lean = touch.lean
        var skew: CGFloat = 0
        if !reduceMotion {
            width *= 1 + Jelly.swallowBulge * swallowAmount
            bulge = swallowAmount * min(10, max(4, Jelly.swallowBulge * height))
            lean += jiggle
            if kind == .collapsed { skew = model.swipeSkew }
        }
        let shape = JellyShape(width: width, height: height, bottomRadius: radius, lean: lean, skew: skew, bulge: bulge)
        return shape
            // The open panel draws its own black strip and glass body.
            .fill(kind == .expanded ? Color.clear : Tokens.notchBg)
            .overlay(
                shape.stroke(Tokens.textMuted, lineWidth: contrast == .increased && kind != .expanded ? 1 : 0))
            .animation(reduceMotion ? nil : Jelly.touch, value: model.pointer)
            .animation(reduceMotion ? nil : Jelly.touch, value: model.swipeSkew)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        let transition = Jelly.contentTransition(reduceMotion: reduceMotion)
        switch model.state {
        case .collapsed:
            CollapsedView(layout: model.layout, centerGap: model.centerGap)
                .contentShape(Rectangle())
                .onTapGesture { model.onTapCollapsed() }
                .transition(transition)
        case .peek(let event):
            PeekView(event: event, topInset: model.topInset)
                .transition(transition)
        case .hud(let reading):
            HUDCapsuleView(reading: reading, topInset: model.topInset)
                .transition(transition)
        case .expanded:
            ExpandedView(
                content: model.content,
                layout: model.layout,
                centerGap: model.centerGap,
                stripHeight: model.stripHeight,
                focusedTile: $model.focusedTile,
                focusToken: model.focusToken,
                onEscape: model.onEscape)
                .transition(transition)
        }
    }

    // MARK: Morphing

    private func snap(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    private func retarget(to target: CGSize) {
        let kind = model.state.kind
        let old = lastKind ?? kind
        lastKind = kind
        let current = shownSize
        let radius = Self.radius(for: kind)
        budTask?.cancel()

        if reduceMotion {
            // Sizes snap; the content cross-fades.
            gooOn = false
            snap { dw = target.width; dh = target.height; dr = radius }
            return
        }

        let isBudKind: (NotchState.Kind) -> Bool = { $0 == .peek || $0 == .hud }
        let involvesPeek = old != kind && (isBudKind(old) || isBudKind(kind))
            && old != .expanded && kind != .expanded
        if involvesPeek, !lowPower {
            startBud(appearing: isBudKind(kind), current: current, target: target, radius: radius)
            return
        }

        gooOn = false
        let spring: Jelly.Spring
        if kind == .expanded, old != .expanded {
            spring = Jelly.openSpring
        } else if old == .expanded, kind != .expanded {
            spring = Jelly.closeSpring
        } else if involvesPeek {
            // Low Power Mode: no goo, the peek slides out of the body.
            spring = Jelly.budSpring
        } else {
            spring = Jelly.morphSpring
        }
        let grows = target.width > current.width
        withAnimation(spring.animation) { dw = target.width; dr = radius }
        withAnimation(grows ? spring.animation.delay(Jelly.heightLag) : spring.animation) { dh = target.height }
    }

    /// A peek buds off the collapsed body (or is reabsorbed into it) as goo, then the crisp
    /// shape takes over after the bud spring's settling time.
    private func startBud(appearing: Bool, current: CGSize, target: CGSize, radius: CGFloat) {
        gooOn = true
        if appearing {
            gooBase = current
            budSize = target
            budP = 0
        } else {
            gooBase = target
            budSize = current
            budP = 1
            snap { dw = target.width; dh = target.height; dr = radius }
        }
        let goal: CGFloat = appearing ? 1 : 0
        budTask = Task { @MainActor in
            // One frame so the start value is drawn before the spring runs.
            try? await Task.sleep(nanoseconds: 20_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(Jelly.bud) { budP = goal }
            try? await Task.sleep(nanoseconds: UInt64(Jelly.budSpring.settleTime * 1_000_000_000))
            guard !Task.isCancelled else { return }
            snap {
                dw = target.width; dh = target.height; dr = radius
                gooOn = false
                budP = 0
            }
        }
    }

    // MARK: File neck

    private func updateNeck(_ drag: FileDragState?) {
        neckTask?.cancel()
        guard !reduceMotion, !lowPower else {
            neckGoo = false
            return
        }
        if let drag {
            if !neckGoo {
                neckGoo = true
                neckLen = 0
                neckX = drag.x
            }
            let length = Jelly.neckLength(distance: drag.distance)
            neckTask = Task { @MainActor in
                if neckLen == 0 { try? await Task.sleep(nanoseconds: 20_000_000) }
                guard !Task.isCancelled else { return }
                withAnimation(Jelly.touch) { neckLen = length; neckX = drag.x }
            }
        } else {
            neckTask = Task { @MainActor in
                withAnimation(Jelly.bud) { neckLen = 0 }
                try? await Task.sleep(nanoseconds: UInt64(Jelly.budSpring.settleTime * 1_000_000_000))
                guard !Task.isCancelled else { return }
                neckGoo = false
            }
        }
    }

    // MARK: One-shot reactions

    /// A 6% bulge, then settle.
    private func swallow() {
        guard !reduceMotion else { return }
        reactionTask?.cancel()
        withAnimation(Jelly.touch) { swallowAmount = 1 }
        reactionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(Jelly.touch) { swallowAmount = 0 }
        }
    }

    /// A critical peek jiggles once: +3 pt, -3 pt, rest. Never a loop.
    private func reactToState(from old: NotchState, to new: NotchState) {
        guard !reduceMotion, case .peek(let event) = new, event.priority == .critical else { return }
        if case .peek(let before) = old, before.id == event.id { return }
        reactionTask?.cancel()
        reactionTask = Task { @MainActor in
            for value in [Jelly.jiggle, -Jelly.jiggle, 0] {
                withAnimation(Jelly.touch) { jiggle = value }
                try? await Task.sleep(nanoseconds: 110_000_000)
                guard !Task.isCancelled else { return }
            }
        }
    }

    static func radius(for kind: NotchState.Kind) -> CGFloat {
        switch kind {
        case .collapsed: return Tokens.Radius.collapsed
        case .peek, .hud: return Tokens.Radius.peek
        case .expanded: return Tokens.Radius.expanded
        }
    }
}
