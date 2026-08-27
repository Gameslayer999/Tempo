import SwiftUI

/// Seven-day token history for the expanded panel (decision 079): the week's
/// total, the model most of it went to, and one bar per local day with today's
/// bar picked out.
///
/// Drawn as a peer of `UsageGraphView` — same icon-then-figure-then-graph
/// shape, same 22pt graph height, same plain `Shape`/`Path` drawing (no
/// `Canvas`, no Swift Charts) — because the two sit in the same panel group and
/// a second visual language there would read as two unrelated widgets stacked
/// up rather than one panel.
///
/// Nothing here animates. The data moves once a minute at most and the bars are
/// a week of history, so motion would be noise rather than meaning
/// (UI Principle #5), which is also why there is nothing for Reduce Motion to
/// switch off.
struct UsageHistoryView: View {
    @ObservedObject var service: UsageHistoryService

    /// Dimmed marks get more of their colour under Increase Contrast, which is
    /// the whole of what that setting asks of a two-tone bar chart.
    @Environment(\.colorSchemeContrast) private var contrast

    /// Matches `UsageGraphView`'s sparkline height exactly.
    private static let barsHeight: CGFloat = 22

    private var total: Int { service.days.reduce(0) { $0 + $1.tokens } }

    var body: some View {
        // Nothing readable under ~/.claude/projects: the feature hides itself
        // rather than adding chrome that explains an absence (Agent
        // Guideline #3, UI Principle #1).
        if service.days.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: NotchMetrics.tightSpacing) {
                header
                if total == 0 {
                    Text("No usage in the last 7 days")
                        .font(NotchType.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    row
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { service.start() }
        }
    }

    private var header: some View {
        HStack(spacing: NotchMetrics.tightSpacing) {
            Text("Tokens · 7 days")
                .font(NotchType.sectionHeader)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let model = service.topModel {
                Text(model)
                    .font(NotchType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var row: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar")
                .font(NotchType.subtitle)
                .foregroundStyle(.secondary)

            Text(UsageHistoryService.shortTokens(total))
                .font(NotchType.figure.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(minWidth: 34, alignment: .leading)

            ZStack {
                DayBars(values: values, maxValue: peak, range: 0..<max(values.count - 1, 0))
                    .fill(Color.secondary.opacity(contrast == .increased ? 0.85 : 0.5))
                // Today is the bar the user is actually spending against, so it
                // is told apart by fill weight, not by hue alone (UI Principle #2).
                DayBars(values: values, maxValue: peak,
                        range: max(values.count - 1, 0)..<values.count)
                    .fill(Color.primary)
            }
            .frame(maxWidth: .infinity, minHeight: Self.barsHeight, maxHeight: Self.barsHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var values: [Int] { service.days.map(\.tokens) }

    /// Bars scale to the busiest day in the window, not to a fixed ceiling:
    /// unlike CPU percent there is no meaningful upper bound to draw against,
    /// and the question the row answers is "which days were heavy".
    private var peak: Int { max(values.max() ?? 0, 1) }

    private var accessibilityText: String {
        var text = "\(UsageHistoryService.shortTokens(total)) tokens over 7 days"
        if let today = service.days.last {
            text += ", \(UsageHistoryService.shortTokens(today.tokens)) today"
        }
        if let model = service.topModel { text += ", mostly \(model)" }
        return text
    }
}

/// One bar per day, oldest at the left, scaled to `maxValue`.
///
/// `range` is which of the bars this instance draws, so the caller can stack
/// two fills — the past week dim, today solid — without the two disagreeing
/// about bar geometry.
///
/// A zero day draws **nothing**: a stub bar would read as "a little" when the
/// truth is "none" (UI Principle #4). Non-zero days get a 1pt floor so a light
/// day next to a heavy one is still visible.
private struct DayBars: Shape {
    var values: [Int]
    var maxValue: Int
    var range: Range<Int>

    /// Gap between bars, as a fraction of a bar's slot.
    private static let gapFraction: CGFloat = 0.28

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !values.isEmpty, !range.isEmpty, rect.width > 0, rect.height > 0 else { return path }

        let slot = rect.width / CGFloat(values.count)
        let width = max(slot * (1 - Self.gapFraction), 1)
        let radius = min(width / 2, 1.5)

        for index in range where values.indices.contains(index) {
            let value = values[index]
            guard value > 0 else { continue }
            let height = max(rect.height * CGFloat(value) / CGFloat(maxValue), 1)
            let bar = CGRect(x: rect.minX + CGFloat(index) * slot + (slot - width) / 2,
                             y: rect.maxY - height,
                             width: width,
                             height: height)
            path.addRoundedRect(in: bar, cornerSize: CGSize(width: radius, height: radius))
        }
        return path
    }
}
