import SwiftUI

/// The collapsed strip + expanded panel layout, and the expand/collapse
/// animation. The panel window is always sized to the expanded (max)
/// dimensions (see NotchWindow.swift); this view draws top-aligned so the
/// collapsed strip sits flush with the notch and the rest of the window is
/// empty until expanded. Wired against the service stubs so feature agents
/// never need to touch this file.
struct ContentView: View {
    @ObservedObject var state: AppState
    @ObservedObject var music: MusicService
    @ObservedObject var api: SpotifyWebAPI

    private let notchWidth = NotchGeometry.notchWidth
    private let stripHeight = NotchGeometry.stripHeight
    private let sidePadding = NotchGeometry.sidePadding
    private let panelWidth = NotchGeometry.panelWidth
    private let panelHeight = NotchGeometry.panelHeight

    var body: some View {
        VStack(spacing: 0) {
            strip
            if state.isExpanded {
                expandedContent
            }
            Spacer(minLength: 0)
        }
        .frame(width: panelWidth, height: panelHeight, alignment: .top)
        .background(backgroundShape, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: state.isExpanded)
    }

    // Black rounded-bottom-corners shape that visually merges with the
    // physical notch. Only the bottom corners round; the top edge stays
    // square and flush against the notch/menu bar.
    private var backgroundShape: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: state.isExpanded ? 14 : 10,
            bottomTrailingRadius: state.isExpanded ? 14 : 10,
            topTrailingRadius: 0
        )
        .fill(Color.black)
        .frame(width: panelWidth, height: state.isExpanded ? panelHeight : stripHeight, alignment: .top)
    }

    // MARK: Collapsed strip

    private var strip: some View {
        HStack(spacing: 0) {
            artworkView
                .frame(width: sidePadding, height: stripHeight)
            Spacer()
                .frame(width: notchWidth)
            VisualizerView(isPlaying: state.nowPlaying?.isPlaying ?? false)
                .frame(width: sidePadding, height: stripHeight)
        }
        .frame(width: panelWidth, height: stripHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            state.isExpanded.toggle()
        }
    }

    private var artworkView: some View {
        Group {
            if let artwork = state.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.4))
            }
        }
        .frame(width: max(stripHeight - 8, 0), height: max(stripHeight - 8, 0))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(.leading, 8)
    }

    // MARK: Expanded content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.nowPlaying?.track ?? "Nothing playing")
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(state.nowPlaying?.artist ?? "")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            HStack(spacing: 28) {
                Button(action: { music.previousTrack() }) {
                    Image(systemName: "backward.fill")
                }
                Button(action: { music.playPause() }) {
                    Image(systemName: (state.nowPlaying?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                }
                Button(action: { music.nextTrack() }) {
                    Image(systemName: "forward.fill")
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
            .font(.system(size: 16, weight: .medium))

            PlaylistSection(api: api, state: state)
            AgentLightsView(sessions: state.sessions)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: panelWidth, height: max(panelHeight - stripHeight, 0), alignment: .topLeading)
    }
}
