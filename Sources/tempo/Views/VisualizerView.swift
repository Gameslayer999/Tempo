import AppKit
import SwiftUI

/// Dynamic-Island-style visualizer beside the notch.
///
/// Two modes, chosen per render:
///
/// * **Reactive** — while `AudioTapService` is delivering real levels, each bar
///   tracks one FFT band of the machine's actual audio output, whichever app
///   is producing it (decision 056).
/// * **Fallback** — otherwise (no Core Audio tap, unauthorized tap, macOS
///   older than 14.2), the playback-synced sine animation from decision 004,
///   which can only follow the now-playing player's state.
///
/// Both modes render the same single `HStack` of five capsules, so switching
/// modes resizes the bars instead of replacing them. The `TimelineView` clock is
/// only needed by the fallback: it is paused outright in reactive mode and once
/// the paused-state transition has finished, so a resting notch costs zero
/// redraws. No `Canvas` — the first `Canvas` in a process costs a one-time
/// ~93 MB Metal allocation.
struct VisualizerView: View {
    let isPlaying: Bool
    /// The current cover's dominant colour, for the `.album` palette. Optional
    /// because the strip draws before any artwork has loaded — and because
    /// there may never be any.
    let artworkTint: NSColor?

    @ObservedObject private var prefs: Preferences
    @ObservedObject private var tap = AudioTapService.shared
    /// The visualizer is continuous motion with no end state — precisely what
    /// Reduce Motion exists to switch off, and the one animation in Tempo
    /// that was still running under it (the panel's spring and the onboarding
    /// stroke both already honour it).
    ///
    /// It cannot simply stop, because motion *is* this element's whole signal:
    /// a frozen bar row beside a playing track is the stale signal UI
    /// Principle #4 forbids. So the meaning is re-encoded as *height* instead
    /// — a static raised profile while audio is playing, a flat row when it
    /// is not. Same binary read at a glance, zero movement.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let barCount = 5
    private static let barWidth: CGFloat = 3
    private static let barSpacing: CGFloat = 2.5
    private static let maxBarHeight: CGFloat = 16
    /// Width the bar row actually occupies. The strip sizes its wings around
    /// this so the bars never overflow their slot and spill past the pill's
    /// rounded edge.
    static let naturalWidth: CGFloat = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
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
    /// Whether `.task(id:)` has already run once. Its first run is the view
    /// *appearing*, not a play-state change, so it must not start a transition
    /// — see the guard in the task below.
    @State private var didAppear = false

    /// What the *fallback* animation keys off. Playing into a muted (or
    /// zero-volume) output device is motion for something nobody can hear, so
    /// it settles the bars exactly as a pause does (decision 039) — otherwise
    /// muting would only swap the reactive bars for sine bars, which is the
    /// same lie in a different mode.
    private var animating: Bool { isPlaying && tap.outputAudible }

    /// `artworkTint` and `prefs` both default, so the strip's existing call
    /// site keeps compiling unchanged; pass the real cover tint to make the
    /// `.album` palette do anything.
    ///
    /// `prefs` defaults through `nil` rather than to `.shared` directly because
    /// a default-argument expression is evaluated outside the initializer's
    /// isolation, and `Preferences.shared` is `@MainActor`.
    @MainActor
    init(isPlaying: Bool, artworkTint: NSColor? = nil, prefs: Preferences? = nil) {
        self.isPlaying = isPlaying
        self.artworkTint = artworkTint
        self.prefs = prefs ?? .shared
    }

    var body: some View {
        Group {
            if reduceMotion {
                still
            } else {
                live
            }
        }
        .accessibilityLabel(animating ? "Audio playing" : "Audio stopped")
        .task(id: animating) {
            // Only a real change in whether the bars should be moving
            // starts a transition. `.task(id:)`
            // also fires once when the view appears, and stamping
            // `transitionStart = .now` there re-created exactly the hazard the
            // `distantPast` initial value exists to avoid: on a paused launch
            // `playEnergy` reads progress ≈ 0, so `1 - eased` ≈ 1 — full
            // playing height — and because the timeline is paused whenever
            // `!isPlaying && settled` (both true on a paused launch), that
            // frame is the one that stays on screen. Measured: bar fractions
            // [0.57, 0.80, 0.33, 0.65, 0.69] instead of a flat [0.15 × 5], and
            // frozen there, so a launch with nothing playing looked exactly
            // like music playing.
            if didAppear {
                transitionStart = .now
            } else {
                didAppear = true
            }
            guard !animating else {
                settled = false
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(transitionDuration * 1_000_000_000))
            if !Task.isCancelled { settled = true }
        }
    }

