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
    /// Token and timing figures per session id (decision 048), empty when the
    /// module is off or a session's transcript has not been found. A row with
    /// no entry here simply draws without figures.
    var stats: [String: SessionStats]
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
            VStack(alignment: .leading, spacing: NotchMetrics.tightSpacing) {
                Text("Agents")
                    .font(NotchType.sectionHeader)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Self.rowSpacing) {
                        ForEach(sessions) { session in
                            AgentLight(session: session, stats: stats[session.id], onFocus: onFocus)
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

/// A single row: a 12pt state light, the folder label, and the session's task
/// description, in a button that focuses the session's host. Blocked sessions
/// pulse gently — the "needs you" state must stand out (UI Principle #2) — and
/// a finished turn nobody has looked at yet shows a steady white light until
/// the row is clicked (decision 044).
///
/// The light's colour, shape, glyph and motion all come from
/// `AgentAppearance`, shared with the collapsed pill's dot (decision 062).
///
/// `NotchButtonStyle` is what makes it read as a control: the same capsule
/// highlight, hover outline and press state as the transport buttons above it,
/// and the same ≥28pt hit target.
private struct AgentLight: View {
    var session: AgentSession
    var stats: SessionStats?
    var onFocus: (AgentSession) -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: { onFocus(session) }) {
            HStack(spacing: 6) {
                AgentDot(appearance: appearance, size: Self.dotSize, pulsePhase: pulse)
                Text(session.label)
                    .font(NotchType.row.weight(.medium))
                    .lineLimit(1)
                    // A floor keeps short folder names from letting the
                    // descriptions jag left and right down the list; the
                    // ceiling stops one long name from eating the row.
                    .frame(minWidth: 56, maxWidth: 108, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !session.task.isEmpty {
                    Text(session.task)
                        .font(NotchType.row)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 4)
                if let stats { StatsCluster(stats: stats) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // `scales: false` — a full-width row that grew on hover pushed its
        // capsule past the panel's content inset and got its ends clipped by
        // the notch shape. Fill and outline carry the hover state instead.
        .buttonStyle(NotchButtonStyle(scales: false))
        .help(helpText)
        // The state is spoken, not left to the dot's colour — the row would
        // otherwise read out as just a folder name and a task (HIG ▸ Colour:
        // never carry information in hue alone).
        .accessibilityLabel("\(session.label), \(appearance.label)")
        .accessibilityHint("Go to this session")
        .onAppear { syncPulse() }
        .onChange(of: appearance.pulses) { _, _ in syncPulse() }
    }

    private var appearance: AgentAppearance { AgentAppearance(session) }

    /// 12pt, not the old 10: `AgentDot` only draws its state glyph at or above
    /// `AgentDot.symbolThreshold`, and the glyph is the part that survives
    /// greyscale. The row is 28pt tall either way, so this costs no height.
    private static let dotSize: CGFloat = 12

    private func syncPulse() {
        if appearance.pulses {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { pulse = false }
        }
    }

    /// "Go to <folder>", plus what the row is showing. An unread row says what
    /// the click will do besides jumping — the light going out is otherwise an
    /// unexplained side effect.
    private var helpText: String {
        var text = "Go to \(session.label) — \(appearance.label)"
        if !session.task.isEmpty { text += "\n\(session.task)" }
        if session.unread { text += " (finished — click to mark as seen)" }
        if let stats {
            text += "\ncontext \(SessionStats.compactTokens(stats.contextTokens))"
                + " · session \(SessionStats.compactTokens(stats.sessionTokens))"
            if let elapsed = stats.elapsed(at: Date()) {
                text += " · \(stats.isTiming ? "running" : "last turn") "
                    + SessionStats.compactDuration(elapsed)
            }
        }
        return text
    }
}

/// The right-hand figures on an agent row (decision 048): tokens live in the
/// session's context, tokens the session has spent, and how long the current
/// turn has been running — or how long the last one took.
///
/// Deliberately unlabelled. Three labels would cost more width than the panel
/// has and would out-shout the task text beside them (UI Principle #1); the
/// two token counts are told apart by weight instead — the live one is the
/// brighter — and the row's tooltip names all three.
private struct StatsCluster: View {
    let stats: SessionStats

    /// The elapsed figure is the only thing here that changes between polls, so
    /// only it runs on a clock, and only while a turn is actually running: a
    /// row showing a finished turn's duration is static text.
    var body: some View {
        HStack(spacing: 4) {
            figure(SessionStats.compactTokens(stats.contextTokens), dim: false)
            separator
            figure(SessionStats.compactTokens(stats.sessionTokens), dim: true)
            if stats.isTiming {
                separator
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    figure(SessionStats.compactDuration(stats.elapsed(at: context.date) ?? 0), dim: false)
                }
            } else if let last = stats.lastTurnDuration {
                separator
                figure(SessionStats.compactDuration(last), dim: true)
            }
        }
        .font(NotchType.figure)
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "context \(stats.contextTokens) tokens, "
            + "\(stats.sessionTokens) tokens spent"
        )
    }

    private var separator: some View {
        Text("·").foregroundColor(.secondary.opacity(0.35))
    }

    private func figure(_ text: String, dim: Bool) -> some View {
        Text(text).foregroundColor(.secondary.opacity(dim ? 0.55 : 1))
    }
}
