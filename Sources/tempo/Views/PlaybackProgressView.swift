import SwiftUI

/// The expanded panel's scrubber (decision 041): elapsed time, a draggable
/// progress bar, and time remaining, spanning the panel's full content width.
///
/// The bar advances without anything publishing at its frame rate. `AppState`
/// holds a `PlaybackProgress` *anchor* — a position and the instant it was
/// true — and this view extrapolates from it on a `TimelineView` clock, so a
/// playing track costs 4 redraws a second of this subtree and zero state
/// changes. When nothing is playing the schedule is dropped entirely: a paused
/// anchor is already correct at every date, so there is nothing to tick.
///
/// This view exists only while the panel is expanded (it lives inside
/// `ContentView.expandedContent`), which is what keeps the collapsed pill at
/// its measured zero-timer rest state (decision 016).
struct PlaybackProgressView: View {
    let progress: PlaybackProgress
    /// Seek target, in seconds. Called once, when the drag ends or on a plain
    /// click — never continuously (decision 041): each call is an AppleScript
    /// round-trip and Spotify audibly re-buffers on every one.
    let onSeek: (TimeInterval) -> Void

    /// 4Hz. Against the widest the bar gets on this machine (353pt over a
    /// typical 3-4 minute track ≈ 1.7pt per second) each tick advances the
    /// knob well under a point, so it reads as continuous motion; the labels
    /// only change once a second anyway.
    private static let tickInterval: TimeInterval = 0.25

    private static let trackHeight: CGFloat = 4
    private static let knobSize: CGFloat = 9
    /// Total height of the bar's hit area. The drawn track is 4pt tall, which
    /// is far too thin to hit reliably; the gesture takes this whole band.
    private static let hitHeight: CGFloat = 20

    /// Where the knob is being dragged to, while a drag is in progress. Takes
    /// over from the clock so the knob tracks the pointer exactly instead of
    /// fighting the extrapolated position.
    @State private var dragFraction: Double?
    @State private var isHovered = false

    /// One clock drives the whole row — bar and both labels — so the digits
    /// can never disagree with the knob.
    ///
    /// Ticks only while playing and not being dragged. A `TimelineView`
    /// schedule is chosen when the view is built, so the still branch installs
    /// no timer at all rather than one redrawing an unchanging value: a paused
    /// anchor reads the same at every date, and a drag is driven by the
    /// pointer, not by time.
    var body: some View {
        if progress.isPlaying && dragFraction == nil {
            TimelineView(.periodic(from: .now, by: Self.tickInterval)) { context in
                row(at: context.date)
            }
        } else {
            row(at: progress.anchorDate)
        }
    }

    // MARK: Row

    private func row(at date: Date) -> some View {
        // A drag overrides the clock entirely, so the knob tracks the pointer
        // exactly and the labels read out where releasing would seek to.
        let position = dragFraction.map { $0 * progress.duration } ?? progress.position(at: date)
        let fraction = progress.duration > 0 ? position / progress.duration : 0
        return HStack(spacing: 8) {
            timeLabel(Self.clock(position), alignment: .leading)
            track(fraction: fraction)
                .frame(height: Self.hitHeight)
            timeLabel("-" + Self.clock(progress.duration - position), alignment: .trailing)
        }
    }

    private func track(fraction: Double) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clamped = min(max(fraction, 0), 1)
            // Kept a knob-radius inside each end so the knob is never drawn
            // half outside the bar at 0:00 or at the end of the track.
            let inset = Self.knobSize / 2
            let knobX = inset + clamped * max(width - Self.knobSize, 0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.22))
                    .frame(height: Self.trackHeight)
                Capsule()
                    .fill(Color.primary.opacity(0.85))
                    .frame(width: knobX, height: Self.trackHeight)
                Circle()
                    .fill(Color.primary)
                    .frame(width: Self.knobSize, height: Self.knobSize)
                    .scaleEffect(isHovered || dragFraction != nil ? 1.35 : 1.0)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .position(x: knobX, y: geo.size.height / 2)
            }
            .frame(height: geo.size.height, alignment: .center)
            // The gesture takes the full 20pt band, not just the 4pt track.
            .contentShape(Rectangle())
            .gesture(
                // `minimumDistance: 0` so a plain click — a drag of zero
                // length — still ends with a seek, which is what makes
                // tapping anywhere on the bar jump there.
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragFraction = fractionFor(x: value.location.x, width: width)
                    }
                    .onEnded { value in
                        let target = fractionFor(x: value.location.x, width: width) * progress.duration
                        dragFraction = nil
                        onSeek(target)
                    }
            )
            .onHover { isHovered = $0 }
        }
        .animation(.smooth(duration: 0.15), value: isHovered)
    }

    /// Inverse of `knobX`: the pointer is over the knob's *centre* line, which
    /// only travels the inset width, so the same inset is removed here. Both
    /// ends are therefore reachable — without this, the last knob-radius of
    /// the bar could never be selected.
    private func fractionFor(x: CGFloat, width: CGFloat) -> Double {
        let travel = max(width - Self.knobSize, 1)
        return min(max((x - Self.knobSize / 2) / travel, 0), 1)
    }

    // MARK: Labels

    /// Fixed width and monospaced digits so the bar's ends stay put as the
    /// clock runs — otherwise every digit change would nudge the whole bar.
    ///
    /// The width is taken from the track's *duration*, not from the text being
    /// drawn: it is therefore constant for the whole track (so nothing
    /// shifts), while still widening for the `h:mm:ss` a long podcast or DJ
    /// set needs. At a flat 36pt an hour-long track rendered as "1:02:…" and
    /// "-1:0…" — verified by rendering the view and reading the pixels.
    private func timeLabel(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundColor(.secondary)
            .lineLimit(1)
            .frame(width: labelWidth, alignment: alignment)
            .shadow(color: .black.opacity(0.5), radius: 3)
    }

    /// Wide enough for "-h:mm:ss" past the hour mark, "-mm:ss" below it.
    private var labelWidth: CGFloat { progress.duration >= 3600 ? 52 : 36 }

    /// `m:ss`, or `h:mm:ss` for anything past an hour (podcasts, DJ sets).
    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0).rounded(.down))
        let s = total % 60, m = (total / 60) % 60, h = total / 3600
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
