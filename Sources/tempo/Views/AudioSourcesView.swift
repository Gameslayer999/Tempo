import SwiftUI

/// One row per app that is audibly playing, each with a pause button
/// (decision 099).
///
/// Shown only when there are **two or more** — one player is what the transport
/// row above already controls, and repeating it as a list would be a second
/// control for the same thing. Two is the moment the transport row stops being
/// enough, because it silently means "the app that started last" and the user
/// wants the other one.
///
/// Every row is a control that works: `AudioSourcesService` only publishes apps
/// it can actually pause, so there is nothing here to grey out or explain
/// (UI Principle #3 — a pause button pauses).
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
                // The now-playing app is the one the transport row above acts
                // on. Saying so here is what makes the *other* row's purpose
                // obvious at a glance.
                .foregroundStyle(source.isNowPlaying ? .primary : .secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Button {
                sources.pause(source)
            } label: {
                Image(systemName: "pause.fill")
                    .font(NotchType.control)
                    .frame(width: NotchMetrics.hitTarget, height: NotchMetrics.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .foregroundStyle(.secondary)
            .accessibilityLabel("Pause \(source.name)")
            .help("Pause \(source.name)")
        }
    }

    /// The app's own icon rather than a generic glyph: with two rows up, the
    /// icon is what identifies the row before the name is read (UI Principle
    /// #1). Falls back to a speaker when the app has no icon to give.
    @ViewBuilder
    private func appIcon(_ source: AudioSource) -> some View {
        if let icon = NSRunningApplication
            .runningApplications(withBundleIdentifier: source.bundleID)
            .first?.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: "speaker.wave.2.fill")
                .font(NotchType.caption)
                .frame(width: 14, height: 14)
                .foregroundStyle(.secondary)
        }
    }
}
