import AppKit
import SwiftUI

/// The silhouette of both the collapsed pill and the expanded panel.
///
/// Geometry: the top corners are *concave* — from the very top edge the
/// outline sweeps inward and down, so the shape flares out where it meets the
/// menu-bar edge and tucks under it instead of ending in a hard corner. The
/// bottom corners are ordinary convex rounds. Both radii animate, so the
/// silhouette morphs continuously between the pill and the panel.
///
/// The straight vertical sides therefore sit `topCornerRadius` inside the
/// rect; only the top `topCornerRadius` points of the shape are full width.
struct NotchShape: Shape {
    static let collapsedTopRadius: CGFloat = 6
    static let collapsedBottomRadius: CGFloat = 14
    static let expandedTopRadius: CGFloat = 19
    static let expandedBottomRadius: CGFloat = 24

    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    /// Set on exactly one always-present instance, which reports the live
    /// animated rect to `NotchHitRegion` for the panel's hit testing.
    var report: (@Sendable (CGSize) -> Void)?

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        report?(rect.size)

        let top = max(0, min(topCornerRadius, rect.width / 2, rect.height))
        let bottom = max(0, min(bottomCornerRadius, (rect.width - top * 2) / 2, rect.height - top))

        var path = Path()
        // Top-left: out at the top edge, curving inward and down.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// The collapsed pill + expanded panel layout, and the hover/pin
/// expand-collapse model. The panel window is always sized to the expanded
/// (max) dimensions (see NotchWindow.swift); this view draws top-aligned and
/// horizontally centred, so the collapsed pill sits flush with the notch and
/// the rest of the window is empty and click-through until expanded.
///
/// Interaction model (revision of decision 009/011):
/// - Hover on the collapsed pill expands it to the full view after a short
///   dwell, so a pointer merely crossing the notch never flickers it open. A
///   haptic tick fires when the expansion actually triggers.
/// - Hover-out collapses back to the pill, unless a click pinned it open.
/// - A click anywhere on the expanded panel that isn't a control pins it:
///   `state.isExpanded` becomes true and it now survives mouse-out.
/// - A click outside the panel (handled in NotchWindow.swift's global
///   monitor) unpins and clears hover, collapsing it.
struct ContentView: View {
    @ObservedObject var state: AppState
    @ObservedObject var music: MusicService
    @ObservedObject var api: SpotifyWebAPI

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let notchWidth = NotchGeometry.notchWidth
    private let stripHeight = NotchGeometry.stripHeight
    private let wingWidth = NotchGeometry.wingWidth
    private let contentSquare = NotchGeometry.contentSquare
    private let pillWidth = NotchGeometry.pillWidth
    private let panelWidth = NotchGeometry.panelWidth
    private let panelHeight = NotchGeometry.panelHeight

    /// Dwell before expanding, and grace before collapsing. Hover-in is
    /// delayed so a pointer crossing the notch on its way somewhere else
    /// cannot flicker the panel open; the pending expansion is cancelled by
    /// the matching hover-out. Hover-out is debounced so a pointer travelling
    /// from the pill into the controls doesn't read as "left the panel".
    private static let hoverExpandDelay: UInt64 = 250_000_000
    private static let hoverCollapseDelay: UInt64 = 100_000_000

    @State private var hoverTask: Task<Void, Never>?

    /// Measured natural height of `expandedContent` (its sections hide and
    /// show, so it isn't a constant). Drives the container's explicit —
    /// therefore spring-animatable — height, and the hit region's expanded
    /// target. The initial value only matters for the first frames of the
    /// very first expansion, before the first measurement lands.
    @State private var expandedContentHeight: CGFloat = 157

    // What the UI actually shows: pinned (click) or currently hovered.
    private var displayedExpanded: Bool { state.displayedExpanded }

    private var currentWidth: CGFloat { displayedExpanded ? panelWidth : pillWidth }
    private var currentHeight: CGFloat {
        displayedExpanded ? min(expandedContentHeight + stripHeight, panelHeight) : stripHeight
    }

    private var shape: NotchShape {
        NotchShape(
            topCornerRadius: displayedExpanded ? NotchShape.expandedTopRadius : NotchShape.collapsedTopRadius,
            bottomCornerRadius: displayedExpanded ? NotchShape.expandedBottomRadius : NotchShape.collapsedBottomRadius
        )
    }

    /// Opening overshoots very slightly; closing is critically damped so the
    /// panel never bounces on its way back into the notch. Reduce Motion
    /// replaces both with a short linear-ish fade (HIG): no spring, no bounce.
    private var expandAnimation: Animation {
        if reduceMotion { return .easeInOut(duration: 0.15) }
        return displayedExpanded
            ? .spring(response: 0.42, dampingFraction: 0.8)
            : .spring(response: 0.45, dampingFraction: 1.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            strip
            if displayedExpanded {
                expandedContent
                    .transition(.opacity)
            }
        }
        .frame(width: currentWidth, height: currentHeight, alignment: .top)
        .background(backgroundShape)
        // The only hit-testable region is the drawn silhouette: this is
        // congruent with the shape filled by `backgroundShape`, and nothing
        // else in the hierarchy spans the window (the outer `.frame` below
        // only positions — a frame claims no clicks of its own).
        .contentShape(shape)
        .onHover(perform: handleHover)
        .onTapGesture {
            // A click anywhere on the expanded panel that isn't a control
            // pins it open. This gesture lives on the foreground content
            // container (not the `.background()` layers) — SwiftUI's gesture
            // hit-testing is driven by the frontmost view's contentShape, so
            // a gesture on a `.background()` view sitting behind this content
            // never receives the tap even though the point is visually over
            // it (verified: the AppKit mouseDown reaches the window, but no
            // SwiftUI tap fires there). Buttons and the playlist Menu still
            // claim their own taps first, so controls are unaffected. Only
            // pins once the panel is actually displayed-expanded (hover
            // already happened), matching the pre-fix scope.
            guard displayedExpanded else { return }
            state.isExpanded = true
        }
        .frame(width: panelWidth, height: panelHeight, alignment: .top)
        .animation(expandAnimation, value: displayedExpanded)
        // A section appearing/disappearing while the panel is open (playlist
        // connects, an agent session starts) re-measures the content and must
        // retarget the height with the same spring, not snap.
        .animation(expandAnimation, value: expandedContentHeight)
    }

