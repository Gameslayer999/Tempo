import AppKit

/// Whether the macOS menu bar is currently *down* — visible on screen rather
/// than retracted above the top edge (decision 091).
///
/// There is no API for this. `NSMenu.menuBarVisible()` answers a different
/// question (app-level hiding), and `NSScreen.visibleFrame` does not move at
/// all when the bar auto-reveals — measured on this machine: `visibleFrame`
/// reserved the same 30pt in both states. The Accessibility API can see the
/// real bar but costs a TCC grant Tempo has never needed.
///
/// What does track it, exactly, is a status item's own window. Status items
/// ride the menu bar, so the window slides with it. Measured on this machine
/// with a probe, on a 1440pt-tall screen with a 30pt bar:
///
///     bar hidden   window y = 1440  (entirely above the screen's top edge)
///     sliding      window y = 1434 … 1416
///     bar down     window y = 1410  (occupying the menu bar row, 1410…1440)
///
/// So the item is a sensor, not a UI: it is zero-length, its button draws
/// nothing, and it exists only while `NotchHoverDetector` is running — the one
/// mode where Tempo has to answer this question (decision 055). Everywhere
/// else Tempo puts nothing in the menu bar.
@MainActor
final class MenuBarSensor {
    private var item: NSStatusItem?

    func start() {
        guard item == nil else { return }
        // Zero-length: the button is 0pt wide and draws nothing. The window
        // around it is still laid out in the menu bar, which is the whole
        // point — that window is the thing being read.
        let item = NSStatusBar.system.statusItem(withLength: 0)
        item.button?.title = ""
        item.button?.image = nil
        self.item = item
    }

    func stop() {
        guard let item else { return }
        NSStatusBar.system.removeStatusItem(item)
        self.item = nil
    }

    /// Height of the menu bar's row on screen, measured from the sensor's own
    /// window rather than asked for (decision 095): `NSStatusBar.system
    /// .thickness` reports 22 on this machine while the bar actually occupies
    /// 30pt, and it is the 30 that the pointer is inside. Falls back to that
    /// thickness before the item exists.
    var barHeight: CGFloat {
        item?.button?.window?.frame.height ?? NSStatusBar.system.thickness
    }

    /// True only when the bar is *fully* down. The slide's intermediate frames
    /// hang off the top of the screen and read false, so the gate opens when
    /// the bar has arrived rather than while it is still on its way.
    ///
    /// Anchored to the menu bar's *row* rather than to the screen's top edge
    /// (decision 103). The row is what the sensor window comes to rest on, and
    /// it is the one part of this geometry that holds across displays; how tall
    /// the window is, and how it sits within the row, does not. Measured on the
    /// external LG ULTRAWIDE the window is 34pt and centred on the 30pt row, so
    /// it rests 2pt *proud* of `screen.frame.maxY` — which the previous
    /// `maxY <= screen.frame.maxY + 0.5` read as "not down", permanently, and
    /// with it went the only way to open the undrawn notch. Comparing the
    /// window's bottom edge against the row's top, with slack for that
    /// centring, reads every state on record correctly: LG at rest 1408, and on
    /// the built-in panel fully down 1410, sliding 1416…1434, hidden 1440.
    var isMenuBarDown: Bool {
        guard let window = item?.button?.window else { return false }
        let frame = window.frame
        // Retracted, the window sits entirely above the screen and intersects
        // nothing — which is already the answer.
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) else {
            return false
        }
        // `visibleFrame`'s top inset is the bar's row. It is reserved whether
        // the bar is shown or hidden (decision 091 measured that), which is
        // exactly what makes it a stable reference rather than a second signal.
        let barRow = screen.frame.maxY - screen.visibleFrame.maxY
        return frame.minY <= screen.frame.maxY - barRow + Self.rowSlack
    }

    /// How far above the row's top the sensor window may rest and still count
    /// as arrived. Covers the window being taller than the row and centred on
    /// it (2pt on the LG); stays well below the 6pt gap to the nearest sliding
    /// frame on record, so "fully down only" survives.
    private static let rowSlack: CGFloat = 4
}
