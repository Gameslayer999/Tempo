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
        let row = NotchGeometry.hoverActivationRegion(height: menuBar.barHeight)
        let inRow = row.contains(pointer)
        // The bar drops a beat *after* the pointer arrives, and a pointer held
        // still sends no further mouse-moved events — so without this the gate
        // would be evaluated once, before the bar had moved, and never again.
        // Polls only while the pointer is actually in the row.
        if inRow { startGateTimer() } else { stopGateTimer() }
        publish(inRow && menuBar.isMenuBarDown)
    }

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
