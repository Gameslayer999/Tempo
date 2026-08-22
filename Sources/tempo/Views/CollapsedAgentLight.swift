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

/// One dot. Blocked and just-finished pulse; everything else is steady, so
/// motion in the pill only ever means "this one wants you" or "this one is
/// done" (UI Principle #5).
private struct SummaryDot: View {
    var summary: AgentSummary

    @State private var pulse = false

    private var color: Color {
        switch summary {
        case .error: return .red
        case .blocked: return .orange
        case .finished: return .white
        case .running: return .green
        case .idle, .none: return .gray
        }
    }

    private var pulses: Bool { summary == .blocked || summary == .finished }

    var body: some View {
        Circle()
            .fill(color)
            // Idle is present but recessive: it is the state nobody acts on,
            // and at full strength a row of grey dots competes with the
            // visualizer beside it.
            .opacity(summary == .idle ? 0.4 : (pulses && pulse ? 0.45 : 1))
            .scaleEffect(pulses && pulse ? 1.2 : 1)
            .frame(width: CollapsedAgentLight.dotSize, height: CollapsedAgentLight.dotSize)
            .shadow(color: color.opacity(pulses ? 0.7 : 0), radius: 3)
            .onAppear { syncPulse() }
            // Unlike the expanded panel's rows — which are created fresh each
            // time the panel opens — this dot is long-lived and changes state
            // under the pointer, so the animation has to be re-armed on every
            // transition, not just on appear.
            .onChange(of: summary) { _, _ in syncPulse() }
    }

    private func syncPulse() {
        if pulses {
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                pulse = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { pulse = false }
        }
    }
}
