import AppKit
import SwiftUI

/// The collapsed strip + expanded panel layout, and the hover/pin
/// expand-collapse model. The panel window is always sized to the expanded
/// (max) dimensions (see NotchWindow.swift); this view draws top-aligned so
/// the collapsed strip sits flush with the notch and the rest of the window
/// is empty until expanded. Wired against the service stubs so feature
/// agents never need to touch this file.
///
/// Interaction model (revision of decision 009):
/// - Hover-in on the collapsed strip grows the panel to the full expanded
///   view immediately (with a haptic tick on the collapsed → hover-expand
///   transition), matching what a click used to show.
/// - Hover-out collapses back to the strip, unless a click pinned it open.
/// - A click anywhere on the expanded panel that isn't a control pins it:
///   `state.isExpanded` becomes true and it now survives mouse-out.
/// - A click outside the panel (handled in NotchWindow.swift's global
///   monitor) unpins and clears hover, collapsing it.
struct ContentView: View {
    @ObservedObject var state: AppState
    @ObservedObject var music: MusicService
    @ObservedObject var api: SpotifyWebAPI

    private let notchWidth = NotchGeometry.notchWidth
    private let stripHeight = NotchGeometry.stripHeight
    private let sidePadding = NotchGeometry.sidePadding
    private let panelWidth = NotchGeometry.panelWidth
    private let panelHeight = NotchGeometry.panelHeight

    // Cancellable delay on hover-out only. It absorbs the case where the
    // mouse travels from the strip down into the controls faster than the
    // expand spring grows the hit region under it — a brief, real gap that
    // would otherwise read as "left the panel" and collapse mid-motion. A
    // re-hover within the window cancels the pending collapse. Hover-in
    // itself is never delayed.
    @State private var hoverCollapseTask: Task<Void, Never>?

    // What the UI actually shows: pinned (click) or currently hovered.
    private var displayedExpanded: Bool { state.displayedExpanded }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                strip
                if displayedExpanded {
                    expandedContent
                }
            }
            .frame(width: panelWidth, height: displayedExpanded ? panelHeight : stripHeight, alignment: .top)
            .contentShape(Rectangle())
            .onHover(perform: handleHover)
            .onTapGesture {
                // A click anywhere on the expanded panel that isn't a
                // control pins it open. This gesture lives on the
                // foreground content container (not the `.background()`
                // glass layer) — SwiftUI's gesture hit-testing is driven by
                // the frontmost view's contentShape, so a gesture on a
                // `.background()` view sitting behind this content never
                // receives the tap even though the point is visually over
                // it (verified: the AppKit mouseDown reaches the window,
                // but no SwiftUI tap fires there). `.contentShape(Rectangle())`
                // above makes empty space, text, and artwork gaps tappable;
                // Buttons and the playlist Menu still claim their own taps
                // first, so controls are unaffected. Only pins once the
                // panel is actually displayed-expanded (hover already
                // happened), matching the pre-fix scope.
                guard displayedExpanded else { return }
                state.isExpanded = true
            }
            Spacer(minLength: 0)
        }
        .frame(width: panelWidth, height: panelHeight, alignment: .top)
        .background(backgroundShape, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: displayedExpanded)
    }

    /// Hover-in expands immediately and, only on the collapsed →
    /// hover-expand transition (never on repeat mouse moves within an
    /// already-hovered/pinned panel, never on hover-out), fires a trackpad
    /// haptic tick. Hover-out is debounced ~0.15s; see `hoverCollapseTask`.
    private func handleHover(_ hovering: Bool) {
        hoverCollapseTask?.cancel()
        hoverCollapseTask = nil

        if hovering {
            let wasFullyCollapsed = !state.isExpanded && !state.isHovered
            state.isHovered = true
            if wasFullyCollapsed {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        } else {
            hoverCollapseTask = Task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                state.isHovered = false
            }
        }
    }

    // Rounded-bottom-corners shape that visually merges with the physical
    // notch. Only the bottom corners round; the top edge stays square and
    // flush against the notch/menu bar. Collapsed: pure black, always (UI
    // Principle #6 — must keep merging with the notch, never glass).
    // Expanded (hover or pin): Liquid Glass body (macOS 26+) with a
    // black-to-glass blend at the top so the seam against the notch stays
    // black.
    private var backgroundShape: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: displayedExpanded ? 14 : 10,
            bottomTrailingRadius: displayedExpanded ? 14 : 10,
            topTrailingRadius: 0
        )
        return Group {
            if displayedExpanded {
                expandedBackground(shape: shape)
            } else {
                shape
                    .fill(Color.black)
                    .frame(width: panelWidth, height: stripHeight, alignment: .top)
            }
        }
    }

    @ViewBuilder
    private func expandedBackground(shape: UnevenRoundedRectangle) -> some View {
        ZStack(alignment: .top) {
            glassLayer(shape: shape)
            // Blend the top of the panel to black so it keeps merging with
            // the notch strip directly above it; the glass takes over below.
            LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: stripHeight + 20)
        }
        .frame(width: panelWidth, height: panelHeight, alignment: .top)
        .clipShape(shape)
    }

    @ViewBuilder
    private func glassLayer(shape: UnevenRoundedRectangle) -> some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
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
        .frame(width: panelWidth, height: stripHeight, alignment: .top)
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
            .shadow(color: .black.opacity(0.5), radius: 3)

            HStack(spacing: 28) {
                Button(action: { music.previousTrack() }) {
                    Image(systemName: "backward.fill")
                }
                .hoverScale()
                Button(action: { music.playPause() }) {
                    Image(systemName: (state.nowPlaying?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                }
                .hoverScale()
                Button(action: { music.nextTrack() }) {
                    Image(systemName: "forward.fill")
                }
                .hoverScale()
            }
            .buttonStyle(.plain)
            .foregroundColor(.white)
            .font(.system(size: 16, weight: .medium))
            .shadow(color: .black.opacity(0.5), radius: 3)

            PlaylistSection(api: api, state: state)
            AgentLightsView(sessions: state.sessions)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: panelWidth, height: max(panelHeight - stripHeight, 0), alignment: .topLeading)
    }
}
