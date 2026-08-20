import SwiftUI

/// Dynamic-Island-style visualizer beside the notch.
///
/// Two modes, chosen per render:
///
/// * **Reactive** — while `AudioTapService` is delivering real levels, each bar
///   tracks one FFT band of Spotify's actual output.
/// * **Fallback** — otherwise (no Core Audio tap, unauthorized tap, Spotify not
///   running), the original playback-synced sine animation from decision 004.
///
/// Both modes render the same single `HStack` of five capsules, so switching
/// modes resizes the bars instead of replacing them. The `TimelineView` clock is
/// only needed by the fallback: it is paused outright in reactive mode and once
/// the paused-state transition has finished, so a resting notch costs zero
/// redraws. No `Canvas` — the first `Canvas` in a process costs a one-time
/// ~93 MB Metal allocation.
struct VisualizerView: View {
    let isPlaying: Bool

    @ObservedObject private var tap = AudioTapService.shared

    private let barCount = 5
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2.5
    private let maxBarHeight: CGFloat = 16
    private let minFraction: CGFloat = 0.15
    private let transitionDuration: TimeInterval = 0.35

    /// Bar index → band index. Bass sits in the centre bar and frequency rises
    /// outward (upper-mid, low-mid, **bass**, mid, treble), so the kick drum
    /// pulses the middle of the strip and the mirror is deliberately imperfect —
    /// a true mirror reads mechanical.
    private static let barToBand = [3, 1, 0, 2, 4]

    /// `distantPast` so the very first render — before `.task` has run — reads a
    /// completed transition. Starting at `.now` instead would leave a paused
    /// visualizer frozen at full playing height on appear.
    @State private var transitionStart = Date.distantPast
    @State private var settled = true

    init(isPlaying: Bool) {
        self.isPlaying = isPlaying
    }

    var body: some View {
        let reactive = tap.isCapturing
        TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                paused: reactive || (!isPlaying && settled))) { context in
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: barWidth,
                               height: maxBarHeight * fraction(index: index,
                                                               reactive: reactive,
                                                               date: context.date))
                }
            }
            // 30 Hz level updates interpolate across one frame interval so the
            // bars read as continuous motion instead of a step sequence.
            .animation(reactive ? .linear(duration: 1.0 / 30.0) : nil, value: tap.bands)
        }
        .task(id: isPlaying) {
            transitionStart = .now
            guard !isPlaying else {
                settled = false
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(transitionDuration * 1_000_000_000))
            if !Task.isCancelled { settled = true }
        }
    }

    /// Height fraction (of `maxBarHeight`) for one bar.
    private func fraction(index: Int, reactive: Bool, date: Date) -> CGFloat {
        if reactive {
            let band = tap.bands[Self.barToBand[index]]
            return max(minFraction, min(CGFloat(band), 1))
        }
        return sineFraction(index: index,
                            time: date.timeIntervalSinceReferenceDate,
                            energy: playEnergy(at: date))
    }

    /// 0 = fully paused/settled, 1 = fully playing. Eases smoothly across
    /// `transitionDuration` whenever `isPlaying` flips, so the bars glide to
    /// their resting state instead of snapping.
    private func playEnergy(at date: Date) -> CGFloat {
        let progress = min(max(date.timeIntervalSince(transitionStart) / transitionDuration, 0), 1)
        let eased = progress * progress * (3 - 2 * progress) // smoothstep
        return isPlaying ? CGFloat(eased) : CGFloat(1 - eased)
    }

    /// Fallback height fraction at time `t`, blended from the idle stub height
    /// up to its organic playing height by `energy`. Two layered sine waves at a
    /// per-bar frequency/phase keep the bars out of lockstep.
    private func sineFraction(index: Int, time: Double, energy: CGFloat) -> CGFloat {
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
