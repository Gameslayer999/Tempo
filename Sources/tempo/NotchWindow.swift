import AppKit
import SwiftUI

/// Real notch geometry read from `NSScreen`, with a fallback for notchless
/// displays. Re-read on every display change; shared by the panel (window
/// sizing and positioning) and ContentView (interior layout), so both agree
/// exactly.
enum NotchGeometry {
    static let sidePadding: CGFloat = 110
    /// Window height ceiling — the tallest the drawn panel may ever be.
    ///
    /// The window is never resized while the panel animates (that invariant is
    /// what lets only the SwiftUI content move), so this has to clear the
    /// fullest case up front. It used to be a constant (680 by decision 063),
    /// which made every growable section inside the panel responsible for
    /// bounding itself: anything laid out past the line is outside the window
    /// and simply not drawn — a hard clip, not a scroll.
    ///
    /// It is now the target screen's height less `bottomMargin`, because the
    /// agent list grows a row per session rather than scrolling inside three
    /// (decision 101), so the ceiling has to be whatever the display can
    /// actually show rather than a figure picked for one content mix. Costs
    /// nothing: the window is transparent outside the drawn shape and hands
    /// those clicks straight through (`NotchHostingView.hitTest`), and the
    /// panel still draws only as tall as its content
    /// (`ContentView.currentHeight`). Re-read on every display change through
    /// `refresh()` / `applyGeometry()`, like every other figure here.
    static var panelHeight: CGFloat { max(screenFrame.height - bottomMargin, 320) }

    /// Air left between the tallest possible panel and the bottom of the
    /// screen, so a full-height panel never runs into the screen edge.
    private static let bottomMargin: CGFloat = 24

    /// The screen Tempo hugs, and the notch dimensions read off it.
    ///
    /// Re-resolved on every display change (decision 037) rather than
    /// snapshotted at process start: `NSScreen` frames, the screen list, and
    /// `safeAreaInsets` all change when a monitor is attached or detached, the
    /// lid closes, or the arrangement is edited in System Settings. Caching
    /// them left the panel parked at coordinates for a screen layout that no
    /// longer existed.
    private(set) static var targetScreen: NSScreen? = resolveScreen()
    private(set) static var raw: (width: CGFloat, height: CGFloat) = resolveRaw(targetScreen)

    /// Always the built-in notched display when it is present, so the pill
    /// keeps hugging the real hardware notch no matter which screen is main.
    /// With the lid closed the built-in leaves `NSScreen.screens` entirely, so
    /// this falls back to the menu-bar display — documented to be index 0 of
    /// `screens`, which (unlike `NSScreen.main`) does not depend on where the
    /// key window is, and Tempo deliberately never has one.
    private static func resolveScreen() -> NSScreen? {
        // A pinned display wins over the built-in notch (decision 075) — that
        // is the whole point of pinning. It is matched by UUID rather than by
        // `CGDirectDisplayID`, which macOS reassigns across reconnects, so a
        // monitor unplugged and plugged back in is still recognised. A pin to
        // a display that is not currently attached falls through to the
        // automatic order rather than leaving the panel nowhere.
        let pinned = pinnedDisplayUUID
        if !pinned.isEmpty,
           let match = NSScreen.screens.first(where: { displayUUID(for: $0) == pinned }) {
            return match
        }
        return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.screens.first
            ?? NSScreen.main
    }

    /// Mirror of `Preferences.preferredDisplayUUID` (decision 075).
    ///
    /// `resolveScreen` is reached from `targetScreen`'s lazy static
    /// initialiser, which carries no actor, while `Preferences` is
    /// `@MainActor` — so the value is mirrored here instead of read across the
    /// boundary. Every write goes through `Preferences`, which is main-actor
    /// isolated, so the writes are serialised even though the annotation
    /// cannot prove it; reads are of a single word and may race only with a
    /// change the user just made, whose own `applyGeometry` follows
    /// immediately behind it.
    nonisolated(unsafe) static var pinnedDisplayUUID = ""

    /// Stable identifier for a display, used to persist the pinned-display
    /// choice. `nil` when the screen has no backing `CGDirectDisplayID` — a
    /// case that does occur mid-reconfiguration — and callers treat that as
    /// "not the pinned one" rather than as an error.
    static func displayUUID(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else { return nil }
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(
            CGDirectDisplayID(number.uint32Value)
        )?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// Every attached display, for the Settings picker.
    static var availableDisplays: [(uuid: String, name: String, hasNotch: Bool)] {
        NSScreen.screens.compactMap { screen in
            guard let uuid = displayUUID(for: screen) else { return nil }
            return (uuid, screen.localizedName, screen.safeAreaInsets.top > 0)
        }
    }

    private static func resolveRaw(_ screen: NSScreen?) -> (width: CGFloat, height: CGFloat) {
        guard let screen else { return (200, 32) }
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            let height = screen.safeAreaInsets.top
            if width > 0, height > 0 { return (width, height) }
        }
        return (200, 32) // notchless fallback: centered 200x32 strip
    }

