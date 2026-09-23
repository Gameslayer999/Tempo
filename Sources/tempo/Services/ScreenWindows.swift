import AppKit

/// What the window server can say about the top of a display: whether a
/// full-screen app owns it, and whether the menu bar is currently drawn over
/// that app (decision 106).
///
/// Nothing read here is gated behind a TCC grant: `CGWindowListCopyWindowInfo`
/// withholds only `kCGWindowName` from a process without Screen Recording, and
/// this looks only at layer, owning pid, bounds and on-screen-ness. Confirmed
/// by running this exact code from a separate ad-hoc-signed bundle with no
/// grant of its own; Tempo has relied on the same call since decision 105.
///
/// Bounds come back in Quartz coordinates (origin top-left, y down), so the
/// display is taken from `CGDisplayBounds` rather than from `NSScreen.frame`
/// and no flipping between the two spaces is needed.
enum ScreenWindows {
    struct TopRow {
        /// The app whose window occupies the menu bar's row on this display —
        /// which is to say, the app owning a full-screen Space here. Nil when
        /// the row is free.
        let fullScreenApp: pid_t?
        /// Whether the menu bar is drawn over that app right now.
        ///
        /// Meaningful **only** when `fullScreenApp` is non-nil. On the desktop
        /// the bar is drawn by `MenuBarAgent`, whose window never enters the
        /// on-screen list, so this reads false there however visible the bar
        /// is — see `menuBarOverlayDown`'s note below.
        let menuBarOverlayDown: Bool
    }

    /// Both answers from one scan of the window list.
    ///
    /// **`menuBarOverlayDown` is the full-screen menu bar, not the menu bar.**
    /// Over a full-screen app the window server slides a layer-24 window of its
    /// own down from above the top edge; on the desktop that window stays
    /// parked and the bar is somebody else's. Measured on the LG ULTRAWIDE
    /// inside a full-screen Space, dumping every window ~30pt tall from
    /// `.optionAll`:
    ///
    ///     pointer in the middle   Window Server @24 {0, -30, 3440, 30}  onscreen absent
    ///     pointer at the top edge Window Server @24 {0,   0, 3440, 30}  onscreen TRUE
    ///
    /// and every full-screen toolbar on the machine moved down with it in the
    /// same sample (Ghostty 0 -> 30, Chrome 0 -> 30, Spotify -32 -> 30), which
    /// is the bar pushing them out of its row. Timed on the same display:
    /// **461ms** from the pointer reaching the edge to the bar arriving, and
    /// 277ms from the pointer leaving to it going away.
    ///
    /// Matched by `isOnscreen` rather than by owner name — `MenuBarAgent`'s
    /// window sits at `{0, 0, 3440, 30}` at all times and is never on screen,
    /// so on-screen-ness is what separates the two without depending on a
    /// process name that could be localised or renamed.
    ///
    /// A previous attempt read this as a general "is the menu bar visible"
    /// signal and it is not: on the desktop it reads false permanently, which
    /// over a 60s run looked like a signal that blinks. Do not use it outside
    /// a full-screen Space.
    static func topRow(on screen: NSScreen) -> TopRow {
        guard let display = displayBounds(screen) else {
            return TopRow(fullScreenApp: nil, menuBarOverlayDown: false)
        }
        let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] ?? []

        var fullScreenApp: pid_t?
        var menuBarOverlayDown = false
        for window in list {
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  let rect = bounds(window) else { continue }

            if layer == menuBarLayer, !menuBarOverlayDown,
               abs(rect.minY - display.minY) < 1,
               rect.width >= display.width * 0.9,
               rect.height > 0, rect.height < display.height / 2 {
                menuBarOverlayDown = true
                continue
            }

            // An app window sitting in the menu bar's row and spanning the
            // display, owned by a *regular* running app.
            //
            // **Not "one window covers the whole display"**, which is the
            // obvious test and is wrong. Ghostty in full screen presents a
            // single `{0, 0, 3440, 1440}` window and passes it; Chrome presents
            // four — `{0,0,3440,41}` tab strip, `{0,41,3440,47}` toolbar,
            // `{0,0,3440,124}` overlay, `{0,88,3440,1352}` content — and not
            // one of them covers the display, so the test returned nil and the
            // caller fell through to its desktop branch. Measured; it is why
            // the first version of decision 106 fixed Ghostty and not Chrome.
            //
            // Occupying the row is also the more honest question, because the
            // row being contested is the entire reason any of this is asked.
            // An ordinary window cannot reach it: macOS keeps the menu bar's
            // row reserved, so a desktop Chrome sits at `{0, 88, …}` and a
            // zoomed window starts below the bar.
            //
            // The owner check is not decoration either: the window server puts
            // a covering window up for about a second during a Space
            // transition, and without it that transient reads as a full-screen
            // app arriving and leaving again (measured).
            if layer == 0, fullScreenApp == nil,
               rect.minY <= display.minY + 1,
               rect.width >= display.width * 0.9,
               rect.intersects(display),
               let pid = window[kCGWindowOwnerPID as String] as? pid_t,
               NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular {
                fullScreenApp = pid
            }
        }
        return TopRow(fullScreenApp: fullScreenApp, menuBarOverlayDown: menuBarOverlayDown)
    }

    /// Whether a full-screen app owns the Space currently shown on `screen`.
    ///
    /// Either term alone is incomplete, and both are needed for the same
    /// reason: revealing the menu bar over a full-screen app pushes the app's
    /// own windows out of the row (Chrome's tab strip moves `{0,0,…}` ->
    /// `{0,30,…}`, measured). So while the bar is down no app window is in the
    /// row and `fullScreenApp` is nil — but the overlay is only ever drawn over
    /// a full-screen app, which makes it the other half of the answer.
    ///
    /// Measured on the LG ULTRAWIDE, sampled every 0.2–0.5s across a 60s run:
    /// it tracked every Space change the user made, reported full screen for
    /// exactly the full-screen intervals, and never flickered within a state.
    /// `.optionOnScreenOnly` reports the Space currently on screen, which is
    /// the one being asked about — Tempo is `.canJoinAllSpaces`, so that is
    /// always the Space it is displayed on.
    static func isFullScreen(on screen: NSScreen) -> Bool {
        let top = topRow(on: screen)
        return top.fullScreenApp != nil || top.menuBarOverlayDown
    }

    /// `kCGMainMenuWindowLevel`. Tempo's own panel is one level above this
    /// (`.statusBar`, 25) and is `panelWidth` wide, so it cannot match.
    private static let menuBarLayer = 24

    private static func bounds(_ window: [String: Any]) -> CGRect? {
        guard let dict = window[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dict as CFDictionary)
    }

    /// The display's rect in the window list's own coordinate space. Returns
    /// nil for a screen with no backing `CGDirectDisplayID`, which does occur
    /// mid-reconfiguration; callers treat that as "not full screen" rather than
    /// as an error, which is the direction that leaves Tempo reachable.
    private static func displayBounds(_ screen: NSScreen) -> CGRect? {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else { return nil }
        return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
    }
}
