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
    @ObservedObject var media: MediaRemoteService
    @ObservedObject var shelf: ShelfService
    @ObservedObject var audio: AudioOutputService
    @ObservedObject var api: SpotifyWebAPI
    @ObservedObject var prefs: Preferences
    /// Opens the Settings window (SettingsWindow.swift), owned by AppDelegate.
    let openSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Read live rather than captured: the notch dimensions change when a
    /// display is attached, detached, or the lid closes (decision 037), and a
    /// stored `let` would freeze this view at the launch-time screen's notch.
    /// `state.screenGeneration` is what re-evaluates this body afterwards.
    private var notchWidth: CGFloat { NotchGeometry.notchWidth }
    private var stripHeight: CGFloat { NotchGeometry.stripHeight }
    private var wingWidth: CGFloat { NotchGeometry.wingWidth }
    private var wingOuterInset: CGFloat { NotchGeometry.wingOuterInset }
    private var wingInnerInset: CGFloat { NotchGeometry.wingInnerInset }
    private var contentSquare: CGFloat { NotchGeometry.contentSquare }
    private var wingContentWidth: CGFloat { NotchGeometry.wingContentWidth }
    private var pillWidth: CGFloat { NotchGeometry.pillWidth }
    private var panelWidth: CGFloat { NotchGeometry.panelWidth }
    private var panelHeight: CGFloat { NotchGeometry.panelHeight }

    /// Grace before collapsing: debounced so a pointer travelling from the
    /// pill into the controls doesn't read as "left the panel".
    ///
    /// The matching expand dwell is a user setting, not a constant — see
    /// `hoverExpandDelay` below.
    private static let hoverCollapseDelay: UInt64 = 100_000_000

    /// Dwell before hover expands the panel, from Settings ▸ General ▸
    /// Interaction (decision 034, amends 011). It exists so a pointer merely
    /// crossing the notch on its way somewhere else cannot flicker the panel
    /// open; the pending expansion is cancelled by the matching hover-out.
    ///
    /// It is also what the haptic tick waits on, since the tick fires when the
    /// expansion actually triggers — which is why it is adjustable. At the
    /// original 250ms the tick usually fired into a trackpad the finger had
    /// already left. Against the measured pill (271 x 33pt: 185pt notch +
    /// 43pt wings), a pointer crossing *vertically* — the common accident,
    /// travelling up to the menu bar and past — is inside for only 13-40ms at
    /// any normal speed, so even a short dwell filters it; slow *horizontal*
    /// travel along the menu bar is inside for 180-340ms and was never
    /// filtered at any of these values.
    private var hoverExpandDelay: UInt64 {
        UInt64(max(prefs.hoverExpandDelayMS, 0) * 1_000_000)
    }

    @State private var hoverTask: Task<Void, Never>?

    /// Pairs the collapsed pill's artwork square with the expanded panel's
    /// larger artwork so the album cover travels between them instead of
    /// cross-fading. Exactly one of the two is in the hierarchy at a time.
    @Namespace private var artworkNamespace
    private static let artworkID = "artwork"
    /// Bounds for the expanded header's cover. Its actual side tracks the
    /// measured height of the column beside it (`headerColumnHeight`) so the
    /// two always line up — the column's height depends on font metrics and on
    /// which rows are showing, which is not something to hard-code. The upper
    /// bound keeps a transient row (the add-to-playlist error message) from
    /// ballooning the cover.
    /// Alpha painted under the expanded panel's glass so the window's backing
    /// store is not transparent there — see `backgroundShape`. Measured
    /// threshold: 0.0 lets clicks through, 0.02 already captures them; 0.05 is
    /// margin against rounding and is imperceptible over the glass.
    private static let glassSubstrateOpacity: Double = 0.05

    private static let expandedArtMin: CGFloat = 72
    private static let expandedArtMax: CGFloat = 116

    /// Measured natural height of `expandedContent` (its sections hide and
    /// show, so it isn't a constant). Drives the container's explicit —
    /// therefore spring-animatable — height, and the hit region's expanded
    /// target. The initial value only matters for the first frames of the
    /// very first expansion, before the first measurement lands.
    @State private var expandedContentHeight: CGFloat = 135

    /// Measured height of the title/transport/playlist column in the expanded
    /// header. Drives the cover's side so the cover matches it.
    @State private var headerColumnHeight: CGFloat = 104

    private var expandedArtSize: CGFloat {
        min(max(headerColumnHeight, Self.expandedArtMin), Self.expandedArtMax)
    }

    // What the UI actually shows: pinned (click) or currently hovered.
    private var displayedExpanded: Bool { state.displayedExpanded }

    /// Whether the media UI is in the hierarchy at all — cover, visualizer,
    /// transport controls and the playlist row (decision 038). False once
    /// nothing has played for `MediaRemoteService.mediaIdleTimeout`, which is what
    /// takes the collapsed pill back down to the bare notch.
    private var showsMedia: Bool { state.isMediaActive }

    /// The collapsed pill: notch plus both wings while there is media to put
    /// in them, otherwise exactly the notch — an empty pill is a black bar
    /// hanging past the hardware notch over a light desktop, which is the
    /// thing this state exists to remove.
    private var collapsedWidth: CGFloat {
        (showsMedia ? pillWidth : notchWidth) + lightSlotWidth * 2
    }

    /// Width of the agent dot(s) themselves (decision 042). Zero when there
    /// are no live sessions or the setting is off, which is what lets the pill
    /// keep its exact previous geometry in those cases.
    private var lightWidth: CGFloat {
        CollapsedAgentLight.width(sessions: state.sessions, mode: prefs.collapsedAgentLight)
    }

    /// The slot the light lives in, dots plus their gap from the pill's edge.
    /// With media showing, the visualizer wing's own `wingOuterInset` already
    /// provides the gap on the inboard side; without it, the slot supplies its
    /// own so the dot doesn't sit flush against the hardware notch.
    private var lightSlotWidth: CGFloat {
        guard lightWidth > 0 else { return 0 }
        return lightLeadingGap + lightWidth + wingOuterInset
    }

    private var lightLeadingGap: CGFloat { showsMedia ? 0 : wingInnerInset }

    private var currentWidth: CGFloat { displayedExpanded ? panelWidth : collapsedWidth }
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
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard prefs.showFileShelf else { return false }
            receiveDrop(providers)
            return true
        }
        // The only hit-testable region is the drawn silhouette: this is
        // congruent with the shape filled by `backgroundShape`, and nothing
        // else in the hierarchy spans the window (the outer `.frame` below
        // only positions — a frame claims no clicks of its own).
        .contentShape(shape)
        .onHover(perform: handleHover)
        .onTapGesture {
            // Backstop for the pin-on-click behaviour; the primary path is
            // `NotchPanel.sendEvent`, which also catches clicks that a Button
            // or Menu swallows before any gesture sees them. Kept because it is
            // the path that was verified working for plain (non-control)
            // clicks.
            //
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
        // Cover resizes with the column rather than snapping when a row
        // appears or disappears beside it.
        .animation(expandAnimation, value: headerColumnHeight)
        // The media UI going away (or coming back) retracts/grows the pill's
        // wings with the same spring instead of snapping a chunk of pill out
        // of existence.
        .animation(expandAnimation, value: showsMedia)
        // Same for the agent light slot: a session starting or ending changes
        // the collapsed width, and that has to spring like everything else
        // rather than snapping the pill wider mid-glance.
        .animation(expandAnimation, value: lightSlotWidth)
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
                    // Hit-testable substrate. macOS routes clicks on a
                    // non-opaque window by the alpha in its backing store, and
                    // Liquid Glass is a compositor effect over `Color.clear` —
                    // it paints (almost) no alpha of its own, so bare glass let
                    // clicks fall straight through to the app behind while the
                    // artwork, graphs, text and the black top gradient (all
                    // real pixels) caught them normally.
                    shape.fill(Color.black.opacity(Self.glassSubstrateOpacity))
                    glassLayer
                    // Clear glass passes the backdrop through almost intact,
                    // so white text over a bright window is unreadable
                    // without a scrim (Apple's own guidance for `.clear`).
                    // The other styles already carry enough of their own
                    // density and get none.
                    if prefs.panelStyle == .clear {
                        Color.black.opacity(0.22)
                    }
                    // Blend the top of the panel to black so it keeps merging
                    // with the notch pill directly above it; the glass takes
                    // over below.
                    LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: stripHeight + 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipShape(shape)
                .overlay(borderLayer)
            }
        }
    }

    /// Rim light around the expanded panel. Two strokes: a crisp 1.2pt edge
    /// whose brightness varies down the panel (bright shoulders, dimmer
    /// waist, bright base — how a real glass edge catches light), and a wider
    /// blurred stroke under it that reads as the thickness of the material
    /// rather than a drawn outline.
    ///
    /// Applied as an overlay *after* `clipShape`, so the stroke is not halved
    /// by the clip. Masked to nothing across the top blend region: the panel's
    /// first `stripHeight` points must stay pure black to merge with the notch
    /// (UI Principle #6), and an outlined seam there would read as a floating
    /// box hanging off the notch.
    private var borderLayer: some View {
        ZStack {
            shape.stroke(
                LinearGradient(
                    colors: [.white.opacity(0.55), .white.opacity(0.16), .white.opacity(0.38)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1.2
            )
            shape.stroke(Color.white.opacity(0.14), lineWidth: 3)
                .blur(radius: 2.5)
        }
        .mask {
            VStack(spacing: 0) {
                Color.clear.frame(height: stripHeight)
                LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
                    .frame(height: 24)
                Color.white
            }
        }
        .allowsHitTesting(false)
    }

    /// The panel's material, per `prefs.panelStyle` (decision 030).
    ///
    /// Below macOS 26 there is no `glassEffect` at all, so the three glass
    /// styles degrade to the nearest `Material` — the picker keeps working and
    /// still visibly changes the panel, it just isn't Liquid Glass. `.solid`
    /// is identical on every version.
    @ViewBuilder
    private var glassLayer: some View {
        if prefs.panelStyle == .solid {
            shape.fill(Color.black.opacity(0.93))
        } else if #available(macOS 26.0, *) {
            Color.clear.glassEffect(glass, in: shape)
        } else {
            shape.fill(prefs.panelStyle == .clear ? .ultraThinMaterial : .regularMaterial)
        }
    }

    /// `.tint(nil)` is defined as "no tint", so a track with no artwork (or a
    /// cover we couldn't sample) falls back to plain regular glass instead of
    /// needing a separate branch.
    @available(macOS 26.0, *)
    private var glass: Glass {
        switch prefs.panelStyle {
        case .clear: return .clear
        case .tinted: return .regular.tint(state.artworkTint.map { Color(nsColor: $0).opacity(0.55) })
        case .regular, .solid: return .regular
        }
    }

    /// Hover-in arms a cancellable expansion; only when it actually fires (and
    /// only on a true collapsed → expanded transition) does the trackpad tick.
    /// Hover-out arms a cancellable collapse. Either edge cancels whatever the
    /// other one had pending.
    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()
        hoverTask = Task {
            try? await Task.sleep(nanoseconds: hovering ? hoverExpandDelay : Self.hoverCollapseDelay)
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
    /// the physical notch untouched between them. Both squares are inset from
    /// the pill's outer edges by `wingOuterInset`, which clears the concave
    /// top corner and the rounded bottom corner of `NotchShape` — flush
    /// content pokes outside the black fill there.
    ///
    /// While expanded the artwork is not here: it has moved into the panel
    /// header (`nowPlayingHeader`). Its slot keeps its width either way, so
    /// the visualizer and the notch gap never shift.
    ///
    /// Both wings leave entirely once the media UI is idle (decision 038);
    /// what is left is the notch-width gap, so the pill is exactly the
    /// hardware notch.
    ///
    /// Outboard of the visualizer sits the agent light (decision 042), in a
    /// slot mirrored by an empty one on the leading side so the notch gap
    /// stays centred on the hardware notch. It is deliberately *not* tied to
    /// `showsMedia`: agent state is the one signal worth widening an otherwise
    /// bare notch for.
    private var strip: some View {
        HStack(spacing: 0) {
            // Empty mirror of the light slot. The strip is centred in the
            // window, so a slot added on one side alone would walk the notch
            // gap off the hardware notch by half its width (UI Principle #6).
            if lightSlotWidth > 0 {
                Color.clear.frame(width: lightSlotWidth, height: stripHeight)
            }
            if showsMedia {
                Color.clear
                    .frame(width: wingContentWidth, height: contentSquare)
                    .overlay {
                        if !displayedExpanded {
                            artworkView(side: contentSquare, cornerRadius: 4)
                                .matchedGeometryEffect(id: Self.artworkID, in: artworkNamespace)
                        }
                    }
                    .padding(.leading, wingOuterInset)
                    .padding(.trailing, wingInnerInset)
                    .frame(height: stripHeight)
            }
            Spacer()
                .frame(width: notchWidth)
            if showsMedia {
                Color.clear
                    .frame(width: wingContentWidth, height: contentSquare)
                    .overlay {
                        if prefs.showVisualizer {
                            VisualizerView(isPlaying: state.nowPlaying?.isPlaying ?? false)
                        }
                    }
                    .padding(.leading, wingInnerInset)
                    .padding(.trailing, wingOuterInset)
                    .frame(height: stripHeight)
            }
            if lightSlotWidth > 0 {
                CollapsedAgentLight(sessions: state.sessions, mode: prefs.collapsedAgentLight)
                    .frame(width: lightWidth, height: contentSquare)
                    .padding(.leading, lightLeadingGap)
                    .padding(.trailing, wingOuterInset)
                    .frame(height: stripHeight)
            }
        }
        .frame(width: collapsedWidth, height: stripHeight, alignment: .top)
    }

    private func artworkView(side: CGFloat, cornerRadius: CGFloat) -> some View {
        Group {
            if let artwork = state.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.gray.opacity(0.4))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    // MARK: Expanded content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsMedia {
                nowPlayingHeader
                // Full content width, below the cover+controls block rather
                // than inside the column beside the cover: the extra ~120pt
                // is what makes the bar precise enough to scrub with
                // (~1.7pt per second on a typical track instead of ~1.1).
                if let progress = state.progress, progress.duration > 0 {
                    PlaybackProgressView(progress: progress) { media.seek(to: $0) }
                }
            }
            if prefs.showAudioOutput {
                AudioOutputView(audio: audio)
            }
            if prefs.showFileShelf {
                ShelfView(shelf: shelf, isDropTargeting: state.isDragTargeting)
            }
            if prefs.showUsageGraph {
                UsageGraphView()
            }
            if prefs.showAgentLights {
                AgentLightsView(
                    sessions: state.sessions,
                    // Empty when the figures are switched off — the service is
                    // stopped in that case anyway, and an empty map is exactly
                    // "this row has no figures" (decision 048).
                    stats: prefs.showAgentStats ? state.sessionStats : [:],
                    onFocus: focusSession
                )
            }
        }
        // Top-right corner of the panel content. An overlay rather than a
        // member of the header row: in the row it would consume width on one
        // side only, pulling the centred title off the play button.
        .overlay(alignment: .topTrailing) {
            settingsButton
                // Cancel the button style's own padding so the glyph sits on
                // the content inset rather than 8pt inside it.
                .padding(.trailing, -8)
                .padding(.top, -4)
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

    /// Album art on the left; to its right, the title and artist centred over
    /// a transport row spread across the remaining width — so the play/pause
    /// button sits directly under the title, and cover + controls together
    /// occupy the full content width. The artwork is the same square that was
    /// in the collapsed pill's left wing, travelling here via
    /// `matchedGeometryEffect`.
    private var nowPlayingHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            artworkView(side: expandedArtSize, cornerRadius: 12)
                .matchedGeometryEffect(id: Self.artworkID, in: artworkNamespace)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 1)

            VStack(spacing: 6) {
                VStack(spacing: 2) {
                    Text(state.nowPlaying?.track ?? "Nothing playing")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(state.nowPlaying?.artist ?? "")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                // Symmetric, so the title stays centred on the play button
                // while still keeping clear of the gear in the corner.
                .padding(.horizontal, 24)
                .shadow(color: .black.opacity(0.5), radius: 3)

                // Evenly spread: with equal spacers the middle button lands on
                // the column's centre line, directly below the title.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Button(action: { media.previousTrack() }) {
                        Image(systemName: "backward.fill")
                    }
                    Spacer(minLength: 0)
                    Button(action: { media.playPause() }) {
                        Image(systemName: (state.nowPlaying?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                    }
                    Spacer(minLength: 0)
                    Button(action: { media.nextTrack() }) {
                        Image(systemName: "forward.fill")
                    }
                    Spacer(minLength: 0)
                }
                .buttonStyle(NotchButtonStyle())
                .foregroundColor(.primary)
                .font(.system(size: 17, weight: .medium))
                .shadow(color: .black.opacity(0.5), radius: 3)
                .frame(maxWidth: .infinity)

                PlaylistSection(api: api, state: state, prefs: prefs)
            }
            // The column sets the header's height; the cover matches it.
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { reportHeaderColumnHeight(geo.size.height) }
                        .onChange(of: geo.size.height) { _, newHeight in
                            reportHeaderColumnHeight(newHeight)
                        }
                }
            )
        }
    }

    /// A click on an agent light goes to that session's window (decision 035)
    /// and collapses the panel on the way, so the newly-fronted window isn't
    /// left under a pinned panel. The collapse is explicit for the same reason
    /// the gear's is: any click on the panel pins it
    /// (`NotchPanel.sendEvent`), and the outside-click monitor never sees the
    /// clicks Tempo's own panel receives.
    private func focusSession(_ session: AgentSession) {
        // Going to a finished session *is* reviewing it, so the same click
        // clears its unread light (decision 044).
        state.acknowledgeFinish(session)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            state.isExpanded = false
            state.isHovered = false
        }
        SessionFocusService.focus(session)
    }

    private func reportHeaderColumnHeight(_ height: CGFloat) {
        guard height > 0, height != headerColumnHeight else { return }
        headerColumnHeight = height
    }

    /// Opens the Settings window and collapses the panel on the way out. The
    /// collapse is explicit because the panel would otherwise stay pinned:
    /// NotchPanel's outside-click monitor is a *global* monitor, and a click
    /// in Tempo's own Settings window is not global.
    private var settingsButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                state.isExpanded = false
                state.isHovered = false
            }
            openSettings()
        }) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(NotchButtonStyle())
        .foregroundColor(.secondary)
        .shadow(color: .black.opacity(0.5), radius: 3)
        .help("Tempo Settings")
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

extension ContentView {
    /// Resolves dropped providers to file URLs and hands them to the shelf.
    ///
    /// `loadItem` is asynchronous and answers on an arbitrary queue, so the
    /// URLs are collected first and added in one main-actor batch — adding
    /// them one at a time would publish `items` once per file and animate the
    /// row N times for a single drop.
    fileprivate func receiveDrop(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            MainActor.assumeIsolated {
                guard !urls.isEmpty else { return }
                shelf.add(urls: urls)
            }
        }
    }
}
