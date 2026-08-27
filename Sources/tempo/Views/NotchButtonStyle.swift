import SwiftUI

/// Shared style for every control in the expanded panel: transport buttons,
/// the playlist add button, Connect Spotify.
///
/// Gives each control a ≥28×28pt hit target, a soft capsule highlight and
/// outline while hovered, and a distinct pressed state. Replaces the old
/// `.buttonStyle(.plain)` + `hoverScale()` pairing — a ButtonStyle can see
/// `configuration.isPressed`, a hover-only modifier cannot, so the press had
/// no feedback at all before.
struct NotchButtonStyle: ButtonStyle {
    /// Whether hover and press scale the control. True for the compact
    /// controls the style was built for; **false for anything full-width**,
    /// where growing 6% pushes the capsule past the panel's content inset and
    /// the shape clips its ends off (seen on the agent rows). Such a control
    /// still reads its state from the fill and the hover outline, which is the
    /// usual treatment for a list row anyway.
    var scales: Bool = true

    /// Highlight opacities, shared so anything that can't *be* a
    /// `NotchButtonStyle` can still look like one. The playlist picker is a
    /// `Menu`, which a ButtonStyle can't reach, so it mirrors these instead of
    /// carrying its own magic numbers that would drift out of sync.
    static let hoverFill: Double = 0.18
    static let pressedFill: Double = 0.28
    static let hoverStroke: Double = 0.60
    /// What a control shows at rest under Increase Contrast, so it is a
    /// visible control rather than a glyph waiting to be discovered.
    static let restingFill: Double = 0.10
    static let restingStroke: Double = 0.45
    static let hoverAnimation: Animation = .smooth(duration: 0.3)

    func makeBody(configuration: Configuration) -> some View {
        // Named anything but `Body`: that identifier is the protocol's own
        // associated type and shadowing it breaks the conformance.
        ControlBody(configuration: configuration, scales: scales)
    }

    private struct ControlBody: View {
        let configuration: ButtonStyleConfiguration
        let scales: Bool

        @State private var isHovered = false
        /// Increase Contrast means "show me where the controls are". At rest
        /// these buttons are bare glyphs with no plate at all — findable by
        /// hovering, which is exactly the discovery the setting exists to
        /// remove (HIG ▸ Accessibility). Turned on, every control keeps a
        /// resting fill and border whether or not the pointer is near it.
        @Environment(\.colorSchemeContrast) private var contrast
        /// The 6% hover growth and the 12% press shrink are decoration, not
        /// information — the fill and the outline already carry both states —
        /// so Reduce Motion drops them entirely.
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var highContrast: Bool { contrast == .increased }

        var body: some View {
            configuration.label
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(minWidth: NotchMetrics.hitTarget, minHeight: NotchMetrics.hitTarget)
                .background(Capsule().fill(Color.primary.opacity(fillOpacity)))
                // Outline on hover, marking the hit area — the same treatment
                // the playlist picker already mirrors from these buttons, now
                // drawn by the style itself so every control in the panel
                // (transport, gear, agent lights) highlights identically.
                .overlay(
                    Capsule().strokeBorder(
                        Color.primary.opacity(strokeOpacity),
                        lineWidth: 1.5
                    )
                )
                .contentShape(Rectangle())
                .scaleEffect(scaleFactor)
                .animation(NotchButtonStyle.hoverAnimation, value: isHovered)
                .animation(.smooth(duration: 0.12), value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }

        private var scaleFactor: CGFloat {
            guard scales, !reduceMotion else { return 1.0 }
            return configuration.isPressed ? 0.88 : (isHovered ? 1.06 : 1.0)
        }

        private var fillOpacity: Double {
            if configuration.isPressed { return NotchButtonStyle.pressedFill }
            if isHovered { return NotchButtonStyle.hoverFill }
            return highContrast ? NotchButtonStyle.restingFill : 0
        }

        private var strokeOpacity: Double {
            if isHovered { return NotchButtonStyle.hoverStroke }
            return highContrast ? NotchButtonStyle.restingStroke : 0
        }
    }
}