    /// Re-reads the display layout. Returns true when anything the panel or
    /// the content lays out against actually moved, so callers can skip the
    /// window/layout work for the many no-op notifications macOS emits during
    /// a single reconfiguration.
    @discardableResult
    static func refresh() -> Bool {
        let screen = resolveScreen()
        let newRaw = resolveRaw(screen)
        // Compared by value, not by object identity: macOS hands out fresh
        // `NSScreen` instances on every reconfiguration, so an identity check
        // would report a change for each of the several notifications one
        // reconfiguration emits. The old instance is still what the previous
        // frame was computed from, which is exactly the comparison wanted.
        let changed = newRaw != raw || screen?.frame != targetScreen?.frame
        targetScreen = screen
        raw = newRaw
        return changed
    }

    /// Whether the screen Tempo is hugging actually has a hardware notch.
    ///
    /// False means the strip is the notchless fallback — the lid is closed, or
    /// the Mac has no built-in notch at all — and Tempo is drawing a 200x32
    /// bar at the top of whichever display carries the menu bar. That is the
    /// only case `Preferences.showStripOnExternalDisplays` governs
    /// (decisions 054, 055):
    /// when the built-in notched display is present, `resolveScreen` already
    /// picks it over every external one, so the setting has nothing to do.
    ///
    /// Read from the resolved screen rather than from `raw`, because the
    /// fallback dimensions are a plausible real notch size and would not
    /// distinguish the two cases.
    static var isHardwareNotch: Bool { (targetScreen?.safeAreaInsets.top ?? 0) > 0 }

    static var notchWidth: CGFloat { raw.width }
    static var notchHeight: CGFloat { raw.height }
    static var stripHeight: CGFloat { notchHeight }

    /// Vertical inset above and below the wing squares.
    static let contentInset: CGFloat = 6
    /// Side of the artwork / visualizer square that sits in each wing.
    static var contentSquare: CGFloat { max(stripHeight - contentInset * 2, 0) }
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
    static var wingContentWidth: CGFloat { max(contentSquare, VisualizerView.naturalWidth) }
    /// Width of one wing beside the notch.
    static var wingWidth: CGFloat { wingOuterInset + wingContentWidth + wingInnerInset }
    /// Collapsed pill: the physical notch plus one wing on each side. This is
    /// the whole hover/hit surface while collapsed.
    static var pillWidth: CGFloat { notchWidth + wingWidth * 2 }
    /// Expanded panel, and therefore the (never resized) window width.
    static var panelWidth: CGFloat { notchWidth + sidePadding * 2 }

    /// How far outside the collapsed pill a file drag still counts as
    /// heading for the notch. The notch should *attract* a drag rather than
    /// demand pixel accuracy — the user aims at the top of the screen, not at
    /// a 32pt strip (decision 051).
    static let dragActivationMargin: CGFloat = 80

    /// A region flush with the top of the target screen, in screen coordinates
    /// (origin bottom-left, matching `NSEvent.mouseLocation`), horizontally
    /// centred on the screen.
    ///
    /// One point *taller* than asked for, overshooting above the screen's top
    /// edge, because `NSRect.contains` excludes its own `maxY` and the pointer
    /// resting on the topmost row of the display reports exactly
    /// `screen.maxY`. Measured on this machine (3440x1440 external display,
    /// 30pt menu bar) by warping the cursor: Quartz y=0 gives
    /// `NSEvent.mouseLocation.y == 1440.0 == frame.maxY`, which a rect ending
    /// at 1440 does not contain, while y=1 gives 1439.0, which it does. That
    /// was a one-point dead band along the very edge the pointer is thrown at
    /// — slam it to the top of the display and the notch went dead, back it
    /// off a pixel and it opened (decision 096). The overshoot covers space
    /// the pointer cannot otherwise reach, so it makes no other target bigger.
    private static func topAnchoredRegion(width: CGFloat, height: CGFloat) -> NSRect {
        let screen = screenFrame
        return NSRect(
            x: screen.midX - width / 2,
            y: screen.maxY - height,
            width: width,
            height: height + 1
        )
    }

    /// Screen-coordinate region (origin bottom-left, matching
    /// `NSEvent.mouseLocation`) in which a dragged file opens the shelf.
    /// Recomputed per event so it follows the notch across displays
    /// (decision 037).
    static var dragActivationRegion: NSRect {
        topAnchoredRegion(
            width: pillWidth + dragActivationMargin * 2,
            height: notchHeight + dragActivationMargin
        )
    }

