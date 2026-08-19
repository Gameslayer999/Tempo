import SwiftUI

/// A small springy scale-up on hover for interactive controls (transport
/// buttons, the playlist menu/add button, the Connect Spotify button).
/// Not applied to the agent lights or the strip — those aren't buttons.
private struct HoverScale: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.15 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    /// Scales this view up slightly on hover with a quick spring.
    func hoverScale() -> some View {
        modifier(HoverScale())
    }
}
