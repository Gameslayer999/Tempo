import SwiftUI

/// One row per app that is a live audio source, each with a play/pause button
/// (decisions 099 and 104).
///
/// Shown only when there are **two or more** — one player is what the transport
/// row above already controls, and repeating it as a list would be a second
/// control for the same thing. Two is the moment the transport row stops being
/// enough, because it silently means "the app that started last" and the user
/// wants the other one.
///
/// A row stays put once its app has been heard, playing or not, so pausing one
/// leaves a resume button where the pause button was instead of collapsing the
/// list out from under the cursor. The glyph and the emphasis carry the state
/// instead (decision 104).
///
/// Every row is a control that works: `AudioSourcesService` only publishes apps
/// it can actually reach, so there is nothing here to grey out or explain
/// (UI Principle #3 — a pause button pauses, a play button plays).
struct AudioSourcesView: View {
    @ObservedObject var sources: AudioSourcesService

    var body: some View {
        if sources.sources.count > 1 {
            VStack(alignment: .leading, spacing: NotchMetrics.rowSpacing) {
                ForEach(sources.sources) { source in
                    row(source)
                }
            }
        }
    }

    private func row(_ source: AudioSource) -> some View {
        HStack(spacing: 8) {
            appIcon(source)
            Text(source.name)
                .font(NotchType.caption)
                // Emphasis follows *audible*, not now-playing: with paused rows
                // on screen, which apps are making sound is the question the
                // list answers at a glance (UI Principle #1).
                .foregroundStyle(source.isPlaying ? .primary : .secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Button {
                sources.toggle(source)
            } label: {
                Image(systemName: source.isPlaying ? "pause.fill" : "play.fill")
                    .font(NotchType.control)
                    .frame(width: NotchMetrics.hitTarget, height: NotchMetrics.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(source.isPlaying ? "Pause" : "Play") \(source.name)")
            .help("\(source.isPlaying ? "Pause" : "Play") \(source.name)")
        }
    }

    /// The app's own icon rather than a generic glyph: with two rows up, the
    /// icon is what identifies the row before the name is read (UI Principle
    /// #1). Dimmed when the app is silent, so the playing rows read first.
    /// Falls back to a speaker when the app has no icon to give.
    @ViewBuilder
    private func appIcon(_ source: AudioSource) -> some View {
        if let icon = NSRunningApplication
            .runningApplications(withBundleIdentifier: source.bundleID)
            .first?.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 14, height: 14)
                .opacity(source.isPlaying ? 1 : 0.55)
        } else {
            Image(systemName: "speaker.wave.2.fill")
                .font(NotchType.caption)
                .frame(width: 14, height: 14)
                .foregroundStyle(.secondary)
        }
    }
}