    /// Screen-coordinate region (origin bottom-left, matching
    /// `NSEvent.mouseLocation`) that opens the notch when the collapsed strip
    /// is not drawn (decision 055): the menu bar's own row, `notchWidth` wide
    /// and `height` tall, where `height` is the bar as the caller measured it
    /// (plus `topAnchoredRegion`'s one-point overshoot above the screen edge).
    ///
    /// Not where the pill *would* be — an invisible 32pt-tall, `pillWidth`-wide
    /// slab opened the panel whenever the pointer passed near the top of the
    /// display (decision 090) — and no longer the 3pt edge band that replaced
    /// it either: 3pt was too tight to *hold*, so relaxing the pointer a pixel
    /// after the menu bar dropped cancelled the dwell or collapsed the panel
    /// a frame after it opened (decision 095). What keeps this honest is not
    /// the height but `MenuBarSensor` — the caller opens only while the bar is
    /// fully down, and a bar that is down covers whatever was underneath it.
    ///
    /// `notchWidth` and not the live `collapsedWidth`, so the target does not
    /// change size with the media UI (decision 038): an invisible target that
    /// silently resizes is unusable.
    static func hoverActivationRegion(height: CGFloat) -> NSRect {
        topAnchoredRegion(width: notchWidth, height: height)
    }

    /// Screen-coordinate region the expanded panel occupies right now — what
    /// keeps the undrawn notch open once the pointer is inside it. Sized from
    /// the same content-measured target the hit region uses, so it tracks a
    /// panel whose sections have appeared or disappeared.
    static var expandedPanelRegion: NSRect {
        let size = NotchHitRegion.shared.expandedTarget
        return topAnchoredRegion(width: size.width, height: size.height)
    }

