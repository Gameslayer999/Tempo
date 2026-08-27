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
        static let accentSource = "accentSource"
        static let customAccentHex = "customAccentHex"
        static let albumGlow = "albumGlow"
        static let albumGlowStrength = "albumGlowStrength"
        static let albumArtBlur = "albumArtBlur"
        static let spectrogramPalette = "spectrogramPalette"
        static let sneakPeek = "sneakPeek"
        static let sneakPeekSeconds = "sneakPeekSeconds"
        static let mediaIdleSeconds = "mediaIdleSeconds"
        static let musicControlSlots = "musicControlSlots"
        static let hideFromScreenCapture = "hideFromScreenCapture"
        static let preferredDisplayUUID = "preferredDisplayUUID"
        static let fullScreenBehavior = "fullScreenBehavior"
        static let showUsageHistory = "showUsageHistory"
        static let showRateLimitPace = "showRateLimitPace"
        static let rateLimitWindowTokens = "rateLimitWindowTokens"
        static let rateLimitWarnPercent = "rateLimitWarnPercent"
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

    // MARK: - Appearance

    /// Where the accent colour comes from (decision 069). The accent tints
    /// chrome only — chips, rims, the scrubber, drop targets. It deliberately
    /// never reaches the agent lights, whose hues carry state (UI Principle #2).
    @Published var accentSource: AccentSource {
        didSet { defaults.set(accentSource.rawValue, forKey: Key.accentSource) }
    }

    /// The custom accent, as `#RRGGBB`. Only consulted when
    /// `accentSource == .custom`; an unparseable string falls back to the
    /// system accent rather than to an arbitrary colour.
    @Published var customAccentHex: String {
        didSet { defaults.set(customAccentHex, forKey: Key.customAccentHex) }
    }

    /// Whether a bloom in the cover's own colour is painted behind the
    /// artwork (decision 070). Painted, not composited: decision 064 measured
    /// that `glassEffect` contributes no pixels of its own.
    @Published var albumGlow: Bool {
        didSet { defaults.set(albumGlow, forKey: Key.albumGlow) }
    }

    /// How far the bloom carries, 0...1, scaling both its radius and its peak
    /// alpha together so one control covers "barely there" to "unmistakable".
    @Published var albumGlowStrength: Double {
        didSet { defaults.set(albumGlowStrength, forKey: Key.albumGlowStrength) }
    }

    /// Whether a blurred copy of the cover sits behind the artwork
    /// (decision 070). Independent of `albumGlow` — boringNotch ships these as
    /// two switches and they read as two different looks.
    @Published var albumArtBlur: Bool {
        didSet { defaults.set(albumArtBlur, forKey: Key.albumArtBlur) }
    }

    /// How the visualizer bars are coloured (decision 071). The tap already
    /// publishes five band magnitudes, so this is a colour mapping over data
    /// that is already there, not a new capture path.
    @Published var spectrogramPalette: SpectrogramPalette {
        didSet { defaults.set(spectrogramPalette.rawValue, forKey: Key.spectrogramPalette) }
    }

    // MARK: - Media

    /// Whether a track change flashes the title and artist under the notch
    /// without expanding the panel (decision 072).
    @Published var sneakPeek: Bool {
        didSet { defaults.set(sneakPeek, forKey: Key.sneakPeek) }
    }

    /// How long that flash stays up, in seconds.
    @Published var sneakPeekSeconds: Double {
        didSet { defaults.set(sneakPeekSeconds, forKey: Key.sneakPeekSeconds) }
    }

    /// How long playback may stay paused before the notch stops treating media
    /// as active and drops the wings (decision 073). This was a hard-coded 60s
    /// in `MediaRemoteService`; the value was always a matter of taste — a
    /// pause to take a call is not the end of listening — so it becomes a
    /// setting rather than a constant. 0 means never drop it.
    @Published var mediaIdleSeconds: Double {
        didSet { defaults.set(mediaIdleSeconds, forKey: Key.mediaIdleSeconds) }
    }

    /// The transport row, left to right (decision 074). Persisted as raw
    /// strings so an unknown control from a future build degrades to an empty
    /// slot instead of failing to decode the whole row.
    @Published var musicControlSlots: [MusicControl] {
        didSet {
            defaults.set(musicControlSlots.map(\.rawValue), forKey: Key.musicControlSlots)
        }
    }

    // MARK: - Window behaviour

    /// Whether the panel is excluded from screen capture and sharing
    /// (decision 077). Agent lights and `cwd` labels are exactly what should
    /// not land in a screen share.
    @Published var hideFromScreenCapture: Bool {
        didSet { defaults.set(hideFromScreenCapture, forKey: Key.hideFromScreenCapture) }
    }

    /// Which display the strip hugs, as a `CGDisplayCreateUUIDFromDisplayID`
    /// string (decision 075). Empty means automatic — the built-in notched
    /// display when it is available. A UUID rather than a display ID because
    /// display IDs are reassigned across reconnects.
    @Published var preferredDisplayUUID: String {
        didSet {
            defaults.set(preferredDisplayUUID, forKey: Key.preferredDisplayUUID)
            NotchGeometry.pinnedDisplayUUID = preferredDisplayUUID
        }
    }

    /// What the panel does when an app goes full screen (decision 076).
    @Published var fullScreenBehavior: FullScreenBehavior {
        didSet { defaults.set(fullScreenBehavior.rawValue, forKey: Key.fullScreenBehavior) }
    }

    // MARK: - Agents

    /// Whether the panel carries the token-history panel (decision 079).
    /// Off by default: it reads Claude Code's transcripts across every project,
    /// which is a wider read than the per-session figures, so it is opt-in.
    @Published var showUsageHistory: Bool {
        didSet { defaults.set(showUsageHistory, forKey: Key.showUsageHistory) }
    }

    /// Whether the estimated rate-limit pace bar is shown (decision 079).
    /// Off by default, and labelled an estimate wherever it appears: Claude
    /// Code persists no real rate-limit signal locally, so this is computed
    /// from transcript tokens in a rolling window and can only ever
    /// approximate (UI Principle #4 — never show a lying signal).
    @Published var showRateLimitPace: Bool {
        didSet { defaults.set(showRateLimitPace, forKey: Key.showRateLimitPace) }
    }

    /// The token budget the pace bar measures against, for one rolling
    /// five-hour window. User-set because the real number is account-dependent
    /// and Anthropic does not publish it in a form Tempo can read.
    @Published var rateLimitWindowTokens: Double {
        didSet { defaults.set(rateLimitWindowTokens, forKey: Key.rateLimitWindowTokens) }
    }

    /// Percentage of that budget at which the pace bar switches to its warning
    /// appearance.
    @Published var rateLimitWarnPercent: Double {
        didSet { defaults.set(rateLimitWarnPercent, forKey: Key.rateLimitWarnPercent) }
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

    static let defaultAlbumGlowStrength: Double = 0.55

    static let defaultSneakPeekSeconds: Double = 3
    static let minSneakPeekSeconds: Double = 1
    static let maxSneakPeekSeconds: Double = 10

    /// Matches the constant this preference replaced, so an install that never
    /// touches the slider behaves exactly as it did before (Agent Guideline #7).
    static let defaultMediaIdleSeconds: Double = 60
    static let minMediaIdleSeconds: Double = 0
    static let maxMediaIdleSeconds: Double = 600

    /// The transport row is always this many slots wide, so the middle slot
    /// stays on the column's centre line under the title.
    static let musicControlSlotCount = 5
    static let defaultMusicControlSlots: [MusicControl] = [.none, .previous, .playPause, .next, .none]

    /// A round number, not a measured limit — see `rateLimitWindowTokens`.
    ///
    /// Sized against this machine's own history rather than guessed: counting
    /// the way Tempo counts (cache reads excluded), the busiest five-hour
    /// window in the last seven days measured 5.30M tokens. A 5M default would
    /// therefore have shown a bar reading 106% on the first day it was
    /// switched on, which is a false alarm, not a signal — so the default sits
    /// clear of the observed peak. Settings shows that measured busiest window
    /// beside the slider so the number can be calibrated rather than guessed.
    static let defaultRateLimitWindowTokens: Double = 10_000_000
    static let minRateLimitWindowTokens: Double = 500_000
    static let maxRateLimitWindowTokens: Double = 50_000_000

    static let defaultRateLimitWarnPercent: Double = 80
    static let minRateLimitWarnPercent: Double = 50
    static let maxRateLimitWarnPercent: Double = 99

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
            Key.accentSource: AccentSource.system.rawValue,
            Key.albumGlow: true,
            Key.albumGlowStrength: Self.defaultAlbumGlowStrength,
            Key.albumArtBlur: false,
            Key.spectrogramPalette: SpectrogramPalette.monochrome.rawValue,
            Key.sneakPeek: true,
            Key.sneakPeekSeconds: Self.defaultSneakPeekSeconds,
            Key.mediaIdleSeconds: Self.defaultMediaIdleSeconds,
            Key.hideFromScreenCapture: false,
            Key.fullScreenBehavior: FullScreenBehavior.never.rawValue,
            Key.showUsageHistory: false,
            Key.showRateLimitPace: false,
            Key.rateLimitWindowTokens: Self.defaultRateLimitWindowTokens,
            Key.rateLimitWarnPercent: Self.defaultRateLimitWarnPercent,
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

        accentSource = AccentSource(rawValue: defaults.string(forKey: Key.accentSource) ?? "")
            ?? .system
        customAccentHex = defaults.string(forKey: Key.customAccentHex) ?? ""
        albumGlow = defaults.bool(forKey: Key.albumGlow)
        albumGlowStrength = min(max(defaults.double(forKey: Key.albumGlowStrength), 0), 1)
        albumArtBlur = defaults.bool(forKey: Key.albumArtBlur)
        spectrogramPalette = SpectrogramPalette(
            rawValue: defaults.string(forKey: Key.spectrogramPalette) ?? ""
        ) ?? .monochrome

        sneakPeek = defaults.bool(forKey: Key.sneakPeek)
        sneakPeekSeconds = min(max(defaults.double(forKey: Key.sneakPeekSeconds),
                                   Self.minSneakPeekSeconds), Self.maxSneakPeekSeconds)
        mediaIdleSeconds = min(max(defaults.double(forKey: Key.mediaIdleSeconds),
                                   Self.minMediaIdleSeconds), Self.maxMediaIdleSeconds)
        // A row of the wrong width would leave the play button off the centre
        // line, so a stored value that is not exactly `musicControlSlotCount`
        // long is discarded rather than padded.
        let storedSlots = (defaults.stringArray(forKey: Key.musicControlSlots) ?? [])
            .map { MusicControl(rawValue: $0) ?? .none }
        musicControlSlots = storedSlots.count == Self.musicControlSlotCount
            ? storedSlots
            : Self.defaultMusicControlSlots

        hideFromScreenCapture = defaults.bool(forKey: Key.hideFromScreenCapture)
        preferredDisplayUUID = defaults.string(forKey: Key.preferredDisplayUUID) ?? ""
        fullScreenBehavior = FullScreenBehavior(
            rawValue: defaults.string(forKey: Key.fullScreenBehavior) ?? ""
        ) ?? .never

        showUsageHistory = defaults.bool(forKey: Key.showUsageHistory)
        showRateLimitPace = defaults.bool(forKey: Key.showRateLimitPace)
        rateLimitWindowTokens = min(max(defaults.double(forKey: Key.rateLimitWindowTokens),
                                        Self.minRateLimitWindowTokens), Self.maxRateLimitWindowTokens)
        rateLimitWarnPercent = min(max(defaults.double(forKey: Key.rateLimitWarnPercent),
                                       Self.minRateLimitWarnPercent), Self.maxRateLimitWarnPercent)

        // After every stored property is initialised, so `self` is readable.
        NotchGeometry.pinnedDisplayUUID = preferredDisplayUUID
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

/// Where the accent colour comes from (decision 069).
enum AccentSource: String, CaseIterable, Identifiable {
    case system, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System accent"
        case .custom: return "Custom"
        }
    }

    var detail: String {
        switch self {
        case .system: return "Follows the accent colour set in System Settings ▸ Appearance."
        case .custom: return "A colour picked here, independent of the system accent."
        }
    }
}

