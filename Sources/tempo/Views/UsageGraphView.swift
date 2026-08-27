import SwiftUI

/// Compact iStat-Menus-style CPU/memory row for the expanded panel: an icon,
/// the current value, and a 22pt-tall sparkline of the last 60 samples per
/// metric, sourced from `SystemStatsService`. The two cells split the panel's
/// full content width evenly, so each sparkline is as wide as the layout
/// allows. Headerless by design — the whole row is budgeted at <=30pt tall, and a section header (as
/// `AgentLightsView` uses for "Agents") would blow that budget for no
/// glanceability gain; the `cpu`/`memorychip` glyphs already label each cell
/// (UI Principle #1).
struct UsageGraphView: View {
    @ObservedObject private var stats = SystemStatsService.shared

    var body: some View {
        HStack(spacing: 14) {
            StatCell(symbolName: "cpu", label: "CPU", value: stats.cpuUsage, history: stats.cpuHistory)
            StatCell(symbolName: "memorychip", label: "Memory", value: stats.memUsage, history: stats.memHistory)
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .onAppear {
            stats.start()
        }
    }
}

/// One "icon + value + sparkline" cell. Renders "--" instead of a value
/// while `value` is nil (first tick after launch) rather than a fake 0%,
/// per UI Principle #4 — a wrong signal is worse than no signal.
private struct StatCell: View {
    let symbolName: String
    let label: String
    let value: Double?
    let history: [Double]

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(NotchType.subtitle)
                .foregroundStyle(.secondary)

            Text(valueText)
                .font(NotchType.figure.weight(.semibold))
                .foregroundStyle(valueColor)
                .frame(minWidth: 26, alignment: .leading)

            ZStack {
                Sparkline(samples: history, filled: true)
                    .fill(Color.secondary.opacity(0.15))
                Sparkline(samples: history, filled: false)
                    .stroke(Color.secondary, lineWidth: 1)
            }
            .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var valueText: String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))%"
    }

    /// Attention tint: red once the metric exceeds 80, per the same
    /// orange/red-stands-out convention `AgentLightsView` uses for sessions
    /// that need the user (UI Principle #2).
    private var valueColor: Color {
        guard let value, value > 80 else { return .primary }
        return .red
    }

    private var accessibilityText: String {
        guard let value else { return "\(label) usage unavailable" }
        return "\(label) usage \(Int(value.rounded())) percent"
    }
}

/// Line/area for a 0...100-scale history, fixed-scale (never autoscaled —
/// 0 and 100 are meaningful bounds, not "min/max of the sample window").
/// Shorter-than-60-sample histories anchor to the trailing (right) edge so
/// newest is always at the right and the line fills in left-to-right as
/// samples accumulate, then scrolls normally once at capacity.
///
/// Deliberately a plain `Shape`/`Path` — no `Canvas`, no Swift Charts, per
/// the task's explicit ban (Canvas's one-time ~93MB Metal allocation is
/// disproportionate for a tiny notch app).
private struct Sparkline: Shape {
    var samples: [Double]
    var filled: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard samples.count >= 2, rect.width > 0, rect.height > 0 else { return path }

        let capacity = SystemStatsService.historyLimit
        let stepX = rect.width / CGFloat(capacity - 1)
        let startIndex = capacity - samples.count

        func point(_ index: Int) -> CGPoint {
            let clamped = min(max(samples[index], 0), 100)
            let x = rect.minX + CGFloat(startIndex + index) * stepX
            let y = rect.maxY - CGFloat(clamped / 100) * rect.height
            return CGPoint(x: x, y: y)
        }

        path.move(to: point(0))
        for i in 1..<samples.count {
            path.addLine(to: point(i))
        }

        if filled {
            path.addLine(to: CGPoint(x: point(samples.count - 1).x, y: rect.maxY))
            path.addLine(to: CGPoint(x: point(0).x, y: rect.maxY))
            path.closeSubpath()
        }

        return path
    }
}
