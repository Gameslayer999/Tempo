import SwiftUI

/// One colored light per live Claude Code session (decision 005). Reads only
/// `state`/`label` off `AgentSession` — never the status file's `task`/
/// `detail` fields (Agent Guideline #5).
///
/// Hides itself entirely when there are no sessions, so the feature never
/// adds chrome to the expanded panel when AgentStatus isn't running
/// (Agent Guideline #3, UI Principle #1).
struct AgentLightsView: View {
    var sessions: [AgentSession]

    var body: some View {
        if sessions.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Agents")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.gray)
                    .textCase(.uppercase)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(sessions) { session in
                            AgentLight(session: session)
                        }
                    }
                }
            }
            // Keeps the whole feature inside the ~400x~50pt budget of the
            // expanded panel's agent row regardless of session count.
            .frame(maxWidth: .infinity, maxHeight: 50, alignment: .leading)
        }
    }
}

/// A single ~10pt colored dot + label. Blocked sessions pulse gently — the
/// "needs you" state must stand out (UI Principle #2).
private struct AgentLight: View {
    var session: AgentSession

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            indicator
            Text(session.label)
                .font(.system(size: 11))
                .foregroundColor(.gray.opacity(0.9))
                .lineLimit(1)
        }
        .onAppear {
            guard session.state == "blocked" else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch session.state {
        case "running", "blocked", "error", "idle":
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .opacity(session.state == "blocked" && pulse ? 0.45 : 1.0)
                .scaleEffect(session.state == "blocked" && pulse ? 1.25 : 1.0)
        default:
            // Unknown state: a hollow gray ring rather than a solid light,
            // so Tempo never asserts a state it doesn't recognize.
            Circle()
                .stroke(Color.gray.opacity(0.6), lineWidth: 1.5)
                .frame(width: 10, height: 10)
        }
    }

    private var color: Color {
        switch session.state {
        case "running": return .green
        case "blocked": return .orange
        case "error": return .red
        case "idle": return .gray
        default: return .gray
        }
    }
}
