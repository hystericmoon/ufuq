import SwiftUI

/// The black body. A flat top edge fixed at the top of its rect, sides and a bottom that deform.
/// At rest (no lean, skew or bulge) it draws exactly the plain notch shape: square top corners,
/// circular bottom corners. Width and height are separate animatable values, so a caller can
/// drive them with different springs (height lagging width gives squash and stretch).
struct JellyShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var bottomRadius: CGFloat
    /// Sideways offset of the bottom edge, points. Clamped to ±`Jelly.maxLean`.
    var lean: CGFloat
    /// Shear of the sides, degrees. Clamped to ±`Jelly.maxSkew`.
    var skew: CGFloat
    /// How far the bottom edge bows downward in the middle, points. Never negative.
    var bulge: CGFloat

    init(
        width: CGFloat, height: CGFloat, bottomRadius: CGFloat,
        lean: CGFloat = 0, skew: CGFloat = 0, bulge: CGFloat = 0
    ) {
        self.width = width
        self.height = height
        self.bottomRadius = bottomRadius
        self.lean = Self.clampLean(lean)
        self.skew = Self.clampSkew(skew)
        self.bulge = max(0, bulge)
    }

    static func clampLean(_ value: CGFloat) -> CGFloat {
        min(Jelly.maxLean, max(-Jelly.maxLean, value))
    }

    static func clampSkew(_ degrees: CGFloat) -> CGFloat {
        min(Jelly.maxSkew, max(-Jelly.maxSkew, degrees))
    }

    typealias Data = AnimatablePair<
        AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>,
        AnimatablePair<CGFloat, CGFloat>>

    var animatableData: Data {
        get {
            AnimatablePair(
                AnimatablePair(AnimatablePair(width, height), AnimatablePair(bottomRadius, lean)),
                AnimatablePair(skew, bulge))
        }
        set {
            width = newValue.first.first.first
            height = newValue.first.first.second
            bottomRadius = newValue.first.second.first
            lean = newValue.first.second.second
            skew = newValue.second.first
            bulge = newValue.second.second
        }
    }

    /// Centered on the rect's mid x, hanging from its top edge.
    func path(in rect: CGRect) -> Path {
        let w = max(0, width)
        let h = max(0, height)
        guard w > 0, h > 0 else { return Path() }
        let r = min(max(0, bottomRadius), h / 2, w / 2)
        let radians = Double(Self.clampSkew(skew)) * Double.pi / 180
        let dx = Self.clampLean(lean) + h * CGFloat(tan(radians))
        let bow = max(0, bulge)

        let x0 = rect.midX - w / 2
        let x1 = rect.midX + w / 2
        let top = rect.minY
        let bottom = rect.minY + h

        var path = Path()
        path.move(to: CGPoint(x: x0, y: top))
        path.addLine(to: CGPoint(x: x1, y: top))
        // Right side and corner. Tangent arcs follow a slanted side as well as a vertical one.
        path.addArc(
            tangent1End: CGPoint(x: x1 + dx, y: bottom),
            tangent2End: CGPoint(x: x0 + dx, y: bottom),
            radius: r)
        let left = CGPoint(x: x0 + dx + r, y: bottom)
        if bow > 0 {
            // A quad curve reaches half its control offset, so double it to bow by `bow`.
            path.addQuadCurve(to: left, control: CGPoint(x: rect.midX + dx, y: bottom + 2 * bow))
        } else {
            path.addLine(to: left)
        }
        path.addArc(
            tangent1End: CGPoint(x: x0 + dx, y: bottom),
            tangent2End: CGPoint(x: x0, y: top),
            radius: r)
        path.closeSubpath()
        return path
    }
}

/// The body plus its secondary bodies, drawn through a blur and an alpha threshold so they merge
/// like metaballs. Used only while budding (a peek appears or goes, a file drag reaches for the
/// notch); the crisp `JellyShape` takes over once the spring settles.
struct JellyGoo: View, Animatable {
    var width: CGFloat
    var height: CGFloat
    /// 0 to about 1.08: how far the peek bud has grown toward `budSize`.
    var bud: CGFloat
    var neckLength: CGFloat
    /// Neck x, points from the body's centre.
    var neckX: CGFloat
    let bodyRadius: CGFloat
    let budSize: CGSize
    let budRadius: CGFloat

    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>
    > {
        get {
            AnimatablePair(
                AnimatablePair(width, height),
                AnimatablePair(bud, AnimatablePair(neckLength, neckX)))
        }
        set {
            width = newValue.first.first
            height = newValue.first.second
            bud = newValue.second.first
            neckLength = newValue.second.second.first
            neckX = newValue.second.second.second
        }
    }

    var body: some View {
        Canvas { context, size in
            // Added in this order, the blur runs first and the threshold cuts the blurred edge.
            context.addFilter(.alphaThreshold(min: 0.5, color: .black))
            context.addFilter(.blur(radius: Jelly.gooBlur))
            context.drawLayer { layer in
                let rect = CGRect(origin: .zero, size: size)
                let black = GraphicsContext.Shading.color(.black)
                let cap: CGFloat = 40
                // The body, with the top edge pushed above the window so the blur cannot thin it.
                layer.fill(
                    JellyShape(width: width, height: height, bottomRadius: bodyRadius).path(in: rect),
                    with: black)
                layer.fill(
                    Path(CGRect(x: rect.midX - width / 2, y: -cap, width: width, height: cap + 2)),
                    with: black)
                if bud > 0.001 {
                    let grown = CGSize(width: budSize.width * bud, height: budSize.height * bud)
                    layer.fill(
                        JellyShape(width: grown.width, height: grown.height, bottomRadius: budRadius).path(in: rect),
                        with: black)
                    layer.fill(
                        Path(CGRect(x: rect.midX - grown.width / 2, y: -cap, width: grown.width, height: cap + 2)),
                        with: black)
                }
                if neckLength > 0.5 {
                    let reach = max(0, width / 2 - 24)
                    let x = rect.midX + min(reach, max(-reach, neckX))
                    let tip = height + neckLength
                    layer.fill(
                        Path(roundedRect: CGRect(x: x - 7, y: height - 10, width: 14, height: neckLength + 10),
                             cornerRadius: 7),
                        with: black)
                    layer.fill(
                        Path(ellipseIn: CGRect(x: x - 10, y: tip - 10, width: 20, height: 20)),
                        with: black)
                }
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
