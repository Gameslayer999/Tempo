import SwiftUI

/// One row per live Claude Code session (decision 005) — colored light, folder
/// label, and a one-line description of what that session is working on
/// (decision 040) — each a button that goes to that session's window
/// (decision 035).
///
/// Hides itself entirely when there are no sessions, so the feature never
/// adds chrome to the expanded panel when AgentStatus isn't running
/// (Agent Guideline #3, UI Principle #1).
struct AgentLightsView: View {
    var sessions: [AgentSession]
    /// Called with the clicked session. The panel's collapse lives with the
    /// caller (ContentView), which owns the expansion state.
    var onFocus: (AgentSession) -> Void

    /// Rows visible before the list scrolls, and the row metrics used to turn
    /// that count into a height. 28pt is `NotchButtonStyle`'s minimum hit
    /// target, which is what sets a row's height.
    private static let visibleRows = 3
    private static let rowHeight: CGFloat = 28
    private static let rowSpacing: CGFloat = 2

    private var listHeight: CGFloat {
        let shown = min(sessions.count, Self.visibleRows)
        return CGFloat(shown) * Self.rowHeight
            + CGFloat(max(shown - 1, 0)) * Self.rowSpacing
    }

    var body: some View {
        if sessions.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Agents")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Self.rowSpacing) {
                        ForEach(sessions) { session in
                            AgentLight(session: session, onFocus: onFocus)
                        }
                    }
                }
                // Caps the feature at three rows so a busy machine can't grow
                // the expanded panel without bound; the rest scrolls.
                .frame(height: listHeight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A single row: ~10pt colored dot, folder label, and the session's task
/// description, in a button that focuses the session's host. Blocked sessions
/// pulse gently — the "needs you" state must stand out (UI Principle #2) — and
/// a finished turn nobody has looked at yet shows a steady white light until
/// the row is clicked (decision 044).
///
/// `NotchButtonStyle` is what makes it read as a control: the same capsule
/// highlight, hover outline and press state as the transport buttons above it,
/// and the same ≥28pt hit target.
private struct AgentLight: View {
    var session: AgentSession
    var onFocus: (AgentSession) -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: { onFocus(session) }) {
            HStack(spacing: 6) {
                indicator
                Text(session.label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    // A floor keeps short folder names from letting the
                    // descriptions jag left and right down the list; the
                    // ceiling stops one long name from eating the row.
                    .frame(minWidth: 56, maxWidth: 108, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !session.task.isEmpty {
                    Text(session.task)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // `scales: false` — a full-width row that grew on hover pushed its
        // capsule past the panel's content inset and got its ends clipped by
        // the notch shape. Fill and outline carry the hover state instead.
        .buttonStyle(NotchButtonStyle(scales: false))
        .help(helpText)
        .onAppear {
            guard session.state == "blocked" else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    /// "Go to <folder>", plus what the row is showing. An unread row says what
    /// the click will do besides jumping — the light going out is otherwise an
    /// unexplained side effect.
    private var helpText: String {
        var text = "Go to \(session.label)"
        if !session.task.isEmpty { text += " — \(session.task)" }
        if session.unread { text += " (finished — click to mark as seen)" }
        return text
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
        // An unacknowledged finished turn outranks the grey underneath it: the
        // session really is idle, but "done, and you haven't seen it" is the
        // thing worth drawing (decision 044). It never outranks a state the
        // user has to act on — a session cannot be both idle and blocked, so
        // the ordering here is only ever grey vs. white.
        if session.unread { return .white }
        switch session.state {
        case "running": return .green
        case "blocked": return .orange
        case "error": return .red
        case "idle": return .gray
        default: return .gray
        }
    }
}
