import SwiftUI

/// Motion tokens from `docs/motion.md` ("Spring tokens"). Every number lives in this file, so
/// retuning the jelly is a one-line edit here. Nothing else in the app writes a spring.
enum Jelly {
    /// A SwiftUI `.spring(response:dampingFraction:)` and what is needed to reason about it.
    struct Spring: Equatable {
        let response: Double
        let damping: Double

        var animation: Animation { .spring(response: response, dampingFraction: damping) }

        /// Seconds until the motion is within about 2% of its target: the envelope e^(-ζωt) with
        /// ω = 2π / response, plus a small margin. Never shorter than one response.
        var settleTime: TimeInterval {
            let omega = 2 * Double.pi / response
            let t = -log(0.02) / (max(damping, 0.05) * omega)
            return max(response, t) + 0.05
        }
    }

    // MARK: Springs

    static let touchSpring = Spring(response: 0.28, damping: 0.55)
    static let morphSpring = Spring(response: 0.42, damping: 0.62)
    static let openSpring = Spring(response: 0.50, damping: 0.68)
    static let closeSpring = Spring(response: 0.36, damping: 0.80)
    static let budSpring = Spring(response: 0.45, damping: 0.50)

    /// Hover lean, press squash, release.
    static let touch = touchSpring.animation
    /// Collapsed to peek, wing width when activities rotate.
    static let morph = morphSpring.animation
    /// Collapsed to open panel.
    static let open = openSpring.animation
    /// Any close: snappier, almost no wobble.
    static let close = closeSpring.animation
    /// A secondary body budding off or being reabsorbed.
    static let bud = budSpring.animation

    // MARK: Content

    static let contentInDuration = 0.16
    static let contentInDelay = 0.08
    static let contentOutDuration = 0.10
    /// Content appears once the shape is about 60% there.
    static let contentIn = Animation.easeOut(duration: contentInDuration).delay(contentInDelay)
    /// Content leaves before the shape closes.
    static let contentOut = Animation.easeIn(duration: contentOutDuration)

    // MARK: Squash and stretch, overshoot

    /// Height starts this long after width when the body grows.
    static let heightLag: TimeInterval = 0.04
    /// No dimension overshoots more than 8% or 10 pt, whichever is smaller.
    static let overshootFraction: CGFloat = 0.08
    static let overshootPoints: CGFloat = 10

    /// The largest value a dimension aimed at `target` may reach while it springs.
    static func overshootLimit(target: CGFloat) -> CGFloat {
        target + min(abs(target) * overshootFraction, overshootPoints)
    }

    // MARK: Touch

    static let hoverSwell: CGFloat = 1.03
    static let pressWidth: CGFloat = 0.96
    static let pressHeight: CGFloat = 0.92
    static let swallowBulge: CGFloat = 0.06
    /// How far the body leans toward the pointer.
    static let maxLean: CGFloat = 6
    /// Shear for a horizontal swipe, in degrees.
    static let maxSkew: CGFloat = 4
    /// Horizontal drag/scroll distance (pt) that maps to `maxSkew` and triggers a swipe.
    static let swipeSkewScale: CGFloat = 20
    static let swipeTriggerDistance: CGFloat = 30
    /// The critical-peek jiggle, in points; played once.
    static let jiggle: CGFloat = 3

    // MARK: Budding goo

    /// A file drag shows the neck under 160 pt from the top edge and reaches full length at 60 pt.
    static let neckStartDistance: CGFloat = 160
    static let neckFullDistance: CGFloat = 60
    /// How far the neck hangs below the body at full length, in points.
    static let neckMaxLength: CGFloat = 44
    static let gooBlur: CGFloat = 10

    /// 0 at `neckStartDistance` and beyond, 1 at `neckFullDistance` and closer.
    static func neckFraction(distance: CGFloat) -> CGFloat {
        let span = neckStartDistance - neckFullDistance
        return min(1, max(0, (neckStartDistance - distance) / span))
    }

    static func neckLength(distance: CGFloat) -> CGFloat {
        neckFraction(distance: distance) * neckMaxLength
    }

    // MARK: Reduce Motion

    /// Every spring becomes this 0.2 s cross-fade; sizes snap.
    static let crossFade = Animation.easeInOut(duration: 0.2)

    /// `animation`, or the cross-fade when Reduce Motion is on.
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? crossFade : animation
    }

    /// Content in and out; both are the cross-fade under Reduce Motion.
    static func contentTransition(reduceMotion: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(reduceMotion ? crossFade : contentIn),
            removal: .opacity.animation(reduceMotion ? crossFade : contentOut))
    }

    /// Hover swell, press squash and lean for the resting body. Identity under Reduce Motion.
    static func touchShape(
        pointer: JellyPointer, width: CGFloat, reduceMotion: Bool
    ) -> (scaleX: CGFloat, scaleY: CGFloat, lean: CGFloat) {
        guard !reduceMotion else { return (1, 1, 0) }
        if pointer.pressed { return (pressWidth, pressHeight, 0) }
        guard pointer.hovering else { return (1, 1, 0) }
        let unit = min(1, max(-1, pointer.x / max(width / 2, 1)))
        return (hoverSwell, 1, unit * maxLean)
    }

    /// Shear angle (degrees) for a horizontal swipe delta. Identity under Reduce Motion.
    static func swipeSkew(deltaX: CGFloat, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return min(maxSkew, max(-maxSkew, deltaX / swipeSkewScale))
    }
}
