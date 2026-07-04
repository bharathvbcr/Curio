//
//  CurioMotion.swift
//  Curio
//
//  Ports: app/src/main/java/com/example/ui/theme/Motion.kt
//         (CurioMotion springs, Modifier.pressBounce, Modifier.bounceScale, curioExpandSpec).
//
//  CONVENTIONS §8 (Motion) + §10/§13 (Accessibility): `CurioMotion` springs map Compose
//  damping → SwiftUI (`bouncy/liquid/snappy/gentle` + `fade`). `CurioPressBounceStyle: ButtonStyle`
//  (scale to pressedScale on `isPressed`, `.sensoryFeedback(.impact(weight:.light))`,
//  `.accessibilityAddTraits(.isButton)`) replaces the Material ripple EVERYWHERE.
//  `bounceScale(active:)` is a NON-HIT-TESTING `.scaleEffect` modifier (must not steal taps).
//  Honor `accessibilityReduceMotion` (damp/disable springs and infinite animations).
//
//  Compose → SwiftUI spring mapping:
//   Compose `spring(dampingRatio, stiffness)` is a physical spring. SwiftUI's
//   `.interpolatingSpring(stiffness:damping:)` takes the same physical params, but the
//   Compose `dampingRatio` is a ζ (unitless), not the raw damping coefficient. We convert:
//     ω0 = sqrt(stiffness)              (undamped natural frequency, unit mass)
//     damping = 2 * dampingRatio * ω0   (critical-damping relation, c = 2ζ·sqrt(k·m), m = 1)
//   This reproduces the same overshoot/settle feel. Compose stiffness constants:
//     StiffnessLow = 200, StiffnessMediumLow = 400, StiffnessMedium = 1500.
//

import SwiftUI

/// Curio motion language — iOS-flavoured liquid & bouncy springs.
///
/// The whole app should feel physical: things overshoot a touch, settle softly, and react
/// to the finger. These specs mimic the UIKit spring feel (gentle overshoot, low stiffness)
/// rather than Material's rigid defaults.
enum CurioMotion {

    // Compose `Spring.Stiffness*` constants (Hooke's-law k, unit mass).
    private static let stiffnessLow: Double = 200
    private static let stiffnessMediumLow: Double = 400
    private static let stiffnessMedium: Double = 1500

    /// Converts a Compose `spring(dampingRatio, stiffness)` to the matching SwiftUI
    /// `interpolatingSpring`, using ω0 = √k and damping = 2ζω0 (unit mass).
    private static func spring(dampingRatio: Double, stiffness: Double) -> Animation {
        let omega0 = stiffness.squareRoot()
        let damping = 2 * dampingRatio * omega0
        return .interpolatingSpring(stiffness: stiffness, damping: damping)
    }

    /// Lively overshoot — great for appearance, FABs, selection pops.
    /// Compose: `spring(dampingRatio = 0.52f, stiffness = StiffnessMediumLow)`.
    static var bouncy: Animation { spring(dampingRatio: 0.52, stiffness: stiffnessMediumLow) }

    /// A softer, classier bounce for content size / expansion changes.
    /// Compose: `spring(dampingRatio = 0.72f, stiffness = StiffnessLow)`.
    static var liquid: Animation { spring(dampingRatio: 0.72, stiffness: stiffnessLow) }

    /// Quick, controlled response for press feedback.
    /// Compose: `spring(dampingRatio = 0.78f, stiffness = StiffnessMedium)`.
    static var snappy: Animation { spring(dampingRatio: 0.78, stiffness: stiffnessMedium) }

    /// Almost no overshoot — for things that must not look jiggly.
    /// Compose: `spring(dampingRatio = 0.9f, stiffness = StiffnessMediumLow)`.
    static var gentle: Animation { spring(dampingRatio: 0.9, stiffness: stiffnessMediumLow) }

    /// Smooth fade timing used to pair with spring movement.
    /// Compose: `tween(durationMillis = 240, easing = EaseInOutCubic)`.
    static var fade: Animation { .timingCurve(0.65, 0.0, 0.35, 1.0, duration: 0.240) }

    /// Content-size spring used for expand/collapse reveals (ports `curioExpandSpec()`,
    /// which returns `liquid()`).
    static var expand: Animation { liquid }

    /// Reduce-Motion-aware variant: returns a near-instant ease when the user has enabled
    /// Reduce Motion, otherwise the requested spring. Call sites that drive infinite or
    /// overshooting animation should route through this.
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : animation
    }
}

// MARK: - Press bounce (ButtonStyle)
//
// Ports `Modifier.pressBounce`. The Android default shrinks to 0.94, announces as a Button
// to a11y, and emits a light haptic tick on click. Here that becomes the single shared
// `ButtonStyle` used app-wide; wrap any tappable control in a `Button` to inherit it.

/// iOS-style "press to shrink, release to spring back" tap feedback, replacing the Material
/// ripple with a tactile scale bounce + light haptic. Use as the app-wide button style.
struct CurioPressBounceStyle: ButtonStyle {
    /// Scale applied while pressed. Mirrors Compose `pressBounce(pressedScale = 0.94f)`.
    var pressedScale: CGFloat = 0.94

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .animation(CurioMotion.resolved(CurioMotion.bouncy, reduceMotion: reduceMotion),
                       value: configuration.isPressed)
            // Light haptic on the press transition (Android emitted a TextHandleMove tick).
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in
                pressed
            }
            .accessibilityAddTraits(.isButton)
    }
}

extension ButtonStyle where Self == CurioPressBounceStyle {
    /// The app-wide press-bounce button style. `Button(...) { }.buttonStyle(.curioPressBounce)`.
    static var curioPressBounce: CurioPressBounceStyle { CurioPressBounceStyle() }

    /// Press-bounce with a custom pressed scale.
    static func curioPressBounce(pressedScale: CGFloat) -> CurioPressBounceStyle {
        CurioPressBounceStyle(pressedScale: pressedScale)
    }
}

// MARK: - bounceScale(active:)
//
// Ports `Modifier.bounceScale(active:activeScale:)` — a selection/active-state scale that
// MUST NOT consume taps (it layers over other gesture handling). Implemented as a plain
// `.scaleEffect` with `.allowsHitTesting(false)` semantics preserved by never attaching a
// gesture; the scale alone does not intercept hits.

private struct BounceScaleModifier: ViewModifier {
    let active: Bool
    let activeScale: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(active ? activeScale : 1.0)
            .animation(CurioMotion.resolved(CurioMotion.bouncy, reduceMotion: reduceMotion),
                       value: active)
    }
}

extension View {
    /// Animates this view's scale toward `activeScale` with a bouncy spring WITHOUT consuming
    /// the tap — for selection / active states layered atop other gesture handling.
    /// Mirrors Compose `Modifier.bounceScale(active:activeScale:)` (default `1.04`).
    func bounceScale(active: Bool, activeScale: CGFloat = 1.04) -> some View {
        modifier(BounceScaleModifier(active: active, activeScale: activeScale))
    }
}