    /// The moving visualizer: reactive bands when the tap is delivering them,
    /// the sine fallback otherwise.
    private var live: some View {
        let reactive = tap.isCapturing
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                       paused: reactive || (!animating && settled))) { context in
            bars { index in
                fraction(index: index, reactive: reactive, date: context.date)
            }
            // 30 Hz level updates interpolate across one frame interval so the
            // bars read as continuous motion instead of a step sequence.
            .animation(reactive ? .linear(duration: 1.0 / 30.0) : nil, value: tap.bands)
        }
    }

    /// Reduce Motion: no clock at all, so the row is genuinely static rather
    /// than animating slowly. Playing draws a fixed asymmetric profile — bass
    /// tallest in the centre, exactly where the moving version puts it, so the
    /// shape is recognisably the same element — and silence draws the flat
    /// stub row. Crossing between them is a single eased height change, which
    /// is a state transition rather than ongoing motion, and is what the HIG
    /// asks for in place of a loop.
    private var still: some View {
        bars { index in animating ? Self.staticProfile[index] : minFraction }
            .animation(.easeInOut(duration: 0.2), value: animating)
    }

    /// Height fractions of the resting "audio is playing" silhouette.
    private static let staticProfile: [CGFloat] = [0.45, 0.72, 1.0, 0.72, 0.45]

    private func bars(_ height: @escaping (Int) -> CGFloat) -> some View {
        HStack(spacing: Self.barSpacing) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                Capsule()
                    .fill(fill(bar: index))
                    .frame(width: Self.barWidth, height: Self.maxBarHeight * height(index))
            }
        }
    }

    // MARK: - Colour

    /// The fill every bar had before decision 071, and still the default. Also
    /// the fallback for `.album` with no cover, because the alternative — a bar
    /// row that changes colour depending on whether artwork happened to have
    /// loaded yet — is the flicker UI Principle #1 is about.
    private static let monochrome = Color.white.opacity(0.92)

    /// One bar's fill (decision 071). Colour only: nothing here reads
    /// `animating`, `reduceMotion` or the clock, so a palette can neither start
    /// motion Reduce Motion suppressed nor keep the bars from settling — the
    /// height functions remain the sole source of both.
    private func fill(bar index: Int) -> Color {
        switch prefs.spectrogramPalette {
        case .monochrome:
            return Self.monochrome
        case .accent:
            return NotchAccent.color(for: prefs)
        case .album:
            // Through the same legibility clamp the accent uses:
            // `NSImage.dominantColor()` floors HSB *brightness* at 0.6, which
            // for a saturated blue cover is still only 1.05:1 against the dark
            // panel — bars that are technically drawn and practically gone.
            guard let artworkTint else { return Self.monochrome }
            return Color(nsColor: NotchAccent.legible(artworkTint))
        case .spectrum:
            return Self.spectrum[Self.barToBand[index]]
        }
    }

    /// A hue per **band**, bass → treble — indexed by band, not by bar, so the
    /// ramp follows frequency the way `barToBand` lays it out: warm in the
    /// centre where the bass sits, cooling outward. Indexing by bar instead
    /// would paint a left-to-right gradient across a row whose heights are
    /// arranged around the middle, and the two orderings would visibly disagree.
    ///
    /// Fixed sRGB values rather than a runtime clamp: all five are chosen at a
    /// common saturation 0.58 / brightness 1.0, the most saturated the ramp can
    /// be while its darkest member still clears 4.5:1 on the dark panel. Against
    /// the backdrop `NotchAccent` models — bass 6.10:1, low-mid 10.59:1, mid
    /// 11.92:1, upper-mid 9.97:1, treble 4.77:1 — so they need no clamp under
    /// either contrast setting.
    private static let spectrum: [Color] = [
        Color(red: 1.00, green: 0.50, blue: 0.42), // bass       hue   8°
        Color(red: 1.00, green: 0.83, blue: 0.42), // low-mid    hue  42°
        Color(red: 0.42, green: 1.00, blue: 0.71), // mid        hue 150°
        Color(red: 0.42, green: 0.88, blue: 1.00), // upper-mid  hue 192°
        Color(red: 0.73, green: 0.42, blue: 1.00), // treble     hue 272°
    ]

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
        return animating ? CGFloat(eased) : CGFloat(1 - eased)
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
