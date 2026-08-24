import AppKit
import SwiftUI

/// Owns the one Settings window (decision 020).
///
/// The notch panel is deliberately non-activating and can never become key
/// (Agent Guideline #3), which also means it can never take keyboard input —
/// so Settings is a separate, ordinary `NSWindow`. Opening it is the one
/// moment Tempo takes focus, and only because the user explicitly asked for it
/// by clicking the gear. The activation policy stays `.accessory`, so no Dock
/// icon appears; an accessory app's windows can still become key once the app
/// is activated.
///
/// The window is built once and reused, so pane selection and an in-progress
/// Client ID edit survive a close/reopen.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let prefs: Preferences
    private let api: SpotifyWebAPI
    private let state: AppState

    init(prefs: Preferences, api: SpotifyWebAPI, state: AppState) {
        self.prefs = prefs
        self.api = api
        self.state = state
    }

    func show() {
        // The login item can be removed in System Settings behind our back;
        // re-read it every time rather than showing a stale toggle
        // (UI Principle #4).
        prefs.refreshLaunchAtLogin()

        let window = self.window ?? makeWindow()
        self.window = window
        // `ignoringOtherApps` is load-bearing, not legacy habit: measured on
        // macOS 26.6 that plain `NSApp.activate()` leaves the window visible
        // but *not* key (the panel that was clicked is non-activating, so the
        // system does not treat Tempo as the app the user is interacting
        // with), and a non-key window cannot take the Client ID text field's
        // keystrokes.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Tempo Settings"
        // Sidebar material runs up under the title bar, as in System Settings.
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        // Follow the user to whatever Space they're on. A plain window stays
        // put in the Space it was first opened on, so clicking the gear from
        // another desktop would silently switch Spaces (or appear to do
        // nothing) instead of showing Settings where the user is.
        // `.fullScreenAuxiliary` additionally lets it appear over a fullscreen
        // app, which the notch panel is reachable from.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 580, height: 360)
        window.contentView = NSHostingView(rootView: SettingsView(prefs: prefs, api: api, state: state))
        window.setFrameAutosaveName("TempoSettingsWindow")
        window.center()
        return window
    }
}
