import AppKit
import SwiftUI

/// Real notch geometry read from `NSScreen`, with a fallback for notchless
/// displays. Computed once at process start; shared by the panel (window sizing
/// and positioning) and ContentView (interior layout), so both agree exactly.
enum NotchGeometry {
    static let sidePadding: CGFloat = 110
    /// Window height ceiling. The drawn expanded panel sizes itself to its
    /// content (sections hide/show — see ContentView.expandedContent) and is
    /// usually shorter than this; the window just has to be tall enough for
    /// the fullest case (all sections visible).
    static let panelHeight: CGFloat = 280

    static let targetScreen: NSScreen? =
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main

    private static let raw: (width: CGFloat, height: CGFloat) = {
        guard let screen = targetScreen else { return (200, 32) }
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            let height = screen.safeAreaInsets.top
            if width > 0, height > 0 { return (width, height) }
        }
        return (200, 32) // notchless fallback: centered 200x32 strip
    }()

    static let notchWidth: CGFloat = raw.width
    static let notchHeight: CGFloat = raw.height
    static let stripHeight: CGFloat = notchHeight

    /// Vertical inset above and below the wing squares.
    static let contentInset: CGFloat = 6
    /// Side of the artwork / visualizer square that sits in each wing.
    static let contentSquare: CGFloat = max(stripHeight - contentInset * 2, 0)
    /// Inset from the pill's *outer* edge to its wing square. The silhouette's
    /// top corners sweep inward by `NotchShape.collapsedTopRadius` and its
    /// bottom corners round by `collapsedBottomRadius`, so the straight side
    /// only begins `collapsedTopRadius` inside the pill rect — content flush
    /// with the rect edge pokes outside the black fill at both corners, which
    /// is invisible over a dark window and obvious over a light desktop.
    static let wingOuterInset: CGFloat = NotchShape.collapsedTopRadius + contentInset
    /// Inset from the wing square to the physical notch edge.
    static let wingInnerInset: CGFloat = contentInset
    /// Width of the content slot in each wing. Wide enough for the artwork
    /// square *and* the visualizer's bar row, so both wings stay identical and
    /// neither one's content overflows its slot.
    static let wingContentWidth: CGFloat = max(contentSquare, VisualizerView.naturalWidth)
    /// Width of one wing beside the notch.
    static let wingWidth: CGFloat = wingOuterInset + wingContentWidth + wingInnerInset
    /// Collapsed pill: the physical notch plus one wing on each side. This is
    /// the whole hover/hit surface while collapsed.
    static let pillWidth: CGFloat = notchWidth + wingWidth * 2
    /// Expanded panel, and therefore the (never resized) window width.
    static let panelWidth: CGFloat = notchWidth + sidePadding * 2

    static var screenFrame: NSRect {
        targetScreen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }
}

/// Size of the notch shape SwiftUI is drawing *right now*, in points.
///
/// The window is always sized to the expanded (max) dimensions so the window
/// frame never has to animate — only the SwiftUI content does. That leaves
/// most of the window transparent and empty, and a stock `NSHostingView`
/// claims every mouse event anywhere in its bounds: verified on macOS 26.6 /
/// Swift 6.3 that `NSHostingView.hitTest` does not consult SwiftUI hit-testing
/// at all — it returns self for any point inside its bounds even when the root
/// view is `.allowsHitTesting(false)`. So the panel has to decide passthrough
/// itself (Agent Guideline #3: never swallow clicks meant for other apps).
///
/// It must decide it against the shape that is on screen at this instant, not
/// against a discrete expanded/collapsed flag. Keying off the flag was the
/// click-fallthrough bug: on hover-out the flag flips immediately while the
/// panel is still visually expanded mid-spring, the hit region snaps back to
/// the collapsed pill, and a click on a control that is still plainly visible
/// falls straight through to the window behind.
///
/// `NotchShape.path(in:)` is invoked on the main thread once per animation
/// frame with the interpolated rect (measured: ~298 calls across a 0.45s
/// spring, monotonic in both directions), so it is the exact live geometry.
/// It writes here; `NotchPanel`'s hosting view reads here.
final class NotchHitRegion: @unchecked Sendable {
    static let shared = NotchHitRegion()

    private let lock = NSLock()
    private var stored = CGSize(width: NotchGeometry.pillWidth, height: NotchGeometry.stripHeight)
    private var storedTarget = CGSize(width: NotchGeometry.panelWidth, height: NotchGeometry.panelHeight)

    var size: CGSize {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }

    /// Full size of the expanded panel's *content-determined* layout — the
    /// size the shape is heading toward while opening. Reported by
    /// ContentView the moment the expanded content lays out (which happens at
    /// final size on the first frame of the expansion, before the spring gets
    /// there). Defaults to the window size until first reported, which only
    /// over-claims briefly and only while the pointer is on the pill.
    var expandedTarget: CGSize {
        get { lock.lock(); defer { lock.unlock() }; return storedTarget }
        set { lock.lock(); storedTarget = newValue; lock.unlock() }
    }
}