/// How the visualizer bars are coloured (decision 071).
///
/// The tap already publishes five band magnitudes, so every option below is a
/// colour mapping over data that is already being computed — none of them adds
/// a capture path or a per-frame cost beyond the fill itself.
enum SpectrogramPalette: String, CaseIterable, Identifiable {
    case monochrome, accent, album, spectrum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monochrome: return "White"
        case .accent: return "Accent colour"
        case .album: return "Album colour"
        case .spectrum: return "Spectrum"
        }
    }

    var detail: String {
        switch self {
        case .monochrome: return "Every bar white, as it has always been."
        case .accent: return "Every bar in the accent colour."
        case .album: return "Every bar in the current cover's dominant colour, falling back to white with no artwork."
        case .spectrum: return "A hue per band, bass through treble, so the shape of the sound reads as colour as well as height."
        }
    }
}

/// What the panel does when an app goes full screen (decision 076).
///
/// `never` is the behaviour every build before this decision had, and stays the
/// default so nothing changes for anyone who does not go looking (Agent
/// Guideline #7).
enum FullScreenBehavior: String, CaseIterable, Identifiable {
    case never, mediaApp, allApps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: return "Never hide"
        case .mediaApp: return "Hide for the app that's playing"
        case .allApps: return "Hide for all apps"
        }
    }

    var detail: String {
        switch self {
        case .never: return "The strip stays over full-screen apps, as it always has."
        case .mediaApp: return "The strip hides only when the app currently playing goes full screen — a full-screen video keeps its own controls, everything else keeps the notch."
        case .allApps: return "Any full-screen app hides the strip. The panel still opens if you move the pointer to the notch."
        }
    }
}

