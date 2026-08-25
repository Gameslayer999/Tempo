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

    init(state: AppState) {
        self.state = state
    }

    /// While the panel is open the region *is* the panel, so the pointer
    /// moving from the invisible strip down into the controls keeps it open —
    /// with the collapsed region alone it would read as "left the notch" the
    /// moment it crossed below the menu bar.
    private var region: NSRect {
        state.displayedExpanded
            ? NotchGeometry.expandedPanelRegion
            : NotchGeometry.hoverActivationRegion
    }

    func start() {
        guard monitor == nil else { return }
        // Global monitors are delivered on the main thread, which is where this
        // object lives; the hop keeps that promise explicit for the compiler.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // `NSEvent.mouseLocation` rather than the event's own location:
                // the event is in the coordinate space of whatever window it
                // was headed for, and this region is in screen coordinates.
                let inside = self.region.contains(NSEvent.mouseLocation)
                // Republishing an unchanged value on every mouse-moved event
                // would re-evaluate the panel's body dozens of times a second
                // for nothing.
                if inside != self.state.isPointerNearNotch {
                    self.state.isPointerNearNotch = inside
                }
            }
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        // Clears the hover the monitor is responsible for, so switching the
        // strip back on cannot leave the panel pinned open by a pointer flag
        // nothing updates any more.
        state.isPointerNearNotch = false
    }
}
