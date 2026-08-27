import SwiftUI

/// The agent signal in the *collapsed* pill (decision 042) — the third glance
/// signal alongside artwork and visualizer motion (UI Principle #1), so a
/// session that needs the user is visible without expanding anything.
///
/// Two shapes, chosen in Settings ▸ Modules:
/// - `.summary` — one dot carrying the most urgent state across every session.
/// - `.perSession` — up to `maxDots` dots in the panel's own priority order.
///
/// Draws nothing (and claims no width) when there are no live sessions, so the
/// pill keeps its bare geometry when AgentStatus isn't running.
struct CollapsedAgentLight: View {
    var sessions: [AgentSession]
    var mode: CollapsedAgentLightMode

    static let dotSize: CGFloat = 8
    static let dotSpacing: CGFloat = 4
    /// Ceiling on `.perSession`, so a busy machine can't grow the pill without
    /// bound. The sessions past it are in the expanded list.
    static let maxDots = 3

    /// Width this view occupies — the pill's geometry is laid out around it,
    /// so it has to be knowable without measuring.
    static func width(sessions: [AgentSession], mode: CollapsedAgentLightMode) -> CGFloat {
        guard !sessions.isEmpty else { return 0 }
        switch mode {
        case .off:
            return 0
        case .summary:
            return dotSize
        case .perSession:
            let count = min(sessions.count, maxDots)
            return CGFloat(count) * dotSize + CGFloat(count - 1) * dotSpacing
        }
    }

    var body: some View {
        switch mode {
        case .off:
            EmptyView()
        case .summary:
            SummaryDot(summary: AgentSummary(sessions))
        case .perSession:
            HStack(spacing: Self.dotSpacing) {
                ForEach(sessions.prefix(Self.maxDots)) { session in
                    SummaryDot(summary: AgentSummary([session]))
                }
            }
        }
    }
}

/// One dot. Only blocked pulses, so motion in the pill means exactly one
/// thing — "this one wants you" (UI Principle #5). A finished-and-unread
/// session is a solid white light with a steady halo: it is a state to notice,
/// not one to act on, and a second moving signal beside the visualizer made
/// the pill read as busy rather than glanceable (decision 045).
///
/// Colour, shape and motion all come from `AgentAppearance`, so this dot and
/// the expanded panel's rows cannot drift apart — and so idle reads as a
/// hollow ring rather than a dim green-ish disc, which is what makes the
/// states distinguishable without colour (decision 062).
private struct SummaryDot: View {
    var summary: AgentSummary

    @State private var pulse = false

    private var appearance: AgentAppearance { AgentAppearance(summary) }

    var body: some View {
        AgentDot(appearance: appearance,
                 size: CollapsedAgentLight.dotSize,
                 pulsePhase: pulse)
            .onAppear { syncPulse() }
            // Unlike the expanded panel's rows — which are created fresh each
            // time the panel opens — this dot is long-lived and changes state
            // under the pointer, so the animation has to be re-armed on every
            // transition, not just on appear.
            .onChange(of: summary) { _, _ in syncPulse() }
            .accessibilityLabel("Agent \(appearance.label)")
    }

    private func syncPulse() {
        if appearance.pulses {
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                pulse = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { pulse = false }
        }
    }
}
