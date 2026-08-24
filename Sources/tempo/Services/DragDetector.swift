import AppKit
import UniformTypeIdentifiers

/// Notices that a file drag is happening anywhere on the Mac, so the notch can
/// open itself into a drop target before the pointer ever reaches it.
///
/// macOS gives an app no notification of a drag it is not part of, so the only
/// signal available is the mouse itself. `NSEvent.addGlobalMonitorForEvents`
/// for *mouse* events needs no Accessibility or Input Monitoring grant —
/// verified on this machine by running an ad-hoc-signed probe bundle whose
/// `AXIsProcessTrusted()` and `CGPreflightListenEventAccess()` both returned
/// false and which still received every posted `.leftMouseDown`,
/// `.leftMouseDragged` and `.leftMouseUp`. (Keyboard monitoring is the gated
/// case; Tempo never asks for it.)
///
/// A pointer moving with the button down is not necessarily a *content* drag —
/// it is also text selection, a window move, a slider. The discriminator is the
/// drag pasteboard: AppKit fills it at the start of a real dragging session, so
/// a `changeCount` that differs from the one snapshotted at mouse-down means
/// content is in flight. Only the pasteboard's *type list* is read, never its
/// contents (Agent Guideline #5).
@MainActor
final class DragDetector: ObservableObject {

    /// True while the user is dragging droppable content anywhere on screen.
    @Published private(set) var isDraggingContent = false

    /// True while such a drag is inside the activation region.
    @Published private(set) var isNearNotch = false

    /// Supplies the current activation region in screen coordinates. Tempo
    /// moves the notch between displays at runtime (decision 037), so this is
    /// re-evaluated on every event rather than captured once at init.
    var activationRegion: () -> CGRect = { .zero }

    /// Types that mean "this drag could end up on the shelf". The shelf stores
    /// files, so a plain-text or web-link drag is deliberately not enough to
    /// open the notch — that would be a drop target that refuses the drop.
    private static let droppableTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
        NSPasteboard.PasteboardType(UTType.url.identifier),
    ]

    private let dragPasteboard = NSPasteboard(name: .drag)
    private var monitors: [Any] = []
    private var buttonIsDown = false
    private var changeCountAtMouseDown = -1

    /// The mouse-up that ends a cross-app drag is consumed by the dragging
    /// session of the *source* app, so the global `.leftMouseUp` monitor cannot
    /// be relied on to fire. Without a backstop the notch would stay stuck open
    /// as a drop target for a drag that already finished — a lying signal (UI
    /// Principle #4). This polls the physical button state instead, and only
    /// while a drag is actually in flight.
    private var releaseWatchdog: Timer?

    init() {}

    func start() {
        stop()

        add(.leftMouseDown) { [weak self] _ in
            guard let self else { return }
            self.buttonIsDown = true
            self.changeCountAtMouseDown = self.dragPasteboard.changeCount
        }

        add(.leftMouseDragged) { [weak self] _ in
            guard let self, self.buttonIsDown else { return }

            if !self.isDraggingContent,
               self.dragPasteboard.changeCount != self.changeCountAtMouseDown,
               self.hasDroppableContent() {
                self.isDraggingContent = true
                self.startWatchdog()
            }

            guard self.isDraggingContent else { return }
            // Republishing an unchanged value on every drag event would redraw
            // the panel dozens of times a second for nothing.
            let inside = self.activationRegion().contains(NSEvent.mouseLocation)
            if inside != self.isNearNotch { self.isNearNotch = inside }
        }

        add(.leftMouseUp) { [weak self] _ in self?.endDrag() }
    }

    /// Removes the monitors and clears the published state. Also the only place
    /// the monitors are released — the detector has no deinit, so an owner that
    /// discards it must call this first.
    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        endDrag()
    }

    private func add(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> Void) {
        // Global monitors are delivered on the main thread, which is where this
        // object lives; the hop keeps that promise explicit for the compiler.
        guard let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { handler(event) }
        }) else { return }
        monitors.append(monitor)
    }

    private func hasDroppableContent() -> Bool {
        dragPasteboard.types?.contains(where: Self.droppableTypes.contains) ?? false
    }

    private func startWatchdog() {
        releaseWatchdog?.invalidate()
        releaseWatchdog = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 { self.endDrag() }
            }
        }
    }

    private func endDrag() {
        releaseWatchdog?.invalidate()
        releaseWatchdog = nil
        buttonIsDown = false
        changeCountAtMouseDown = -1
        if isDraggingContent { isDraggingContent = false }
        if isNearNotch { isNearNotch = false }
    }
}
