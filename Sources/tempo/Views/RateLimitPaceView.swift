import SwiftUI

/// How hard the current five-hour window is being leaned on (decision 079):
/// a compact bar, the figures, and — past the user's warning threshold — a
/// warning appearance.
///
/// **The figure is an estimate and says so on the surface.** Claude Code
/// persists no rate-limit signal locally (verified on this machine), so what
/// the bar measures is tokens counted out of local transcripts against a
/// budget the user typed into Settings, not a limit anything reported. The
/// header carries the word "estimate" for exactly that reason — a bar that
/// implied it knew the real limit would be the lying signal UI Principle #4
/// rules out.
///
/// The warning state is never carried by hue alone (UI Principle #2): a
/// warning glyph appears, the percentage goes semibold, and the fill visibly
/// crosses the threshold mark that is drawn on the track at all times.
struct RateLimitPaceView: View {
    @ObservedObject var service: UsageHistoryService
    @ObservedObject var prefs: Preferences

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The bar itself, and the threshold mark that overhangs it top and bottom
    /// so the fill can never hide the mark it is being measured against.
    private static let barHeight: CGFloat = 6
    private static let markHeight: CGFloat = 10

    private var budget: Double { max(prefs.rateLimitWindowTokens, 1) }
    private var fraction: Double { Double(service.windowTokens) / budget }
    private var percent: Int { Int((fraction * 100).rounded()) }
    private var warnFraction: Double { min(max(prefs.rateLimitWarnPercent / 100, 0), 1) }
    private var isWarning: Bool { fraction >= warnFraction }
    private var isOver: Bool { fraction >= 1 }

    var body: some View {
        // No transcripts to read: no bar. An estimate drawn from nothing would
        // be worse than no signal at all (Agent Guideline #3, UI Principle #4).
        if service.days.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: NotchMetrics.tightSpacing) {
                header
                bar
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .onAppear { service.start() }
        }
    }

    private var header: some View {
        HStack(spacing: NotchMetrics.tightSpacing) {
            Text("5h pace · estimate")
                .font(NotchType.sectionHeader)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            if isWarning {
                Image(systemName: isOver ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                    .font(NotchType.caption)
                    .foregroundStyle(stateColor)
            }

            Text("\(UsageHistoryService.shortTokens(service.windowTokens))"
                 + " / \(UsageHistoryService.shortTokens(Int(budget)))")
                .font(NotchType.figure)
                .foregroundStyle(.secondary)

            Text("\(percent)%")
                .font(NotchType.figure.weight(isWarning ? .semibold : .regular))
                .foregroundStyle(stateColor)
                .frame(minWidth: 30, alignment: .trailing)
        }
    }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(contrast == .increased ? 0.4 : 0.2))
                    .frame(height: Self.barHeight)

                Capsule()
                    .fill(stateColor)
                    // Clamped at full: past the budget the bar is simply full
                    // and the percentage carries the overshoot. A fill wider
                    // than its track would say nothing the number doesn't.
                    .frame(width: fillWidth(in: geo.size.width), height: Self.barHeight)
                    // The value moves once a minute at most, so the ease is
                    // there only to keep the step from reading as a glitch.
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: fraction)

                // The threshold, drawn whether or not it has been crossed, so
                // "past the line" is a position on screen and not just a colour.
                RoundedRectangle(cornerRadius: 0.75)
                    .fill(Color.secondary.opacity(contrast == .increased ? 1 : 0.7))
                    .frame(width: 1.5, height: Self.markHeight)
                    .offset(x: geo.size.width * warnFraction - 0.75)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, minHeight: Self.markHeight, maxHeight: Self.markHeight)
    }

    private func fillWidth(in width: CGFloat) -> CGFloat {
        guard service.windowTokens > 0, width > 0 else { return 0 }
        // Never thinner than the capsule is tall, so a small-but-real figure
        // still shows as a mark rather than vanishing.
        return min(max(width * min(fraction, 1), Double(Self.barHeight)), width)
    }

    /// White while the window is comfortable, orange past the user's warning
    /// percentage, red past the budget — the same "attention states stand out"
    /// convention the agent lights use, and never the only difference between
    /// the two (UI Principle #2).
    private var stateColor: Color {
        if isOver { return .red }
        if isWarning { return .orange }
        return .primary
    }

    private var accessibilityText: String {
        let used = UsageHistoryService.shortTokens(service.windowTokens)
        let of = UsageHistoryService.shortTokens(Int(budget))
        let state = isOver ? ", over the estimated budget"
            : (isWarning ? ", past the warning threshold" : "")
        return "Estimated 5 hour pace: \(used) of \(of) tokens, \(percent) percent\(state)"
    }
}
