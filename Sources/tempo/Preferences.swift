import AppKit
import Combine
import ServiceManagement

/// User-adjustable settings, edited in the Settings window (decision 020) and
/// read by the notch views.
///
/// Everything here is plain display preference, so it lives in `UserDefaults`;
/// the Spotify Client ID stays in Application Support beside the tokens
/// (`SpotifyWebAPI`), which is the one place with owner-only permissions.
/// Every key defaults to on, so a fresh install behaves exactly as it did
/// before this file existed.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let showVisualizer = "showVisualizer"
        static let showUsageGraph = "showUsageGraph"
        static let showAgentLights = "showAgentLights"
        static let showAgentStats = "showAgentStats"
        static let collapsedAgentLight = "collapsedAgentLight"
        static let favoritePlaylists = "favoritePlaylists"
        static let panelStyle = "panelStyle"
        static let hoverExpandDelayMS = "hoverExpandDelayMS"
        static let showFileShelf = "showFileShelf"
        static let showAudioOutput = "showAudioOutput"
        static let showStripOnExternalDisplays = "showStripOnExternalDisplays"
        static let showLockScreenCards = "showLockScreenCards"
        static let lockCardShowsWeather = "lockCardShowsWeather"
        static let lockCardShowsMusic = "lockCardShowsMusic"
        static let weatherUseLocation = "weatherUseLocation"
        static let weatherCity = "weatherCity"
        static let weatherCityName = "weatherCityName"
        static let weatherCityLatitude = "weatherCityLatitude"
        static let weatherCityLongitude = "weatherCityLongitude"
        static let weatherUnit = "weatherUnit"
        static let hasSeenHello = "hasSeenHello"
    }

    private let defaults: UserDefaults

    @Published var showVisualizer: Bool {
        didSet { defaults.set(showVisualizer, forKey: Key.showVisualizer) }
    }
    @Published var showUsageGraph: Bool {
        didSet { defaults.set(showUsageGraph, forKey: Key.showUsageGraph) }
    }
    @Published var showAgentLights: Bool {
        didSet { defaults.set(showAgentLights, forKey: Key.showAgentLights) }
    }

    /// Whether the agent rows carry token and timing figures (decision 048).
    /// Separate from `showAgentLights` because it is the one module that reads
    /// a *second* data source — Claude Code's transcripts — and switching it
    /// off must stop those reads entirely, not just hide the numbers.
    @Published var showAgentStats: Bool {
        didSet { defaults.set(showAgentStats, forKey: Key.showAgentStats) }
    }

    /// Whether the notch acts as a drop target for dragged files and shows
    /// the shelf (decision 051). Off means the global mouse monitor is never
    /// installed, so a disabled shelf watches nothing.
    @Published var showFileShelf: Bool {
        didSet { defaults.set(showFileShelf, forKey: Key.showFileShelf) }
    }

    /// Whether the expanded panel carries the output-device row and volume
    /// slider (decision 050).
    @Published var showAudioOutput: Bool {
        didSet { defaults.set(showAudioOutput, forKey: Key.showAudioOutput) }
    }

    /// Whether the *collapsed strip* is drawn when the display Tempo hugs has
    /// no hardware notch — the notchless fallback, which is what you get with
    /// the lid closed or on a Mac with no built-in notch (decisions 054, 055).
    ///
    /// Off does not disable Tempo there: the panel still opens when the
    /// pointer reaches the top middle of that display, it simply isn't drawn
    /// until it does, and it claims no clicks while undrawn. On (the default)
    /// is the behaviour that existed before this switch.
    @Published var showStripOnExternalDisplays: Bool {
        didSet { defaults.set(showStripOnExternalDisplays, forKey: Key.showStripOnExternalDisplays) }
    }

    /// Whether Tempo posts its lock-screen cards at all (decision 058).
    ///
    /// Off by default, and deliberately: the feature needs Notification
    /// authorization, and a fresh install must never open with a permission
    /// prompt nobody asked for. The hello screen is what turns it on, at the
    /// moment the user grants (decision 057).
    @Published var showLockScreenCards: Bool {
        didSet { defaults.set(showLockScreenCards, forKey: Key.showLockScreenCards) }
    }

    /// Which of the two cards get posted. Both on is the point of the feature;
    /// either can be switched off without disabling the other, and switching
    /// weather off is also what stops every location and network request
    /// (`WeatherService` is started from this).
    @Published var lockCardShowsWeather: Bool {
        didSet { defaults.set(lockCardShowsWeather, forKey: Key.lockCardShowsWeather) }
    }
    @Published var lockCardShowsMusic: Bool {
        didSet { defaults.set(lockCardShowsMusic, forKey: Key.lockCardShowsMusic) }
    }

    /// Whether weather follows the Mac's own location (decision 059). Off
    /// means the typed city below is the only source and CoreLocation is
    /// never asked for anything.
    @Published var weatherUseLocation: Bool {
        didSet { defaults.set(weatherUseLocation, forKey: Key.weatherUseLocation) }
    }

    /// The city typed in Settings ▸ Weather — the fallback when location is
    /// off, denied, or has produced no fix. Stored as typed; the coordinates
    /// it resolved to are cached separately in `cachedCityPlace`.
    @Published var weatherCity: String {
        didSet { defaults.set(weatherCity, forKey: Key.weatherCity) }
    }

    /// Degrees Fahrenheit or Celsius. Open-Meteo converts server-side, so this
    /// is a query parameter rather than a formatting step.
    @Published var weatherUnit: TemperatureUnit {
        didSet { defaults.set(weatherUnit.rawValue, forKey: Key.weatherUnit) }
    }

    /// Whether the first-run hello has already played (decision 057). The one
    /// preference with no Settings toggle of its own — Settings ▸ About has a
    /// "Show the welcome again" button that clears it, so replaying the
    /// onboarding never means hand-editing defaults (Agent Guideline #8).
    @Published var hasSeenHello: Bool {
        didSet { defaults.set(hasSeenHello, forKey: Key.hasSeenHello) }
    }

    /// Coordinates the typed city resolved to, cached so a relaunch does not
    /// re-geocode and so weather works before the network answers. Only ever
    /// holds a *typed* place — a CoreLocation fix is never written to disk
    /// (Agent Guideline #5).
    var cachedCityPlace: WeatherPlace? {
        get {
            let name = defaults.string(forKey: Key.weatherCityName) ?? ""
            guard defaults.object(forKey: Key.weatherCityLatitude) != nil else { return nil }
            return WeatherPlace(
                name: name,
                latitude: defaults.double(forKey: Key.weatherCityLatitude),
                longitude: defaults.double(forKey: Key.weatherCityLongitude)
            )
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.weatherCityName)
                defaults.removeObject(forKey: Key.weatherCityLatitude)
                defaults.removeObject(forKey: Key.weatherCityLongitude)
                return
            }
            defaults.set(newValue.name, forKey: Key.weatherCityName)
            defaults.set(newValue.latitude, forKey: Key.weatherCityLatitude)
            defaults.set(newValue.longitude, forKey: Key.weatherCityLongitude)
        }
    }

    /// Shape of the agent signal in the *collapsed* pill (decision 042).
    /// Independent of `showAgentLights`, which governs the expanded panel's
    /// per-session list. Persisted by raw value, so an unknown string from a
    /// future or older build falls back to the default rather than failing to
    /// decode.
    @Published var collapsedAgentLight: CollapsedAgentLightMode {
        didSet { defaults.set(collapsedAgentLight.rawValue, forKey: Key.collapsedAgentLight) }
    }

    /// Material of the expanded panel (decision 030). Persisted by raw value,
    /// so an unknown string from a future/older build falls back to `.regular`
    /// rather than failing to decode.
    @Published var panelStyle: PanelStyle {
        didSet { defaults.set(panelStyle.rawValue, forKey: Key.panelStyle) }
    }

    /// Dwell, in milliseconds, before hovering the collapsed pill expands the
    /// panel — and therefore before the haptic tick, which fires when the
    /// expansion actually triggers. Exposed as a setting because the right
    /// value is a matter of feel: too long and the tick fires into a trackpad
    /// the finger has already left, too short and a pointer crossing the notch
    /// flickers the panel open (decision 034, amends 011).
    @Published var hoverExpandDelayMS: Double {
        didSet { defaults.set(hoverExpandDelayMS, forKey: Key.hoverExpandDelayMS) }
    }

    /// Playlists to offer in the notch picker, chosen in Settings ▸ Music.
    /// Empty means "no choice made" and every writable playlist is offered, so
    /// the feature works before anyone visits Settings. Order is the order the
    /// user picked them in; the first is what the picker starts on.
    @Published var favoritePlaylistIDs: [String] {
        didSet { defaults.set(favoritePlaylistIDs, forKey: Key.favoritePlaylists) }
    }

    /// Mirrors `SMAppService`'s registration rather than caching a bool of our
    /// own: the login item can also be removed in System Settings ▸ General ▸
    /// Login Items, so the system is the source of truth and this is re-read
    /// every time the Settings window opens.
    @Published private(set) var launchAtLogin = false
    /// Set when a register/unregister call actually failed, for the Settings
    /// window to show. Never logged (it can name the user's paths).
    @Published private(set) var launchAtLoginError: String?
    /// `.requiresApproval` — registered, but the user must approve it in
    /// System Settings before it takes effect.
    @Published private(set) var launchAtLoginNeedsApproval = false

    /// `SMAppService.mainApp` registers *a bundle*. Run from the bare
    /// `swift build` binary there is no bundle to register, so the toggle is
    /// inert and the Settings window says why (Agent Guideline #3: degrade,
    /// never crash).
    let isBundled = Bundle.main.bundleIdentifier != nil

    static let defaultHoverExpandDelayMS: Double = 60
    static let minHoverExpandDelayMS: Double = 0
    static let maxHoverExpandDelayMS: Double = 400

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.showVisualizer: true,
            Key.showUsageGraph: true,
            Key.showAgentLights: true,
            Key.showAgentStats: true,
            Key.collapsedAgentLight: CollapsedAgentLightMode.summary.rawValue,
            Key.hoverExpandDelayMS: Self.defaultHoverExpandDelayMS,
            Key.showFileShelf: true,
            Key.showAudioOutput: true,
            Key.showStripOnExternalDisplays: true,
            Key.showLockScreenCards: false,
            Key.lockCardShowsWeather: true,
            Key.lockCardShowsMusic: true,
            Key.weatherUseLocation: true,
            Key.weatherUnit: TemperatureUnit.systemDefault.rawValue,
            Key.hasSeenHello: false,
        ])
        self.defaults = defaults
        showVisualizer = defaults.bool(forKey: Key.showVisualizer)
        showUsageGraph = defaults.bool(forKey: Key.showUsageGraph)
        showAgentLights = defaults.bool(forKey: Key.showAgentLights)
        showAgentStats = defaults.bool(forKey: Key.showAgentStats)
        showFileShelf = defaults.bool(forKey: Key.showFileShelf)
        showAudioOutput = defaults.bool(forKey: Key.showAudioOutput)
        showStripOnExternalDisplays = defaults.bool(forKey: Key.showStripOnExternalDisplays)
        showLockScreenCards = defaults.bool(forKey: Key.showLockScreenCards)
        lockCardShowsWeather = defaults.bool(forKey: Key.lockCardShowsWeather)
        lockCardShowsMusic = defaults.bool(forKey: Key.lockCardShowsMusic)
        weatherUseLocation = defaults.bool(forKey: Key.weatherUseLocation)
        weatherCity = defaults.string(forKey: Key.weatherCity) ?? ""
        weatherUnit = TemperatureUnit(rawValue: defaults.string(forKey: Key.weatherUnit) ?? "")
            ?? TemperatureUnit.systemDefault
        hasSeenHello = defaults.bool(forKey: Key.hasSeenHello)
        collapsedAgentLight = CollapsedAgentLightMode(
            rawValue: defaults.string(forKey: Key.collapsedAgentLight) ?? ""
        ) ?? .summary
        panelStyle = PanelStyle(rawValue: defaults.string(forKey: Key.panelStyle) ?? "") ?? .regular
        // Clamped on read, not just on write: a hand-edited defaults value
        // outside the slider's range would otherwise make the notch unusable.
        hoverExpandDelayMS = min(max(defaults.double(forKey: Key.hoverExpandDelayMS), Self.minHoverExpandDelayMS),
                                 Self.maxHoverExpandDelayMS)
        favoritePlaylistIDs = defaults.stringArray(forKey: Key.favoritePlaylists) ?? []
        refreshLaunchAtLogin()
    }

    func toggleFavoritePlaylist(_ id: String) {
        if let index = favoritePlaylistIDs.firstIndex(of: id) {
            favoritePlaylistIDs.remove(at: index)
        } else {
            favoritePlaylistIDs.append(id)
        }
    }

    func isFavoritePlaylist(_ id: String) -> Bool { favoritePlaylistIDs.contains(id) }

    /// Re-reads the live registration state from the system.
    func refreshLaunchAtLogin() {
        guard isBundled else {
            launchAtLogin = false
            launchAtLoginNeedsApproval = false
            return
        }
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        launchAtLoginNeedsApproval = status == .requiresApproval
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        guard isBundled else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLaunchAtLogin()
    }
}

