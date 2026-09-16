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
    /// Read by the onboarding setup rows for their live grant state; the
    /// notch itself shows neither.
    @ObservedObject var lockCards: LockScreenNotifier
    @ObservedObject var location: LocationService
    /// The audio tap, for the visualizer-only strip below. Defaulted so the
    /// call site in AppDelegate stays a plain memberwise init.
    @ObservedObject var tap = AudioTapService.shared
    @ObservedObject var usage = UsageHistoryService.shared
    /// Opens the Settings window (SettingsWindow.swift), owned by AppDelegate.
    let openSettings: () -> Void
    /// The first-run hello and setup sequence (decision 057). Owned by
    /// AppDelegate; the panel is only its stage.
    @ObservedObject var onboarding: OnboardingController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Liquid Glass is a transparency effect, and a user who has asked the
    /// system for less of it must get less of it — the panel falls back to an
    /// opaque fill (HIG ▸ Materials). Without this the setting did nothing
    /// here at all.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// `.increased` when the user has turned on Increase Contrast. Deepens
    /// the scrim under the content and hardens the rim light, so text over a
    /// bright desktop clears 4.5:1 instead of relying on the glass alone.
    @Environment(\.colorSchemeContrast) private var contrast

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

    /// The same dwell for the undrawn strip's edge push, which is its own
    /// setting (decision 093): holding a pointer against a screen edge is a
    /// deliberate gesture and wants a separately tuned hold from brushing a
    /// drawn pill.
    private var edgeHoldDelay: UInt64 {
        UInt64(max(prefs.edgeHoldDelayMS, 0) * 1_000_000)
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
    /// The track the sneak peek is currently showing, and the timer that
    /// retracts it (decision 072). Held here rather than in `AppState` because
    /// nothing outside this view needs it.
    @State private var sneakPeekTrack: NowPlaying?
    @State private var sneakPeekTask: Task<Void, Never>?

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

    /// Real audio is coming out of the machine with no now-playing card to
    /// show for it — a YouTube tab, a game, a call (decision 056). The strip
    /// earns a visualizer wing anyway: something *is* playing, and a dead
    /// notch over live audio reads as broken. No artwork, because there is
    /// none to show; the leading wing becomes an empty mirror so the notch gap
    /// stays centred (UI Principle #6).
    private var showsAudioOnly: Bool { !showsMedia && prefs.showVisualizer && tap.audioActive }

    /// Either reason the pill wears its wings.
    private var showsWings: Bool { showsMedia || showsAudioOnly }

    /// The collapsed pill: notch plus both wings while there is media to put
    /// in them, otherwise exactly the notch — an empty pill is a black bar
    /// hanging past the hardware notch over a light desktop, which is the
    /// thing this state exists to remove.
    private var collapsedWidth: CGFloat {
        (showsWings ? pillWidth : notchWidth) + lightSlotWidth * 2
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

    private var lightLeadingGap: CGFloat { showsWings ? 0 : wingInnerInset }

    /// True when the collapsed pill must not be drawn at all: the setting is
    /// off and there is no hardware notch to hug (decision 055). The panel
    /// still opens on hover — `NotchHoverDetector` watches the pointer, since
    /// an undrawn pill claims no clicks and so gets no `onHover` of its own.
    ///
    /// Recomputed on every body evaluation, and `state.screenGeneration`
    /// (bumped by `applyGeometry`) is what forces one after a display change.
    private var stripHidden: Bool {
        !prefs.showStripOnExternalDisplays && !NotchGeometry.isHardwareNotch
    }

    /// Alpha of the whole panel, so the hidden strip fades in as it expands
    /// rather than appearing at full strength a frame before it grows. Not a
    /// branch in the hierarchy: the black silhouette is what reports the live
    /// animated geometry to `NotchHitRegion`, and a view introduced by a
    /// branch flip does not join an animation already in flight (see
    /// `backgroundShape`). Animated by `fadeAnimation`, not the collapse
    /// spring — see where it is applied in `body`.
    private var panelOpacity: Double { (stripHidden && !displayedExpanded) ? 0 : 1 }

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

    /// Curve for `panelOpacity` alone — the panel appearing and disappearing
    /// where there is no collapsed strip to fall back to (decision 055).
    /// A short ease rather than the collapse spring, so the alpha is at zero
    /// while the geometry is still settling instead of trailing behind it.
    private var fadeAnimation: Animation { .easeOut(duration: reduceMotion ? 0.15 : 0.18) }

    var body: some View {
        VStack(spacing: 0) {
            strip
            if displayedExpanded {
                // Onboarding takes the expanded view's slot rather than
                // sitting beside it: the first run is not a panel with an
                // extra section, it is a different thing in the same drawer
                // (decision 057).
                Group {
                    if onboarding.isActive {
                        onboardingContent
                    } else {
                        expandedContent
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(width: currentWidth, height: currentHeight, alignment: .top)
        .background(backgroundShape)
        // The retracting outline is the only place the panel may draw. A
        // SwiftUI subtree removed inside an animated transaction keeps the
        // size it held and fades in place rather than following the frame
        // inward, and both of the panel's `if displayedExpanded` branches are
        // exactly that: on collapse the expanded column — output chips, gear,
        // CPU and memory readouts — and the glass behind it both stayed at
        // full panel width, fading over the desktop while the pill had already
        // retracted into the notch (decision 082). Clipped here they are wiped
        // by the shape as it closes.
        //
        // After `.background`, so the glass is clipped too and not only the
        // content. The rim light is the one thing that must *not* be inside
        // this clip — a stroke on the boundary would be halved by it — so it
        // moved out of `backgroundShape` to the overlay below.
        .clipShape(shape)
        // Outside the clip, and always present rather than in a branch: a
        // branch would freeze the stroke at full panel size on collapse and
        // draw the very outline this clip exists to remove.
        .overlay(borderLayer.opacity(displayedExpanded ? 1 : 0))
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
        .onHover { hovering in
            // Ignored in exactly one mode, and this is the whole fix for the
            // panel opening at a full-screen browser's tab strip (decision
            // 092). Decision 055 assumed this callback could not fire when the
            // strip is undrawn, because `NotchHostingView.hitTest` returns nil
            // there. It fires anyway: `.onHover` is driven by an
            // `NSTrackingArea`, and tracking areas deliver mouseEntered /
            // mouseExited whether or not hit-testing accepts the point. So
            // both entry paths were live, and this one — the collapsed pill's
            // whole ~308x32pt rect, with no edge band and no menu-bar gate —
            // was the one actually opening the panel. In this mode
            // `NotchHoverDetector` owns hover entirely, opening *and* closing.
            guard !stripHidden else { return }
            handleHover(hovering)
        }
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
        .onChange(of: state.nowPlaying?.track) { _, track in
            showSneakPeek(for: track)
        }
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
        // Same for audio starting or stopping with no now-playing card behind
        // it, which grows and retracts the same wings (decision 056).
        .animation(expandAnimation, value: showsAudioOnly)
        // Same for the agent light slot: a session starting or ending changes
        // the collapsed width, and that has to spring like everything else
        // rather than snapping the pill wider mid-glance.
        .animation(expandAnimation, value: lightSlotWidth)
        // hello -> setup cards is a real height change, and it has to spring
        // like every other section change rather than snapping.
        .animation(expandAnimation, value: onboarding.phase)
        // Deliberately outside every `expandAnimation` above: the panel's own
        // alpha must not inherit the collapse spring. On that curve the
        // critically damped tail left a dim ghost of the panel sitting over
        // the menu bar for roughly half a second after it had finished
        // retracting (decision 065). Placed here, the modifiers above are the
        // closer animation for the frame and shape, so only the alpha takes
        // `fadeAnimation`.
        .opacity(panelOpacity)
        .animation(fadeAnimation, value: panelOpacity)
        // Deliberately *outside* `panelOpacity`, and this is load-bearing.
        // Inside it, the peek inherited the hidden strip's alpha of 0: in
        // clamshell on a notchless display with "Show the strip on external
        // displays" off, `stripHidden` is true whenever the panel is
        // collapsed, so the peek was rendered at zero alpha every time it
        // fired and the feature was invisible in exactly the configuration
        // that most needs it. The peek is a transient signal in its own
        // right — hiding the persistent strip is a statement about chrome
        // over the menu bar, not a request to be told nothing.
        //
        // Below the pill, in the transparent part of the window. It claims no
        // clicks: the window's hit region is the drawn silhouette only, so the
        // peek is pixels over whatever app is behind and nothing more.
        .overlay(alignment: .top) { sneakPeekView }
        // The pointer reaching the place the strip would be, when the strip is
        // not drawn (decision 055). Runs through the same dwell and haptic as
        // a real hover, so the two entry paths cannot feel different — and the
        // detector is only ever running in that one mode, so this is inert
        // everywhere else.
        .onChange(of: state.isPointerNearNotch) { _, near in
            handleHover(near, expandDelay: edgeHoldDelay)
        }
    }

    /// Alpha of the black silhouette. `stripHidden` too, not just
    /// `displayedExpanded`: black is only ever right because it merges with
    /// the notch. On a notchless display with the strip switched off there is
    /// no notch to merge with, and fading it in over the retracting glass drew
    /// a black slab across someone else's menu bar for a few hundred
    /// milliseconds (decision 065). The layer stays in the hierarchy at zero
    /// alpha for the reasons in `backgroundShape`; its report goes unread in
    /// exactly this case, because `activeRect` short-circuits to `.zero` here
    /// (NotchWindow).
    private var silhouetteOpacity: Double { displayedExpanded || stripHidden ? 0 : 1 }

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
                // No `.animation` of its own, deliberately. Scoping the alpha
                // to `fadeAnimation` here also scopes the *geometry* arriving
                // from the frame above to it, and the silhouette then retracted
                // in 0.18s while the panel it backs took the 0.45s spring —
                // the pill reached the notch with the panel's content still
                // spilling out around it. Measured (decision 082).
                .opacity(silhouetteOpacity)
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
                    // The denser styles carry most of their own legibility and
                    // need only the contrast top-up.
                    //
                    // This replaces the per-glyph drop shadows the title,
                    // transport row, gear and progress labels each used to
                    // carry: a shadow behind every letter is what the HIG
                    // calls out as the wrong fix for text on a variable
                    // backdrop — it thickens the type and still fails on a
                    // mid-grey desktop. One scrim under the whole content
                    // does the job the shadows were approximating, and does
                    // it uniformly (decision 062).
                    if contentScrim > 0 {
                        Color.black.opacity(contentScrim)
                    }
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

    /// Rim light around the expanded panel. Two strokes: a crisp 1.2pt edge
    /// whose brightness varies down the panel (bright shoulders, dimmer
    /// waist, bright base — how a real glass edge catches light), and a wider
    /// blurred stroke under it that reads as the thickness of the material
    /// rather than a drawn outline.
    ///
    /// Applied as an overlay on the panel *after* its `clipShape`, so the
    /// stroke is not halved by the clip — and always present, alpha-gated
    /// rather than branched, so it retracts with the frame instead of freezing
    /// at full panel width on collapse (decision 082). Masked to nothing across
    /// the top blend region: the panel's
    /// first `stripHeight` points must stay pure black to merge with the notch
    /// (UI Principle #6), and an outlined seam there would read as a floating
    /// box hanging off the notch.
    private var borderLayer: some View {
        ZStack {
            shape.stroke(
                LinearGradient(
                    // Increase Contrast turns the rim from a glass highlight
                    // into an actual edge: at standard contrast the panel is
                    // meant to float, but a user who asked for hard edges
                    // needs to see where the panel stops.
                    colors: contrast == .increased
                        ? [.white.opacity(0.9), .white.opacity(0.7), .white.opacity(0.85)]
                        : [.white.opacity(0.55), .white.opacity(0.16), .white.opacity(0.38)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: contrast == .increased ? 1.5 : 1.2
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

    /// Opacity of the black scrim between the glass and the panel's content.
    ///
    /// Clear glass is nearly a window, so it carries the bulk of it; the
    /// denser styles need none at standard contrast. Increase Contrast adds a
    /// fixed top-up to every style, which is what takes white-on-glass over a
    /// bright backdrop past 4.5:1. Reduce Transparency has already made the
    /// material opaque by the time this is read, so there is nothing left to
    /// scrim.
    private var contentScrim: Double {
        if reduceTransparency { return 0 }
        var opacity: Double = prefs.panelStyle == .clear ? 0.30 : 0
        if contrast == .increased { opacity += 0.22 }
        return min(opacity, 0.6)
    }

    /// The panel's material, per `prefs.panelStyle` (decision 030).
    ///
    /// Below macOS 26 there is no `glassEffect` at all, so the three glass
    /// styles degrade to the nearest `Material` — the picker keeps working and
    /// still visibly changes the panel, it just isn't Liquid Glass. `.solid`
    /// is identical on every version.
    @ViewBuilder
    private var glassLayer: some View {
        if prefs.panelStyle == .solid || reduceTransparency {
            // Reduce Transparency collapses every style onto the opaque one.
            // Deliberately not a *tinted* opaque fill: the point of the
            // setting is that nothing behind the window shows through, and an
            // album-tinted plate still changes under the user with the track.
            shape.fill(Color.black.opacity(reduceTransparency ? 1.0 : 0.93))
        } else {
            ZStack {
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(glass, in: shape)
                } else {
                    shape.fill(prefs.panelStyle == .clear ? .ultraThinMaterial : .regularMaterial)
                }
                // The album tint's actual pixels (decision 064). `Glass.tint`
                // alone could not carry this feature: measured through
                // `ImageRenderer` over a neutral grey backdrop, every glass
                // variant — `.regular`, `.clear`, and `.regular.tint()` in red
                // and in blue — rendered to an identical 0.502/0.502/0.502.
                // `glassEffect` contributes no pixels to the view's own render
                // tree at all; it is a compositor parameter, and how much of a
                // tint the compositor chooses to show over a dark panel is not
                // ours to decide. So the colour is drawn here instead, where it
                // is ours.
                //
                // Under the black top blend, which is layered after this in
                // `backgroundShape`, so the notch seam stays black regardless.
                if prefs.panelStyle == .tinted,
                   let wash = PanelTint.wash(for: state.artworkTint) {
                    shape.fill(wash)
                }
            }
        }
    }

    /// `.tint(nil)` is defined as "no tint", so a track with no artwork (or a
    /// cover we couldn't sample) falls back to plain regular glass instead of
    /// needing a separate branch.
    ///
    /// Passed at full alpha now, not `.opacity(0.55)`: whatever the compositor
    /// is willing to contribute is on top of `PanelTint.wash` and was being
    /// halved for no stated reason.
    @available(macOS 26.0, *)
    private var glass: Glass {
        switch prefs.panelStyle {
        case .clear: return .clear
        case .tinted: return .regular.tint(state.artworkTint.map { Color(nsColor: $0) })
        case .regular, .solid: return .regular
        }
    }

    /// Hover-in arms a cancellable expansion; only when it actually fires (and
    /// only on a true collapsed → expanded transition) does the trackpad tick.
    /// Hover-out arms a cancellable collapse. Either edge cancels whatever the
    /// other one had pending.
    private func handleHover(_ hovering: Bool, expandDelay: UInt64? = nil) {
        hoverTask?.cancel()
        hoverTask = Task {
            try? await Task.sleep(nanoseconds: hovering ? (expandDelay ?? hoverExpandDelay) : Self.hoverCollapseDelay)
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
            if showsWings {
                Color.clear
                    .frame(width: wingContentWidth, height: contentSquare)
                    .overlay {
                        if showsMedia, !displayedExpanded {
                            artworkView(side: contentSquare, cornerRadius: 5)
                                .matchedGeometryEffect(id: Self.artworkID, in: artworkNamespace)
                        }
                    }
                    .padding(.leading, wingOuterInset)
                    .padding(.trailing, wingInnerInset)
                    .frame(height: stripHeight)
            }
            Spacer()
                .frame(width: notchWidth)
            if showsWings {
                Color.clear
                    .frame(width: wingContentWidth, height: contentSquare)
                    .overlay {
                        if prefs.showVisualizer {
                            VisualizerView(
                                isPlaying: state.nowPlaying?.isPlaying ?? false,
                                artworkTint: state.artworkTint,
                                prefs: prefs
                            )
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

    /// One position in the transport row (decision 074).
    ///
    /// Every case here is an action Tempo can actually carry out today.
    /// `MediaRemoteService` exposes previous / play-pause / next and nothing
    /// else, and mute is Tempo's own via `AudioOutputService` — so the palette
    /// stops there rather than offering a shuffle or repeat slot that would
    /// render a button which does nothing (UI Principle #4).
    @ViewBuilder
    private func transportControl(_ control: MusicControl) -> some View {
        switch control {
        case .none:
            EmptyView()
        case .previous:
            Button(action: { media.previousTrack() }) {
                Image(systemName: "backward.fill")
            }
            .accessibilityLabel("Previous track")
            .help("Previous track")
        case .playPause:
            Button(action: { media.playPause() }) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .help(isPlaying ? "Pause" : "Play")
        case .next:
            Button(action: { media.nextTrack() }) {
                Image(systemName: "forward.fill")
            }
            .accessibilityLabel("Next track")
            .help("Next track")
        case .mute:
            Button(action: { audio.setMuted(!audio.isMuted) }) {
                Image(systemName: audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .accessibilityLabel(audio.isMuted ? "Unmute" : "Mute")
            .help(audio.isMuted ? "Unmute" : "Mute")
        }
    }

    /// The cover, or — when there isn't one — a plate that says so.
    ///
    /// The placeholder was a flat grey square, which over the black pill read
    /// as a rendering fault rather than as "no artwork for this track". A
    /// glyph on a dim plate is the platform's own empty-state idiom and costs
    /// nothing at 20pt. Continuous corners throughout: `.continuous` is the
    /// curve macOS uses for every rounded rect of this size, and the circular
    /// one visibly disagrees with the notch shape's own corners beside it.
    ///
    /// `ambient` adds the glow and the blurred backdrop behind the cover
    /// (decision 070). Only the expanded header passes it: in the collapsed
    /// pill the bloom would spill past the black silhouette and hang in the
    /// air beside the notch, which is exactly the artefact the silhouette
    /// exists to prevent.
    private func artworkView(side: CGFloat, cornerRadius: CGFloat, ambient: Bool = false) -> some View {
        Group {
            if let artwork = state.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.14))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: side * 0.42, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .background {
            if ambient { albumAmbience(side: side, cornerRadius: cornerRadius) }
        }
        .accessibilityLabel(state.artwork == nil
                            ? "No album artwork"
                            : "Album artwork for \(state.nowPlaying?.track ?? "the current track")")
    }

    /// The light behind the album (decision 070).
    ///
    /// Two independent layers, matching the two switches boringNotch ships,
    /// because they read as different looks and people want them separately:
    /// a blurred, over-scaled copy of the cover, and a bloom in the cover's
    /// dominant colour. Both are drawn *behind* the clipped artwork and neither
    /// takes clicks.
    ///
    /// Painted, not composited. Decision 064 measured that `glassEffect`'s
    /// tint parameter contributes no pixels to this view's render tree, so a
    /// glow expressed as a material hint would have been invisible the same
    /// way the album tint was for six weeks. These are real fills and real
    /// blurs.
    ///
    /// Suppressed entirely under Reduce Transparency: a bloom is decoration
    /// spilling past the thing it decorates, which is precisely what that
    /// setting asks apps to stop doing.
    @ViewBuilder
    private func albumAmbience(side: CGFloat, cornerRadius: CGFloat) -> some View {
        if !reduceTransparency {
            let strength = prefs.albumGlowStrength
            ZStack {
                // Bloom sits under the blurred cover so the cover's own colours
                // stay the top-most thing behind the art.
                if prefs.albumGlow, let tint = state.artworkTint {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(nsColor: tint))
                        .frame(width: side, height: side)
                        .blur(radius: side * (0.10 + 0.24 * strength))
                        .scaleEffect(1 + 0.12 * strength)
                        .opacity(0.22 + 0.46 * strength)
                }
                if prefs.albumArtBlur, let artwork = state.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .blur(radius: side * 0.16)
                        .scaleEffect(1.16)
                        .opacity(0.55)
                }
            }
            .allowsHitTesting(false)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: state.artworkTint)
        }
    }

    /// What just started playing, under the notch, without opening anything
    /// (decision 072).
    ///
    /// The panel already answers "what's playing" — but only once you have
    /// moved the pointer to the notch and waited out the hover delay. A track
    /// change is the one moment the answer is wanted without being asked for,
    /// which is exactly what boringNotch's Sneak Peek is for. Suppressed while
    /// the panel is open, where it would be repeating what is already on
    /// screen an inch above it.
    @ViewBuilder
    private var sneakPeekView: some View {
        if let peek = sneakPeekTrack, !displayedExpanded {
            VStack(spacing: NotchMetrics.tightSpacing) {
                Text(peek.track)
                    .font(NotchType.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !peek.artist.isEmpty {
                    Text(peek.artist)
                        .font(NotchType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: panelWidth - 40)
            .background { peekBackground }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, NotchGeometry.stripHeight + 6)
            .allowsHitTesting(false)
            .transition(
                reduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Now playing: \(peek.track) by \(peek.artist)")
        }
    }

    /// The peek's own surface: Liquid Glass, the same material the system's
    /// own transient HUDs wear (decision 084).
    ///
    /// The peek is a system-HUD-shaped thing — a floating capsule that says
    /// one thing and leaves — so it is drawn in the material macOS 26 gives
    /// those: `.regular` glass, which refracts and tints from whatever is
    /// behind the window rather than sitting on it as a flat black plate.
    /// Deliberately untinted and independent of `panelStyle`: the AirPods and
    /// volume HUDs it is meant to sit beside are neutral, and an album-tinted
    /// peek would change colour under the user on every track.
    ///
    /// Glass draws its own rim, but a faint one that dissolves against a bright
    /// wallpaper, so a rim light is stroked over the top of it to keep the
    /// peek's edge legible on any background. The black fill is gone with the
    /// glass, and comes back for the three cases where there is no glass to
    /// have: Reduce Transparency (the setting means nothing behind shows
    /// through), the `.solid` panel style (the user has asked this app's chrome
    /// to be opaque), and macOS 14/15, which has no `glassEffect` at all.
    @ViewBuilder
    private var peekBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Self.peekCornerRadius, style: .continuous)
        if #available(macOS 26.0, *), !reduceTransparency, prefs.panelStyle != .solid {
            ZStack {
                Color.clear.glassEffect(.regular, in: shape)
                // The same top-up `contentScrim` gives the panel: glass alone
                // is thinner than the plate it replaces, and Increase Contrast
                // is a request for the text to win over what is behind it.
                if contrast == .increased { shape.fill(Color.black.opacity(0.25)) }
                shape.strokeBorder(Color.white.opacity(0.28), lineWidth: 1.5)
            }
        } else {
            shape
                .fill(Color.black.opacity(reduceTransparency ? 1.0 : 0.82))
                .overlay { shape.strokeBorder(Color.white.opacity(0.28), lineWidth: 1.5) }
        }
    }

    /// Concentric with the two lines it wraps rather than the 12pt of the
    /// plate it replaces: the system HUDs this now matches are near-capsules,
    /// and 20pt is a hair under half the peek's own height.
    private static let peekCornerRadius: CGFloat = 20

    /// Raises the peek for a new track and schedules its retraction.
    ///
    /// Only a real change to a *named* track counts. Startup, a stop, and the
    /// artwork arriving a beat after the title all pass through here, and none
    /// of them is a track change the user needs told about.
    private func showSneakPeek(for track: String?) {
        sneakPeekTask?.cancel()
        sneakPeekTask = nil

        guard prefs.sneakPeek,
              let track, !track.isEmpty,
              let playing = state.nowPlaying,
              !displayedExpanded
        else {
            if sneakPeekTrack != nil {
                withAnimation(.easeOut(duration: 0.2)) { sneakPeekTrack = nil }
            }
            return
        }

        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.34, dampingFraction: 0.82)) {
            sneakPeekTrack = playing
        }

        let seconds = prefs.sneakPeekSeconds
        sneakPeekTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { sneakPeekTrack = nil }
            sneakPeekTask = nil
        }
    }

    // MARK: Expanded content

    /// Two groups, not six equal siblings (decision 063).
    ///
    /// Everything here used to sit in one stack at a uniform 12pt, which put
    /// the artist's name exactly as far from the track title as the CPU graph
    /// was from the agent list — so the panel read as a column of unrelated
    /// widgets rather than "what's playing" followed by "what the Mac is
    /// doing". Proximity is the cheapest hierarchy there is (HIG ▸ Layout:
    /// alignment and grouping are what show which things are related), so the
    /// media controls now sit tight together, the system readouts sit tight
    /// together, and the two blocks are separated by a wider gap and a
    /// hairline.
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsMedia {
                VStack(alignment: .leading, spacing: NotchMetrics.rowSpacing) {
                    nowPlayingHeader
                    // Full content width, below the cover+controls block rather
                    // than inside the column beside the cover: the extra ~120pt
                    // is what makes the bar precise enough to scrub with
                    // (~1.7pt per second on a typical track instead of ~1.1).
                    if let progress = state.progress, progress.duration > 0 {
                        PlaybackProgressView(progress: progress) { media.seek(to: $0) }
                    }
                    // Out of the column beside the cover and across the full
                    // content width. In the column it was the tallest thing
                    // there, and since the cover matches the column's height
                    // it was what inflated the cover to ~104pt — a header
                    // half again as tall as it needed to be. Out here the
                    // column is title + artist + transport, the cover settles
                    // to its 72pt floor, and the picker gets 353pt of width
                    // instead of ~230 to show a playlist name in.
                    if api.isConfigured {
                        PlaylistSection(api: api, state: state, prefs: prefs)
                    }
                }
            }

            if showsMedia && hasSystemContent {
                groupSeparator
            }

            if hasSystemContent {
                VStack(alignment: .leading, spacing: NotchMetrics.sectionSpacing) {
                    if prefs.showAudioOutput {
                        AudioOutputView(audio: audio)
                    }
                    if prefs.showFileShelf {
                        ShelfView(shelf: shelf, isDropTargeting: state.isDragTargeting)
                    }
                    if prefs.showUsageGraph {
                        UsageGraphView()
                    }
                    if prefs.showRateLimitPace {
                        RateLimitPaceView(service: usage, prefs: prefs)
                    }
                    if prefs.showUsageHistory {
                        UsageHistoryView(service: usage)
                    }
                    if prefs.showAgentLights {
                        AgentLightsView(
                            sessions: state.sessions,
                            // Empty when the figures are switched off — the
                            // service is stopped in that case anyway, and an
                            // empty map is exactly "this row has no figures"
                            // (decision 048).
                            stats: prefs.showAgentStats ? state.sessionStats : [:],
                            onFocus: focusSession
                        )
                    }
                }
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
        .padding(.horizontal, NotchMetrics.contentInset)
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

    /// The rule between the media block and the system block. One hairline,
    /// not a header on each section: four new labels would cost ~56pt of a
    /// panel that is already close to its ceiling, and would out-shout the
    /// content they name (UI Principle #1). It brightens under Increase
    /// Contrast like every other edge in the panel.
    private var groupSeparator: some View {
        Rectangle()
            .fill(Color.primary.opacity(contrast == .increased ? 0.30 : 0.12))
            .frame(height: 1)
            .padding(.vertical, NotchMetrics.groupSpacing)
            .accessibilityHidden(true)
    }

    /// Whether the system group will actually draw anything.
    ///
    /// Asked before the separator is drawn, because three of the four sections
    /// hide themselves when they have nothing to show — an empty shelf, no
    /// live sessions — and a rule with nothing under it is worse than no rule
    /// at all. The output row and the usage graphs always draw when switched
    /// on; the shelf and the agent list do not.
    private var hasSystemContent: Bool {
        if prefs.showAudioOutput || prefs.showUsageGraph { return true }
        if prefs.showRateLimitPace || prefs.showUsageHistory { return true }
        if prefs.showFileShelf, state.isDragTargeting || !shelf.items.isEmpty { return true }
        if prefs.showAgentLights, !state.sessions.isEmpty { return true }
        return false
    }

    /// The onboarding sequence, measured and reported exactly like
    /// `expandedContent` so the panel sizes itself to it and the hit region
    /// tracks it — the panel does not care which of the two is inside.
    private var onboardingContent: some View {
        OnboardingView(
            onboarding: onboarding,
            prefs: prefs,
            api: api,
            lockCards: lockCards,
            location: location,
            openSettings: openSettings
        )
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
    ///
    /// The playlist row used to live in this column and is now below the
    /// whole block (decision 063), which is what lets the cover sit at its
    /// 72pt floor instead of being stretched to ~104 to match a column the
    /// picker had made tall.
    private var nowPlayingHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            artworkView(side: expandedArtSize, cornerRadius: 12, ambient: true)
                .matchedGeometryEffect(id: Self.artworkID, in: artworkNamespace)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 1)

            VStack(spacing: 6) {
                VStack(spacing: 2) {
                    Text(state.nowPlaying?.track ?? "Nothing playing")
                        .font(NotchType.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(state.nowPlaying?.artist ?? "")
                        .font(NotchType.subtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                // Symmetric, so the title stays centred on the play button
                // while still keeping clear of the gear in the corner.
                .padding(.horizontal, 24)
                // Title and artist are one thing to VoiceOver, and the full
                // untruncated text is what it should read — the visible line
                // is clipped to the panel's width.
                .accessibilityElement(children: .combine)
                .help(nowPlayingHelp)

                // Evenly spread: with equal spacers the middle button lands on
                // the column's centre line, directly below the title.
                // Empty slots are dropped rather than rendered as zero-width
                // boxes: with equal spacers, an extra participant on each side
                // would redistribute the spacing and shift the three default
                // buttons inward. Filtering keeps the default row byte-identical
                // to the hard-coded one it replaced (Agent Guideline #7).
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ForEach(Array(prefs.musicControlSlots.filter { $0 != .none }.enumerated()),
                            id: \.offset) { _, control in
                        transportControl(control)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(NotchButtonStyle())
                .foregroundStyle(.primary)
                // `.title2` is 17pt on macOS — the size these glyphs already
                // were, now tracking the user's text-size setting.
                .font(.title2.weight(.medium))
                .frame(maxWidth: .infinity)

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

    private var isPlaying: Bool { state.nowPlaying?.isPlaying ?? false }

    /// The full track and artist, for the tooltip and for VoiceOver. The
    /// visible line is `lineLimit(1)` inside a 405pt panel, so a long title is
    /// truncated on screen and this is the only place it survives intact
    /// (HIG ▸ Clarity: don't let the layout be the only copy of the content).
    private var nowPlayingHelp: String {
        guard let playing = state.nowPlaying else { return "Nothing playing" }
        return playing.artist.isEmpty ? playing.track : "\(playing.track) — \(playing.artist)"
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
        SessionFocusService.focus(session, among: state.sessions)
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
                .font(.body.weight(.medium))
        }
        .buttonStyle(NotchButtonStyle())
        .foregroundStyle(.secondary)
        .accessibilityLabel("Tempo Settings")
        .help("Tempo Settings")
    }

    /// Feeds the measured expanded-content height to the animatable container
    /// height and to the hit region's expanded target rect (NotchWindow.swift).
    private func reportExpandedHeight(_ contentHeight: CGFloat) {
        guard contentHeight > 0, contentHeight != expandedContentHeight else { return }
        // The ceiling is a hard clip, not a scroll: content laid out past
        // `panelHeight` is outside the window and simply never drawn, so
        // overflowing it loses the bottom section with no other symptom
        // (decision 063). Nothing can be done about it at runtime — the
        // window is not resized — but a run with TEMPO_DEBUG_VIZ=1 will at
        // least say so instead of leaving it to be noticed by eye.
        let total = contentHeight + stripHeight
        tempoDebug("panel content \(Int(contentHeight))pt + strip \(Int(stripHeight))pt"
                   + " = \(Int(total))pt of \(Int(panelHeight))pt ceiling"
                   + (total > panelHeight ? "  ** CLIPPED **" : ""))
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
