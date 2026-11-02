import SwiftUI

/// Every animation in the kit lives here so the feel can be tuned in one place.
enum CKMotion {
    /// Press-down / release on any button.
    static let press = Animation.spring(response: 0.25, dampingFraction: 0.7)
    /// Selected ⇄ idle (fill + outline), mode swaps, zoom label.
    static let select = Animation.spring(response: 0.35, dampingFraction: 0.8)
    /// Ruler snapping to a stop after release.
    static let ruler = Animation.spring(response: 0.30, dampingFraction: 0.85)
    /// Panels entering/leaving (histogram, focus rail ⇄ MF stub, BKT badge).
    static let panel = Animation.spring(response: 0.45, dampingFraction: 0.82)
    /// Histogram bars following the live signal.
    static let histogram = Animation.easeOut(duration: 0.12)
    /// Dim of exposure rulers when hidden/disabled.
    static let fade = Animation.easeOut(duration: 0.18)
}

extension AnyTransition {
    /// Histogram / overlay panels: scale from the top edge + fade.
    static var panelPop: AnyTransition {
        .scale(scale: 0.96, anchor: .top).combined(with: .opacity)
    }
    /// Focus rail ⇄ manual stub.
    static var railSwap: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.96))
    }
    /// BKT badge sliding in from the leading edge.
    static var badgeSlide: AnyTransition {
        .move(edge: .leading).combined(with: .opacity)
    }
    /// Mode key letter change.
    static var glyphSwap: AnyTransition {
        .scale(scale: 0.6).combined(with: .opacity)
    }
}

/// Generic button style: scales to 0.94 while pressed.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(CKMotion.press, value: configuration.isPressed)
    }
}