/// The four materials the expanded panel can be drawn in (decision 030).
/// `regular`/`clear` map straight onto macOS 26's two real `Glass` variants;
/// `tinted` is `regular` carrying the album artwork's colour; `solid` opts out
/// of glass entirely.
enum PanelStyle: String, CaseIterable, Identifiable {
    case regular, clear, tinted, solid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular: return "Regular glass"
        case .clear: return "Clear glass"
        case .tinted: return "Album tint"
        case .solid: return "Solid"
        }
    }

    var detail: String {
        switch self {
        case .regular: return "Frosted glass that adapts to whatever is behind the notch."
        case .clear: return "Barely-there glass. The window behind shows through; a slight scrim keeps the text readable."
        case .tinted: return "Frosted glass tinted with the current album cover's dominant colour."
        case .solid: return "No glass — an opaque panel that reads as one slab with the notch."
        }
    }
}

/// How the collapsed pill shows agent state (decision 042).
enum CollapsedAgentLightMode: String, CaseIterable, Identifiable {
    case off, summary, perSession

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .summary: return "Summary dot"
        case .perSession: return "One dot per session"
        }
    }

    var detail: String {
        switch self {
        case .off: return "Nothing beside the notch — agent state is only in the expanded panel."
        case .summary: return "One dot beside the visualizer, coloured by the most urgent session: red for an error, orange when one needs you, pulsing white when one just finished, green while any are working, dim grey when all are idle."
        case .perSession: return "Up to three dots, most urgent first, each coloured for its own session. The rest are in the expanded panel."
        }
    }
}
