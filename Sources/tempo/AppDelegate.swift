import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel?
    private var state: AppState?
    private var media: MediaRemoteService?
    private var shelf: ShelfService?
    private var audio: AudioOutputService?
    private var dragDetector: DragDetector?
    private var hoverDetector: NotchHoverDetector?
    private var music: MusicService?
    private var agentStatus: AgentStatusService?
    private var sessionStats: SessionStatsService?
    private var spotifyAPI: SpotifyWebAPI?
    private var location: LocationService?
    private var weather: WeatherService?
    private var screenLock: ScreenLockService?
    private var lockCards: LockScreenNotifier?
    private var onboarding: OnboardingController?
    private var settingsWindow: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppState()
        let media = MediaRemoteService(state: state)
        let shelf = ShelfService()
        let audio = AudioOutputService()
        let dragDetector = DragDetector()
        let hoverDetector = NotchHoverDetector(state: state)
        let music = MusicService(state: state)
        let agentStatus = AgentStatusService(state: state)
        let sessionStats = SessionStatsService(state: state)
        let spotifyAPI = SpotifyWebAPI()
        let prefs = Preferences.shared
        let location = LocationService(prefs: prefs)
        let weather = WeatherService(location: location, prefs: prefs)
        let screenLock = ScreenLockService()
        let lockCards = LockScreenNotifier(state: state, weather: weather, lock: screenLock, prefs: prefs)
        let onboarding = OnboardingController(state: state, prefs: prefs)
        let settingsWindow = SettingsWindowController(
            prefs: prefs,
            api: spotifyAPI,
            state: state,
            weather: weather,
            location: location,
            lockCards: lockCards,
            onboarding: onboarding
        )

        self.state = state
        self.settingsWindow = settingsWindow
        self.media = media
        self.shelf = shelf
        self.audio = audio
        self.dragDetector = dragDetector
        self.hoverDetector = hoverDetector
        self.music = music
        self.agentStatus = agentStatus
        self.sessionStats = sessionStats
        self.spotifyAPI = spotifyAPI
        self.location = location
        self.weather = weather
        self.screenLock = screenLock
        self.lockCards = lockCards
        self.onboarding = onboarding

        media.start()
        shelf.load()

        // The drag detector's region has to follow the notch across displays,
        // so it is a closure read per event rather than a captured rect
        // (decision 037).
        dragDetector.activationRegion = { NotchGeometry.dragActivationRegion }
        dragDetector.$isNearNotch
            .removeDuplicates()
            .sink { near in
                Task { @MainActor in
                    state.isDragTargeting = near
                }
            }
            .store(in: &cancellables)

        // Both switches gate the global mouse monitor itself: a shelf that is
        // switched off must not watch the user's dragging at all.
        prefs.$showFileShelf
            .sink { enabled in
                if enabled {
                    dragDetector.start()
                } else {
                    dragDetector.stop()
                    state.isDragTargeting = false
                }
            }
            .store(in: &cancellables)

        // The pointer monitor for the undrawn notch runs in exactly one mode —
        // strip switched off *and* no hardware notch to hug (decision 055) —
        // so it is gated on both the setting and the current display. The
        // screen generation is the display half: `applyGeometry` refreshes
        // `NotchGeometry` and then bumps it, so by the time this fires
        // `isHardwareNotch` is already the new answer. The emitted value is
        // used rather than re-reading the property, because `@Published` fires
        // from `willSet` and the property still holds the old value here.
        prefs.$showStripOnExternalDisplays
            .combineLatest(state.$screenGeneration)
            .sink { showStrip, _ in
                if !showStrip && !NotchGeometry.isHardwareNotch {
                    hoverDetector.start()
                } else {
                    hoverDetector.stop()
                }
            }
            .store(in: &cancellables)

        prefs.$showAudioOutput
            .sink { enabled in
                if enabled {
                    audio.start()
                } else {
                    audio.stop()
                }
            }
            .store(in: &cancellables)
        music.start()
        agentStatus.start()
        spotifyAPI.start()
        // Start sampling at launch (not first panel-open) so the usage graph
        // has real history the first time the user expands (~2 Mach calls/sec),
        // and stop entirely while the module is switched off — a hidden graph
        // should cost nothing. `@Published` replays the current value on
        // subscribe, so this also handles the launch-time state.
        prefs.$showUsageGraph
            .sink { enabled in
                if enabled {
                    SystemStatsService.shared.start()
                } else {
                    SystemStatsService.shared.stop()
                }
            }
            .store(in: &cancellables)

        // Same contract for the agent rows' token and timing figures
        // (decision 048), gated on *both* switches: the figures only exist on
        // those rows, so lights-off means the transcripts should not be read
        // either. Off drops every read cursor, so a disabled module opens no
        // files at all.
        prefs.$showAgentLights.combineLatest(prefs.$showAgentStats)
            .sink { lights, stats in
                if lights && stats {
                    sessionStats.start()
                } else {
                    sessionStats.stop()
                }
            }
            .store(in: &cancellables)

        // The lock-screen cards, and everything that feeds them (decision
        // 058). Gated on the master switch so an off feature costs nothing at
        // all: no notification centre calls, no lock observers.
        prefs.$showLockScreenCards
            .sink { enabled in
                if enabled {
                    lockCards.start()
                } else {
                    lockCards.stop()
                }
            }
            .store(in: &cancellables)

        // Weather is its own switch inside that: off means no network requests
        // and no location manager at all, which is the only honest way to
        // switch off a feature that reads the user's location (Guideline #5).
        prefs.$showLockScreenCards.combineLatest(prefs.$lockCardShowsWeather)
            .sink { cards, wantsWeather in
                if cards && wantsWeather {
                    weather.start()
                } else {
                    weather.stop()
                }
            }
            .store(in: &cancellables)

        // Standard editing key equivalents (⌘V, ⌘C, ⌘X, ⌘A, ⌘Z) are delivered
        // by the main menu, not by the text field: AppKit resolves them through
        // `NSApp.mainMenu.performKeyEquivalent` before the responder chain ever
        // sees the keystroke. An accessory app starts with no main menu at all,
        // which is why the Settings window's Client ID field silently refused
        // ⌘V. `LSUIElement` still means no menu bar is ever displayed — this
        // menu exists purely to carry the key equivalents.
        NSApp.mainMenu = Self.makeMainMenu()

        let content = ContentView(
            state: state,
            media: media,
            shelf: shelf,
            audio: audio,
            api: spotifyAPI,
            prefs: prefs,
            lockCards: lockCards,
            location: location,
            openSettings: { [weak settingsWindow] in settingsWindow?.show() },
            onboarding: onboarding
        )
        let panel = NotchPanel(state: state, prefs: prefs, content: content)
        panel.orderFrontRegardless()
        self.panel = panel

        // Last, and only after the panel exists: the hello unrolls out of the
        // notch, so there has to be a notch on screen to unroll from
        // (decision 057). A no-op on every run after the first.
        onboarding.startIfFirstRun()

        // The notification grant can be changed in System Settings behind our
        // back, so the live status is re-read whenever Tempo comes back to the
        // foreground rather than trusted from launch (UI Principle #4).
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { lockCards.refreshAuthorization() }
        }
    }

    /// Re-opening Tempo from Finder or the Dock while it is already running
    /// opens Settings. Without this it does nothing at all, and with the panel
    /// hidden — `showOnExternalDisplays` off and no built-in notch present —
    /// Settings would otherwise be unreachable, since the only other way in is
    /// the gear inside the panel (decision 054).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        settingsWindow?.show()
        return true
    }

    /// The MediaRemote stream is a `/usr/bin/perl` child process. Nothing
    /// reparents it on quit, so without this it would outlive Tempo and keep
    /// streaming to a pipe no one reads. (A crash is covered by SIGPIPE — the
    /// next write to the closed pipe kills it — but a clean quit while nothing
    /// is playing produces no write, so it has to be terminated explicitly.)
    func applicationWillTerminate(_ notification: Notification) {
        media?.stop()
        music?.stop()
        dragDetector?.stop()
        hoverDetector?.stop()
        audio?.stop()
        // Withdraws both cards: leaving them in Notification Center after the
        // app that posted them is gone is a signal with nothing behind it.
        lockCards?.stop()
        weather?.stop()
    }

    /// Minimal main menu: an app menu (the first item is always treated as
    /// such) and the standard Edit items. Titles are never shown — only the
    /// key equivalents matter here.
    private static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit Tempo",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        return mainMenu
    }
}