/// One position in the transport row (decision 074).
///
/// The palette is deliberately limited to actions Tempo can actually perform:
/// `MediaRemoteService` exposes previous / play-pause / next and nothing else,
/// and mute is Tempo's own via `AudioOutputService`. Add-to-playlist is
/// deliberately absent — it needs a *target* playlist, and that selection is
/// state owned by `PlaylistSection`, which already carries its own add button;
/// a transport slot with no playlist chosen would be a lying control
/// (UI Principle #4).
enum MusicControl: String, CaseIterable, Identifiable {
    case none, previous, playPause, next, mute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Empty"
        case .previous: return "Previous"
        case .playPause: return "Play / Pause"
        case .next: return "Next"
        case .mute: return "Mute"
        }
    }

    /// The glyph shown in the row and in the Settings palette. `playPause` and
    /// `mute` swap glyph with live state, so the value here is only the
    /// resting one.
    var symbol: String {
        switch self {
        case .none: return "circle.dashed"
        case .previous: return "backward.fill"
        case .playPause: return "playpause.fill"
        case .next: return "forward.fill"
        case .mute: return "speaker.slash.fill"
        }
    }
}

extension Preferences {
    /// The accent colour to paint chrome with, resolved from `accentSource`.
    ///
    /// Returns `nil` for "use the system accent", which is what every call site
    /// wants as its fallback anyway — an unparseable custom hex therefore
    /// degrades to the system accent rather than to an arbitrary colour
    /// (Agent Guideline #3: fail silent, degrade gracefully).
    var resolvedAccent: NSColor? {
        guard accentSource == .custom else { return nil }
        return Self.color(fromHex: customAccentHex)
    }

    /// Parses `#RRGGBB` / `RRGGBB`. Anything else is `nil`.
    static func color(fromHex hex: String) -> NSColor? {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    /// `#RRGGBB` for a colour, for writing back to `customAccentHex`.
    static func hex(from color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "" }
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }
}
