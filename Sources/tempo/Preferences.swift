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
        static let collapsedAgentLight = "collapsedAgentLight"
        static let favoritePlaylists = "favoritePlaylists"
        static let panelStyle = "panelStyle"
        static let hoverExpandDelayMS = "hoverExpandDelayMS"
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
            Key.collapsedAgentLight: CollapsedAgentLightMode.summary.rawValue,
            Key.hoverExpandDelayMS: Self.defaultHoverExpandDelayMS,
        ])
        self.defaults = defaults
        showVisualizer = defaults.bool(forKey: Key.showVisualizer)
        showUsageGraph = defaults.bool(forKey: Key.showUsageGraph)
        showAgentLights = defaults.bool(forKey: Key.showAgentLights)
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
