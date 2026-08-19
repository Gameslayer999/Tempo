import SwiftUI

/// Dynamic-Island-style visualizer beside the notch (decision 004:
/// playback-synced animation, not a real audio tap). While playing, each bar
/// bounces to a height driven by two layered sine waves at a per-bar
/// frequency/phase so the bars never move in lockstep. While paused, bars
/// ease down to a uniform minimal stub. `TimelineView(.animation)` supplies
/// the clock — no timers, no @State animation loop.
struct VisualizerView: View {
    var isPlaying: Bool

    private let barCount = 5
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2.5
    private let maxBarHeight: CGFloat = 16
    private let minFraction: CGFloat = 0.15
    private let transitionDuration: TimeInterval = 0.35

    @State private var transitionStart = Date.now

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let energy = playEnergy(at: context.date)
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: barWidth, height: maxBarHeight * fraction(index: index, time: t, energy: energy))
                }
            }
        }
        .onChange(of: isPlaying) { _, _ in
            transitionStart = Date.now
        }
    }

    /// 0 = fully paused/settled, 1 = fully playing. Eases smoothly across
    /// `transitionDuration` whenever `isPlaying` flips, so the bars glide to
    /// their resting state instead of snapping.
    private func playEnergy(at date: Date) -> CGFloat {
        let progress = min(max(date.timeIntervalSince(transitionStart) / transitionDuration, 0), 1)
        let eased = progress * progress * (3 - 2 * progress) // smoothstep
        return isPlaying ? CGFloat(eased) : CGFloat(1 - eased)
    }

    /// Height fraction (of `maxBarHeight`) for one bar at time `t`, blended
    /// from the idle stub height up to its organic playing height by `energy`.
    private func fraction(index: Int, time: Double, energy: CGFloat) -> CGFloat {
        let freqHz = 1.3 + Double(index) * 0.4
        let phase = Double(index) * 2.1
        let wave = sin(2 * .pi * freqHz * time + phase) * 0.75
            + sin(2 * .pi * freqHz * 2.7 * time + phase * 1.3) * 0.25
        let normalized = (wave + 1) / 2 // 0...1
        let midBiased = 0.5 + (normalized - 0.5) * 0.7 // pull extremes toward the middle
        let playingFraction = min(max(minFraction + midBiased * (1 - minFraction), minFraction), 1)
        return minFraction + energy * (playingFraction - minFraction)
    }
}