    /// Collapsed: pure black, always (UI Principle #6 — must keep merging with
    /// the notch, never glass). Expanded (hover or pin): Liquid Glass body
    /// (macOS 26+) with a black-to-glass blend at the top so the seam against
    /// the notch stays black.
    ///
    /// The black silhouette layer is *always* in the hierarchy — never inside
    /// an `if` branch — for two reasons. It is the layer that reports the live
    /// animated rect to `NotchHitRegion` (see NotchWindow.swift), and a view
    /// introduced by a branch flip does not join an animation already in
    /// flight: verified that such a view is evaluated exactly once, at its
    /// final size. Inside a branch it would both report nothing while the
    /// panel is collapsing — exactly when the hit region must track the
    /// animation — and snap to the collapsed pill instead of retracting. It
    /// fades to transparent while expanded so the glass is never backed by
    /// opaque black.
    private var backgroundShape: some View {
        var silhouette = shape
        silhouette.report = { NotchHitRegion.shared.size = $0 }
        return ZStack(alignment: .top) {
            silhouette
                .fill(Color.black)
                .opacity(displayedExpanded ? 0 : 1)
            if displayedExpanded {
                ZStack(alignment: .top) {
                    glassLayer
                    // Blend the top of the panel to black so it keeps merging
                    // with the notch pill directly above it; the glass takes
                    // over below.
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: stripHeight + 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipShape(shape)
            }
        }
    }

    @ViewBuilder
    private var glassLayer: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }

    /// Hover-in arms a cancellable expansion; only when it actually fires (and
    /// only on a true collapsed → expanded transition) does the trackpad tick.
    /// Hover-out arms a cancellable collapse. Either edge cancels whatever the
    /// other one had pending.
    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()
        hoverTask = Task {
            try? await Task.sleep(nanoseconds: hovering ? Self.hoverExpandDelay : Self.hoverCollapseDelay)
            guard !Task.isCancelled else { return }
            if hovering {
                let wasFullyCollapsed = !state.isExpanded && !state.isHovered
                state.isHovered = true
                if wasFullyCollapsed {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            } else {
                state.isHovered = false
            }
        }
    }

    // MARK: Collapsed pill

    /// Artwork square in the left wing, visualizer square in the right wing,
    /// the physical notch untouched between them.
    private var strip: some View {
        HStack(spacing: 0) {
            artworkView
                .frame(width: wingWidth, height: stripHeight)
            Spacer()
                .frame(width: notchWidth)
            VisualizerView(isPlaying: state.nowPlaying?.isPlaying ?? false)
                .frame(width: contentSquare, height: contentSquare)
                .frame(width: wingWidth, height: stripHeight)
        }
        .frame(width: pillWidth, height: stripHeight, alignment: .top)
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
        .frame(width: contentSquare, height: contentSquare)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: Expanded content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.nowPlaying?.track ?? "Nothing playing")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(state.nowPlaying?.artist ?? "")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .shadow(color: .black.opacity(0.5), radius: 3)

            HStack(spacing: 12) {
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
            .buttonStyle(NotchButtonStyle())
            .foregroundColor(.primary)
            .font(.system(size: 16, weight: .medium))
            .shadow(color: .black.opacity(0.5), radius: 3)

            PlaylistSection(api: api, state: state)
            UsageGraphView()
            AgentLightsView(sessions: state.sessions)
        }
        // Horizontal inset clears the shape's straight sides, which sit
        // `expandedTopRadius` inside the panel rect.
        .padding(.horizontal, NotchShape.expandedTopRadius + 7)
        .padding(.vertical, 16)
        .frame(width: panelWidth, alignment: .topLeading)
        // Content-sized panel: measure the natural height and report it. A
        // branch-inserted view lays out at its final size on the first frame
        // (verified for this codebase — see backgroundShape's comment), so
        // both reports land at expansion start, before the spring arrives.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { reportExpandedHeight(geo.size.height) }
                    .onChange(of: geo.size.height) { _, newHeight in
                        reportExpandedHeight(newHeight)
                    }
            }
        )
    }

    /// Feeds the measured expanded-content height to the animatable container
    /// height and to the hit region's expanded target rect (NotchWindow.swift).
    private func reportExpandedHeight(_ contentHeight: CGFloat) {
        guard contentHeight > 0, contentHeight != expandedContentHeight else { return }
        expandedContentHeight = contentHeight
        NotchHitRegion.shared.expandedTarget = CGSize(
            width: panelWidth,
            height: min(contentHeight + stripHeight, panelHeight)
        )
    }
}
