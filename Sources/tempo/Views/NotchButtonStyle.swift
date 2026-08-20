import SwiftUI

/// Shared style for every control in the expanded panel: transport buttons,
/// the playlist add button, Connect Spotify.
///
/// Gives each control a ≥28×28pt hit target, a soft capsule highlight while
/// hovered, and a distinct pressed state. Replaces the old
/// `.buttonStyle(.plain)` + `hoverScale()` pairing — a ButtonStyle can see
/// `configuration.isPressed`, a hover-only modifier cannot, so the press had
/// no feedback at all before.
struct NotchButtonStyle: ButtonStyle {
    /// Highlight opacities, shared so anything that can't *be* a
    /// `NotchButtonStyle` can still look like one. The playlist picker is a
    /// `Menu`, which a ButtonStyle can't reach, so it mirrors these instead of
    /// carrying its own magic numbers that would drift out of sync.
    static let hoverFill: Double = 0.18
    static let pressedFill: Double = 0.28
    static let hoverStroke: Double = 0.60
    static let hoverAnimation: Animation = .smooth(duration: 0.3)

    func makeBody(configuration: Configuration) -> some View {
        // Named anything but `Body`: that identifier is the protocol's own
        // associated type and shadowing it breaks the conformance.
        ControlBody(configuration: configuration)
    }

    private struct ControlBody: View {
        let configuration: ButtonStyleConfiguration

        @State private var isHovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(minWidth: 28, minHeight: 28)
                .background(Capsule().fill(Color.primary.opacity(fillOpacity)))
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed ? 0.88 : (isHovered ? 1.06 : 1.0))
                .animation(NotchButtonStyle.hoverAnimation, value: isHovered)
                .animation(.smooth(duration: 0.12), value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }

        private var fillOpacity: Double {
            if configuration.isPressed { return NotchButtonStyle.pressedFill }
            return isHovered ? NotchButtonStyle.hoverFill : 0
        }
    }
}