    static var screenFrame: NSRect {
        targetScreen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Where the window belongs right now: `panelWidth` x `panelHeight`,
    /// horizontally centred on the target screen and flush with its top edge.
    static var windowFrame: NSRect {
        let screen = screenFrame
        let width = panelWidth
        return NSRect(
            x: screen.midX - width / 2,
            y: screen.maxY - panelHeight,
            width: width,
            height: panelHeight
        )
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
    private var stored = CGSize(width: NotchGeometry.notchWidth, height: NotchGeometry.stripHeight)
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
    private var screenObserver: Any?
    private var spaceObservers: [NSObjectProtocol] = []
    private var settleTask: Task<Void, Never>?
    private let state: AppState
    private let prefs: Preferences

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

    init(state: AppState, prefs: Preferences, content: ContentView) {
        self.state = state
        self.prefs = prefs

        super.init(
            contentRect: NotchGeometry.windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        applyPrivacyAndSpaceBehavior()
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
        // - settled collapsed: exactly the pill — which is the bare notch
        //   when the media UI is idle (decision 038), hence a floor of
        //   `notchWidth` and not `pillWidth`: floored at the pill it would
        //   keep claiming the two wings after they had visibly retracted, and
        //   those 43pt sit right beside the menu bar's own items.
        //
        // Every bound is read from `NotchGeometry` at call time rather than
        // captured here, because the pill and panel widths change with the
        // display (decision 037) — captured bounds would clamp the region to
        // the previous screen's notch after a monitor is attached.
        let hostingView = NotchHostingView(
            activeRect: { [weak state] in
                let panelWidth = NotchGeometry.panelWidth
                let panelHeight = NotchGeometry.panelHeight
                // - strip hidden on a notchless display, panel shut
                //   (decision 055): nothing is drawn, so nothing is claimed,
                //   and every click in the middle of that menu bar goes to the
                //   app behind (Agent Guideline #3). Keyed off the expansion
                //   flag rather than the live shape — the opposite of the
                //   collapsing rule above, and deliberately so: the flag flips
                //   while the panel is still visibly fading, so this hands
                //   clicks back a few hundred milliseconds early. That is the
                //   right way to err here, because what is fading sits over
                //   someone else's menu bar, and swallowing a click there is
                //   worse than dropping one.
                if state?.displayedExpanded != true,
                   !prefs.showStripOnExternalDisplays,
                   !NotchGeometry.isHardwareNotch {
                    return .zero
                }
                let source = state?.displayedExpanded == true
                    ? NotchHitRegion.shared.expandedTarget
                    : NotchHitRegion.shared.size
                let width = min(max(source.width, NotchGeometry.notchWidth), panelWidth)
                let height = min(max(source.height, NotchGeometry.stripHeight), panelHeight)
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

        // Attaching or detaching a monitor, closing the lid, or rearranging
        // displays in System Settings moves the notch — a different screen,
        // a different origin in the global coordinate space, or no hardware
        // notch at all. Without this the window stayed at its launch-time
        // frame, which is why the panel landed in the wrong place (and, in
        // clamshell, at the wrong size) after plugging in an external display.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenParametersChanged() }
        }

        // Entering or leaving full screen is a Space switch, and activating a
        // different app can land on a Space that is already full screen. Both
        // edges have to be watched or the panel stays hidden after the user
        // has left the full-screen app.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
        ] {
            spaceObservers.append(workspace.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyFullScreenVisibility() }
            })
        }
    }

    /// Applies the two window flags that are user-adjustable, from one place
    /// so the launch path and the settings-changed path cannot drift apart.
    ///
    /// `sharingType = .none` (decision 077) excludes the panel from screen
    /// capture and sharing — Zoom, Meet, Teams, OBS and `screencapture` alike.
    /// This is a window-server flag, not a drawing trick, so it needs no
    /// permission and cannot be defeated by a compositing path the way the
    /// glass tint was (decision 064).
    ///
    /// `.fullScreenAuxiliary` (decision 076) is what lets a non-activating
    /// panel draw over a full-screen app at all. Dropping it is what "hide for
    /// all apps" means at the window level; the per-app case additionally
    /// orders the window out, because a Space that is already full screen does
    /// not re-evaluate collection behaviour on its own.
    func applyPrivacyAndSpaceBehavior() {
        sharingType = prefs.hideFromScreenCapture ? .none : .readOnly

        var behavior: NSWindow.CollectionBehavior = [
            .canJoinAllSpaces, .stationary, .ignoresCycle,
        ]
        if prefs.fullScreenBehavior != .allApps {
            behavior.insert(.fullScreenAuxiliary)
        }
        collectionBehavior = behavior
    }

    /// Hides or restores the panel for the current full-screen state.
    ///
    /// Detected from the screen's own geometry rather than from any private
    /// API: a Space showing a full-screen app hides the menu bar, so
    /// `visibleFrame` reaches `frame`'s top edge; in every ordinary Space the
    /// menu bar keeps them apart. That check costs nothing and needs no
    /// Accessibility grant, which a window-list walk would.
    func applyFullScreenVisibility() {
        let behavior = prefs.fullScreenBehavior
        guard behavior != .never else {
            if !isVisible { orderFrontRegardless() }
            return
        }
        guard let screen = NotchGeometry.targetScreen else { return }

        // A Space showing a full-screen app hides the menu bar, so
        // `visibleFrame` reaches `frame`'s top edge; in every ordinary Space
        // the menu bar keeps them apart. Needs no private API and no
        // Accessibility grant, which a window-list walk would.
        let menuBarHidden = screen.visibleFrame.maxY >= screen.frame.maxY - 1

        // `.mediaApp` hides only for the app that is actually playing. Without
        // this the option would behave identically to `.allApps` — a control
        // whose label promises something it does not do (UI Principle #4).
        // The frontmost app is the one that owns the full-screen Space.
        let shouldHide: Bool
        switch behavior {
        case .never:
            shouldHide = false
        case .allApps:
            shouldHide = menuBarHidden
        case .mediaApp:
            let playing = state.nowPlaying?.sourceBundleID
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            shouldHide = menuBarHidden && playing != nil && playing == front
        }

        if shouldHide {
            if isVisible { orderOut(nil) }
        } else if !isVisible {
            orderFrontRegardless()
        }
    }

    /// Re-reads the display layout and moves the window to match.
    private func screenParametersChanged() {
        applyGeometry()
        // macOS emits this notification while a reconfiguration is still
        // settling — during a lid open the built-in screen can already be back
        // in `NSScreen.screens` while its `safeAreaInsets` still read zero, so
        // the first pass computes the notchless fallback. One re-check after
        // the dust settles corrects that; it is a no-op when the first pass
        // already got it right.
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            self?.applyGeometry()
        }
    }

    /// Moves/resizes the window onto the current notch, and tells the SwiftUI
    /// content to re-lay out against the new dimensions. Both are skipped when
    /// nothing actually changed.
    /// `force` bypasses the "nothing changed" check. Pinning a different
    /// display is the case that needs it: two identical external monitors
    /// report identical frames, so the value comparison in `refresh()` cannot
    /// see the move, and without this the panel would stay on the old screen.
    func applyGeometry(force: Bool = false) {
        let changed = NotchGeometry.refresh()
        guard changed || force else { return }
        setFrame(NotchGeometry.windowFrame, display: true)
        // ContentView reads its widths from NotchGeometry on every body
        // evaluation; this is what makes it evaluate again.
        state.screenGeneration &+= 1
    }

    deinit {
        settleTask?.cancel()
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in spaceObservers {
            workspace.removeObserver(observer)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
    }
}