/// `NSHostingView` that only accepts mouse events inside `activeRect`, so
/// everything else in the transparent window stays click-through.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    private let activeRect: () -> CGRect

    init(activeRect: @escaping () -> CGRect, rootView: Content) {
        self.activeRect = activeRect
        super.init(rootView: rootView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @available(*, unavailable)
    required init(rootView: Content) {
        fatalError("use init(activeRect:rootView:) instead")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard activeRect().contains(point) else { return nil }
        return super.hitTest(point)
    }
}

/// Borderless, non-activating panel that hugs the notch. Collapsed it draws a
/// Dynamic-Island-style pill flush with the notch; hover expands it below the
/// notch and a click pins it open.
@MainActor
final class NotchPanel: NSPanel {
    private var globalClickMonitor: Any?
    private let state: AppState

    /// Never key, never main: the panel overlays every app and must never take
    /// focus away from what the user is actually typing into.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Any click that lands on the drawn panel pins it open.
    ///
    /// This has to happen here rather than in a SwiftUI tap gesture: a `Button`
    /// or a `Menu` consumes the tap before any gesture on the container sees
    /// it, so clicking a control — a transport button, or the playlist picker —
    /// never pinned. Opening the playlist menu then moved the pointer off the
    /// panel, hover-out fired, and the panel collapsed out from under the menu
    /// the user had just opened. `sendEvent` is the window's own entry point
    /// for every event routed to it, so it sees the mouse-down before any view
    /// gets the chance to swallow it.
    ///
    /// Gated on `contentView.hitTest`, which is the same live-geometry region
    /// decision 012 uses for passthrough: a click on the transparent part of
    /// the window is meant for the app behind and must not pin anything.
    ///
    /// The gear still collapses the panel — it pins here on mouse-down, then
    /// its action runs on mouse-up and wins.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           state.displayedExpanded,
           contentView?.hitTest(event.locationInWindow) != nil {
            state.isExpanded = true
        }
        super.sendEvent(event)
    }

    init(state: AppState, content: ContentView) {
        self.state = state

        let panelWidth = NotchGeometry.panelWidth
        let panelHeight = NotchGeometry.panelHeight
        let pillWidth = NotchGeometry.pillWidth
        let stripHeight = NotchGeometry.stripHeight
        let screenFrame = NotchGeometry.screenFrame

        let origin = NSPoint(
            x: screenFrame.midX - panelWidth / 2,
            y: screenFrame.maxY - panelHeight
        )
        let frame = NSRect(origin: origin, size: NSSize(width: panelWidth, height: panelHeight))

        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        // The content is designed dark (black pill, white-on-dark controls) and
        // the expanded panel's materials must render dark regardless of the
        // user's system appearance.
        appearance = NSAppearance(named: .darkAqua)

        // Hit region, in window coordinates (y up from the bottom; the drawn
        // shape is top-aligned and horizontally centered):
        //
        // - displayed-expanded (opening or open): the expanded panel's target
        //   rect. The region has to jump to the full target the instant
        //   expansion starts, otherwise a pointer travelling from the pill
        //   down to a control outruns the growing panel edge, leaves the
        //   view, and cancels the expansion. The target (not the whole
        //   window) is used so the window band below a content-sized panel
        //   stays click-through even while expanded.
        // - collapsing: the live shape size, which shrinks with the spring, so
        //   a click on a still-visible control is still caught by us and
        //   passthrough is handed back progressively as the panel retracts.
        //   This is the fix for the click-fallthrough bug.
        // - settled collapsed: exactly the pill.
        let hostingView = NotchHostingView(
            activeRect: { [weak state] in
                if state?.displayedExpanded == true {
                    let target = NotchHitRegion.shared.expandedTarget
                    let width = min(max(target.width, pillWidth), panelWidth)
                    let height = min(max(target.height, stripHeight), panelHeight)
                    return CGRect(
                        x: (panelWidth - width) / 2,
                        y: panelHeight - height,
                        width: width,
                        height: height
                    )
                }
                let live = NotchHitRegion.shared.size
                let width = min(max(live.width, pillWidth), panelWidth)
                let height = min(max(live.height, stripHeight), panelHeight)
                return CGRect(
                    x: (panelWidth - width) / 2,
                    y: panelHeight - height,
                    width: width,
                    height: height
                )
            },
            rootView: content
        )
        contentView = hostingView

        // Click outside the panel (in another app, or the desktop) unpins
        // and collapses the expanded view. Global monitors only fire for
        // events outside our own app's windows, which is exactly "outside"
        // here.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self, self.state.isExpanded || self.state.isHovered else { return }
            // A global monitor skips events delivered to the *active* app — and
            // this panel is deliberately non-activating, so Tempo is never the
            // active app and its own clicks arrive here too. Without this guard
            // every click on the panel counted as a click outside it and
            // collapsed the panel. (It went unnoticed because decision 011's
            // pin was a tap gesture, which fires on mouse-*up*, after this
            // mouse-*down* — so it silently re-pinned what this had just
            // cleared.)
            //
            // Same hit region as the passthrough and the pin: if the point is
            // on the drawn panel, it is not an outside click.
            let point = self.convertPoint(fromScreen: NSEvent.mouseLocation)
            guard self.contentView?.hitTest(point) == nil else { return }

            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.state.isExpanded = false
                self.state.isHovered = false
            }
        }
    }

    deinit {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
    }
}
