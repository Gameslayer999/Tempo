import AppKit

/// Opens the notch that isn't drawn (decision 055).
///
/// With `showStripOnExternalDisplays` off on a notchless display, the collapsed
/// pill is invisible *and* claims no clicks — `NotchHostingView.hitTest`
/// returns nil over it, so the window receives no mouse events there at all and
/// SwiftUI's `.onHover` can never fire. The pointer's position is therefore the
/// only signal left, and a global monitor is the only way to see it.
///
/// `NSEvent.addGlobalMonitorForEvents` for *mouse* events needs no
/// Accessibility or Input Monitoring grant — the same finding `DragDetector`
/// rests on, verified on this machine with an ad-hoc-signed probe.
///
/// Runs only in that one mode. Everywhere else the drawn pill is hit-testable
/// and `.onHover` does this job, so this monitor is not installed and the
/// pointer is not watched at all.
@MainActor
final class NotchHoverDetector {
    private let state: AppState
    private var monitor: Any?
    /// The menu-bar gate (decision 091). Lives and dies with the monitor, so
    /// the status item it owns exists only in this one mode.
    private let menuBar = MenuBarSensor()
    private var gateTimer: Timer?

    init(state: AppState) {
        self.state = state
    }

    func start() {
        guard monitor == nil else { return }
        menuBar.start()
        // Global monitors are delivered on the main thread, which is where this
        // object lives; the hop keeps that promise explicit for the compiler.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluate()
            }
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        stopGateTimer()
        menuBar.stop()
        // Clears the hover the monitor is responsible for, so switching the
        // strip back on cannot leave the panel pinned open by a pointer flag
        // nothing updates any more.
        state.isPointerNearNotch = false
    }

    /// Is the pointer somewhere that should keep the undrawn notch open?
    ///
    /// While the panel is open the region *is* the panel, so the pointer
    /// moving from the edge down into the controls keeps it open — with the
    /// collapsed band alone it would read as "left the notch" the moment it
    /// crossed below the menu bar. The menu-bar gate deliberately does not
    /// apply there either: moving down into the panel retracts the bar, and
    /// gating on it would slam the panel shut the instant it was used.
    private func evaluate() {
        // `NSEvent.mouseLocation` rather than the event's own location: the
        // event is in the coordinate space of whatever window it was headed
        // for, and these regions are in screen coordinates.
        let pointer = NSEvent.mouseLocation

        if state.displayedExpanded {
            stopGateTimer()
            publish(NotchGeometry.expandedPanelRegion.contains(pointer))
            return
        }

        // The menu bar's row, measured (decision 095). Wide enough to *hold*
        // the pointer: the gate below is what makes it safe, not the height.
        // Rejecting everything outside it first is also what keeps the gate's
        // window-list scan off the path of an ordinary mouse move.
        let row = NotchGeometry.hoverActivationRegion(height: menuBar.barHeight)
        guard row.contains(pointer) else {
            stopGateTimer()
            publish(false)
            return
        }
        // The bar drops a beat *after* the pointer arrives, and a pointer held
        // still sends no further mouse-moved events — so without this the gate
        // would be evaluated once, before the bar had moved, and never again.
        // Polls only while the pointer is actually in the row.
        startGateTimer()
        publish(gateIsOpen())
    }

    /// May the pointer sitting in the top row open the panel right now?
    ///
    /// Two different questions, because the row has two different owners
    /// (decision 106).
    ///
    /// **On the desktop** the row is the menu bar's, and the answer is
    /// `MenuBarSensor` exactly as decisions 091/095/103 left it — including its
    /// requirement to degrade *open*, since on a display where the sensor
    /// cannot see, refusing would leave no way into the app at all.
    ///
    /// **Inside a full-screen Space** the row belongs to the app — a browser
    /// puts its tab strip flush against the top edge — and `MenuBarSensor`
    /// cannot say otherwise: on a permanently visible bar it reads down at all
    /// times, which is what put Tempo over Chrome's tabs and made it swallow
    /// the click meant to close one. There the answer is whether the system has
    /// actually drawn the menu bar over that app, which it does only for a
    /// pointer *held* at the very edge (measured: 461ms to arrive, 277ms to
    /// leave). A pointer passing through the edge on its way to a tab is long
    /// gone before that, so nothing opens; a deliberate push brings the bar
    /// down and the panel with it.
    ///
    /// The three cases are tested in this order deliberately. The bar being
    /// drawn over a full-screen app settles it on its own — and has to be asked
    /// first, because the bar arriving *pushes the app's windows out of the
    /// row* (Chrome's tab strip moves `{0,0,…}` -> `{0,30,…}`, measured), so by
    /// then the app no longer looks like it owns anything and the desktop
    /// branch would answer instead. Right result, wrong reason, and only right
    /// where the desktop sensor happens to fail open.
    ///
    /// Reached only once the pointer is already inside the row, so the
    /// window-list scan never runs on an ordinary mouse move.
    private func gateIsOpen() -> Bool {
        guard let screen = NotchGeometry.targetScreen else { return menuBar.isMenuBarDown }
        let topRow = ScreenWindows.topRow(on: screen)
        // The system has put the menu bar in the row: it is the bar's, whoever
        // else wanted it, and whatever was under it is now under it.
        if topRow.menuBarOverlayDown { return true }
        // An app's window is sitting in the row. Not ours to open into.
        if topRow.fullScreenApp != nil {
            appOwnedRowAt = Date()
            return false
        }
        // Neither — which is the desktop, *or* the ~250ms while the bar slides
        // in over a full-screen app: the app's windows have already been pushed
        // out of the row and the bar has not yet arrived in it, so nothing is
        // there to be found. Measured: that gap alone re-opened the gate
        // mid-reveal, on the fail-open desktop branch. A full-screen Space seen
        // a moment ago is still one.
        if let seen = appOwnedRowAt, Date().timeIntervalSince(seen) < Self.fullScreenGrace {
            return false
        }
        // Desktop: the row is the menu bar's, and the sensor is the answer.
        return menuBar.isMenuBarDown
    }

    /// When an app's window was last seen occupying the menu bar's row.
    private var appOwnedRowAt: Date?

    /// How long after that the row is still treated as the app's. Covers the
    /// bar's slide (measured at 461ms to arrive, 277ms to leave) with room to
    /// spare; its only other effect is to hold the gate shut for up to a second
    /// after leaving a full-screen Space, which self-corrects on the next
    /// evaluation.
    private static let fullScreenGrace: TimeInterval = 1.0

    /// Republishing an unchanged value on every mouse-moved event would
    /// re-evaluate the panel's body dozens of times a second for nothing.
    private func publish(_ near: Bool) {
        if near != state.isPointerNearNotch {
            state.isPointerNearNotch = near
        }
    }

    private func startGateTimer() {
        guard gateTimer == nil else { return }
        gateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluate()
            }
        }
    }

    private func stopGateTimer() {
        gateTimer?.invalidate()
        gateTimer = nil
    }
}
