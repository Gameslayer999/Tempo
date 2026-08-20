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
        static let favoritePlaylists = "favoritePlaylists"
        static let panelStyle = "panelStyle"
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

    /// Material of the expanded panel (decision 029). Persisted by raw value,
    /// so an unknown string from a future/older build falls back to `.regular`
    /// rather than failing to decode.
    @Published var panelStyle: PanelStyle {
        didSet { defaults.set(panelStyle.rawValue, forKey: Key.panelStyle) }
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

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.showVisualizer: true,
            Key.showUsageGraph: true,
            Key.showAgentLights: true,
        ])
        self.defaults = defaults
        showVisualizer = defaults.bool(forKey: Key.showVisualizer)
        showUsageGraph = defaults.bool(forKey: Key.showUsageGraph)
        showAgentLights = defaults.bool(forKey: Key.showAgentLights)
        panelStyle = PanelStyle(rawValue: defaults.string(forKey: Key.panelStyle) ?? "") ?? .regular
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

/// The four materials the expanded panel can be drawn in (decision 029).
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
